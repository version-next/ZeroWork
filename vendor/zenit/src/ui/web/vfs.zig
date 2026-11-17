//! In-memory filesystem behind `std.Io` for the Web DOM host.
//!
//! Target-independent: the tree, the descriptor table and the `std.Io.VTable`
//! filesystem entries compile natively too (unit-tested in `zig build
//! test-ui-core`); only clocks/randomness are injected (`Hooks`). The browser
//! glue (`web_io.zig`) installs one global `Vfs` and mirrors it into IndexedDB
//! through the dirty-path set (`takeDirty`/`taken`/`releaseTaken`) and `import`.
//!
//! Semantics follow POSIX closely enough for desktop code that branches on std
//! errors: FileNotFound / NotDir / IsDir / PathAlreadyExists / DirNotEmpty.
//! Paths: absolute ("/a/b") or relative to the given `Dir`; `Dir.cwd()` is "/".
//! No symlinks, permissions or owners (accepted and ignored). Hard links share
//! the file node. Directory iteration is name-ordered and stable under
//! concurrent deletion (the cursor is the last returned name).
const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;

pub const Handle = File.Handle;
pub const NodeId = u32;
const root_id: NodeId = 0;
/// Descriptors handed out start here (clear of stdio and WASI preopens).
const fd_base: i32 = 64;
const cwd_handle: Handle = Dir.cwd().handle;

pub const Hooks = struct {
    /// Wall clock, nanoseconds since the Unix epoch.
    now_ns: *const fn () i96,
    random: *const fn (buffer: []u8) void,
    /// Receives bytes written to stdout/stderr (handles 1 and 2); null = drop.
    console: ?*const fn (bytes: []const u8) void = null,
};

const Kind = enum { file, dir };

const Child = struct { name: []u8, node: NodeId };

const Node = struct {
    kind: Kind,
    /// File contents.
    data: std.ArrayList(u8) = .empty,
    /// Directory entries, sorted by name.
    children: std.ArrayList(Child) = .empty,
    /// Primary link (directories have exactly one).
    parent: NodeId,
    name: []u8,
    links: u32,
    open: u32 = 0,
    atime: i96,
    mtime: i96,
    ctime: i96,
};

const Fd = struct {
    node: NodeId,
    pos: u64 = 0,
    read: bool,
    write: bool,
};

pub const EntryKind = enum(u32) { deleted = 0, file = 1, dir = 2 };

/// One dirty path resolved at `takeDirty` time (pointers valid until
/// `releaseTaken` or the next filesystem mutation).
pub const Taken = struct {
    path: []const u8,
    kind: EntryKind,
    data: []const u8,
    mtime_ns: i96,
};

pub const Vfs = struct {
    gpa: Allocator,
    hooks: Hooks,
    nodes: std.ArrayList(?Node) = .empty,
    free_nodes: std.ArrayList(NodeId) = .empty,
    fds: std.ArrayList(?Fd) = .empty,
    /// Absolute paths changed since the last `takeDirty` (owned keys).
    dirty: std.StringArrayHashMapUnmanaged(void) = .empty,
    taken: std.ArrayList([]const u8) = .empty,
    /// Off while importing a persisted snapshot.
    track: bool = true,

    pub fn init(gpa: Allocator, hooks: Hooks) Allocator.Error!Vfs {
        var v: Vfs = .{ .gpa = gpa, .hooks = hooks };
        try v.ensureRoot();
        return v;
    }

    /// Statically initializable; the root directory is created on first use.
    pub fn lazy(gpa: Allocator, hooks: Hooks) Vfs {
        return .{ .gpa = gpa, .hooks = hooks };
    }

    fn ensureRoot(v: *Vfs) Allocator.Error!void {
        if (v.nodes.items.len != 0) return;
        const t = v.hooks.now_ns();
        try v.nodes.append(v.gpa, .{ .kind = .dir, .parent = root_id, .name = &.{}, .links = 1, .atime = t, .mtime = t, .ctime = t });
    }

    fn ready(v: *Vfs) *Vfs {
        v.ensureRoot() catch @panic("web vfs: out of memory");
        return v;
    }

    pub fn deinit(v: *Vfs) void {
        for (v.nodes.items) |*slot| if (slot.*) |*n| v.freeNodeMem(n);
        v.nodes.deinit(v.gpa);
        v.free_nodes.deinit(v.gpa);
        v.fds.deinit(v.gpa);
        v.releaseTaken();
        v.taken.deinit(v.gpa);
        for (v.dirty.keys()) |k| v.gpa.free(k);
        v.dirty.deinit(v.gpa);
        v.* = undefined;
    }

    fn freeNodeMem(v: *Vfs, n: *Node) void {
        n.data.deinit(v.gpa);
        for (n.children.items) |c| v.gpa.free(c.name);
        n.children.deinit(v.gpa);
        v.gpa.free(n.name);
    }

    pub fn io(v: *Vfs) Io {
        return .{ .userdata = v, .vtable = &vtable };
    }

    // ── nodes ───────────────────────────────────────────────────────────

    fn node(v: *Vfs, id: NodeId) *Node {
        return &v.nodes.items[id].?;
    }

    fn newNode(v: *Vfs, kind: Kind, parent: NodeId, name: []const u8) Allocator.Error!NodeId {
        const owned = try v.gpa.dupe(u8, name);
        errdefer v.gpa.free(owned);
        const t = v.hooks.now_ns();
        const n: Node = .{ .kind = kind, .parent = parent, .name = owned, .links = 0, .atime = t, .mtime = t, .ctime = t };
        if (v.free_nodes.pop()) |id| {
            v.nodes.items[id] = n;
            return id;
        }
        try v.nodes.append(v.gpa, n);
        return @intCast(v.nodes.items.len - 1);
    }

    fn maybeFree(v: *Vfs, id: NodeId) void {
        const n = v.node(id);
        if (n.links != 0 or n.open != 0 or id == root_id) return;
        v.freeNodeMem(n);
        v.nodes.items[id] = null;
        v.free_nodes.append(v.gpa, id) catch {};
    }

    fn childIndex(n: *const Node, name: []const u8) struct { found: bool, index: usize } {
        var lo: usize = 0;
        var hi: usize = n.children.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            switch (std.mem.order(u8, n.children.items[mid].name, name)) {
                .lt => lo = mid + 1,
                .gt => hi = mid,
                .eq => return .{ .found = true, .index = mid },
            }
        }
        return .{ .found = false, .index = lo };
    }

    /// Child lookup including "." and "..".
    fn findChild(v: *Vfs, dir: NodeId, name: []const u8) ?NodeId {
        if (name.len == 0 or std.mem.eql(u8, name, ".")) return dir;
        if (std.mem.eql(u8, name, "..")) return v.node(dir).parent;
        const n = v.node(dir);
        const r = childIndex(n, name);
        return if (r.found) n.children.items[r.index].node else null;
    }

    fn isDot(name: []const u8) bool {
        return name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..");
    }

    fn addChild(v: *Vfs, dir: NodeId, name: []const u8, child: NodeId) Allocator.Error!void {
        const d = v.node(dir);
        const r = childIndex(d, name);
        std.debug.assert(!r.found);
        const owned = try v.gpa.dupe(u8, name);
        errdefer v.gpa.free(owned);
        try d.children.insert(v.gpa, r.index, .{ .name = owned, .node = child });
        d.mtime = v.hooks.now_ns();
        const c = v.node(child);
        c.links += 1;
        if (c.links == 1) {
            c.parent = dir;
            if (!std.mem.eql(u8, c.name, name)) {
                const nn = try v.gpa.dupe(u8, name);
                v.gpa.free(c.name);
                c.name = nn;
            }
        }
    }

    /// Removes the entry; the node is freed once unlinked and closed.
    fn removeChild(v: *Vfs, dir: NodeId, name: []const u8) void {
        const d = v.node(dir);
        const r = childIndex(d, name);
        std.debug.assert(r.found);
        const entry = d.children.orderedRemove(r.index);
        d.mtime = v.hooks.now_ns();
        const c = v.node(entry.node);
        c.links -= 1;
        if (c.links > 0 and c.parent == dir and std.mem.eql(u8, c.name, name)) v.repointPrimary(entry.node);
        v.gpa.free(entry.name);
        v.maybeFree(entry.node);
    }

    /// After the primary link of a hard-linked file goes away, adopt another.
    fn repointPrimary(v: *Vfs, id: NodeId) void {
        const Search = struct {
            fn find(vv: *Vfs, dir: NodeId, target: NodeId) ?struct { NodeId, []const u8 } {
                for (vv.node(dir).children.items) |c| {
                    if (c.node == target) return .{ dir, c.name };
                    if (vv.node(c.node).kind == .dir) if (find(vv, c.node, target)) |hit| return hit;
                }
                return null;
            }
        };
        const hit = Search.find(v, root_id, id) orelse return;
        const n = v.node(id);
        const nn = v.gpa.dupe(u8, hit[1]) catch return;
        v.gpa.free(n.name);
        n.name = nn;
        n.parent = hit[0];
    }

    // ── path resolution ─────────────────────────────────────────────────

    const LookupError = error{ FileNotFound, NotDir };

    fn dirNode(v: *Vfs, h: Handle) LookupError!NodeId {
        if (h == cwd_handle) return root_id;
        const fd = v.getFd(h) orelse return error.FileNotFound;
        if (v.nodes.items[fd.node] == null) return error.FileNotFound;
        if (v.node(fd.node).kind != .dir) return error.NotDir;
        return fd.node;
    }

    fn startOf(v: *Vfs, h: Handle, path: []const u8) LookupError!NodeId {
        if (path.len > 0 and path[0] == '/') return root_id;
        return v.dirNode(h);
    }

    /// Resolves every component of `path` (which must exist).
    fn lookup(v: *Vfs, h: Handle, path: []const u8) LookupError!NodeId {
        var cur = try v.startOf(h, path);
        var it = std.mem.tokenizeScalar(u8, path, '/');
        while (it.next()) |comp| {
            if (v.node(cur).kind != .dir) return error.NotDir;
            cur = v.findChild(cur, comp) orelse return error.FileNotFound;
        }
        // "file/" names a directory.
        if (path.len > 1 and path[path.len - 1] == '/' and v.node(cur).kind != .dir) return error.NotDir;
        return cur;
    }

    const Parent = struct { dir: NodeId, name: []const u8 };

    /// Resolves all but the last component; the parent must be a directory.
    fn lookupParent(v: *Vfs, h: Handle, path: []const u8) LookupError!Parent {
        const trimmed = std.mem.trimEnd(u8, path, "/");
        const start = try v.startOf(h, path);
        if (trimmed.len == 0) return .{ .dir = start, .name = "." };
        const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
        const name = if (slash) |s| trimmed[s + 1 ..] else trimmed;
        const dir = if (slash) |s| try v.lookup(if (s == 0) cwd_handle else h, if (s == 0) "/" else trimmed[0..s]) else start;
        if (v.node(dir).kind != .dir) return error.NotDir;
        return .{ .dir = dir, .name = name };
    }

    fn pathOf(v: *Vfs, id: NodeId, out: *std.ArrayList(u8)) Allocator.Error!void {
        if (id == root_id) return out.appendSlice(v.gpa, "/");
        var stack: [256]NodeId = undefined;
        var depth: usize = 0;
        var cur = id;
        while (cur != root_id and depth < stack.len) : (depth += 1) {
            stack[depth] = cur;
            cur = v.node(cur).parent;
        }
        while (depth > 0) {
            depth -= 1;
            try out.append(v.gpa, '/');
            try out.appendSlice(v.gpa, v.node(stack[depth]).name);
        }
    }

    fn writeRealPath(v: *Vfs, id: NodeId, out_buffer: []u8) error{ NameTooLong, SystemResources }!usize {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(v.gpa);
        v.pathOf(id, &buf) catch return error.SystemResources;
        if (buf.items.len > out_buffer.len) return error.NameTooLong;
        @memcpy(out_buffer[0..buf.items.len], buf.items);
        return buf.items.len;
    }

    // ── descriptors ─────────────────────────────────────────────────────

    fn getFd(v: *Vfs, h: Handle) ?*Fd {
        if (h < fd_base) return null;
        const i: usize = @intCast(h - fd_base);
        if (i >= v.fds.items.len) return null;
        if (v.fds.items[i]) |*fd| return fd;
        return null;
    }

    fn openFd(v: *Vfs, id: NodeId, read: bool, write: bool) error{SystemResources}!Handle {
        const fd: Fd = .{ .node = id, .read = read, .write = write };
        const slot: usize = for (v.fds.items, 0..) |s, i| {
            if (s == null) break i;
        } else blk: {
            v.fds.append(v.gpa, null) catch return error.SystemResources;
            break :blk v.fds.items.len - 1;
        };
        v.fds.items[slot] = fd;
        v.node(id).open += 1;
        return fd_base + @as(i32, @intCast(slot));
    }

    fn closeFd(v: *Vfs, h: Handle) void {
        if (h == cwd_handle) return;
        const fd = v.getFd(h) orelse return;
        const id = fd.node;
        v.fds.items[@intCast(h - fd_base)] = null;
        if (v.nodes.items[id]) |*n| {
            n.open -= 1;
            v.maybeFree(id);
        }
    }

    fn fileNode(v: *Vfs, h: Handle) ?*Node {
        const fd = v.getFd(h) orelse return null;
        if (v.nodes.items[fd.node]) |*n| return n;
        return null;
    }

    // ── dirty tracking ──────────────────────────────────────────────────

    fn markPathOwned(v: *Vfs, path: []u8) void {
        const gop = v.dirty.getOrPut(v.gpa, path) catch {
            v.gpa.free(path);
            return;
        };
        if (gop.found_existing) v.gpa.free(path);
    }

    fn markEntry(v: *Vfs, dir: NodeId, name: []const u8) void {
        if (!v.track) return;
        var buf: std.ArrayList(u8) = .empty;
        v.pathOf(dir, &buf) catch return buf.deinit(v.gpa);
        if (dir != root_id) buf.append(v.gpa, '/') catch return buf.deinit(v.gpa);
        buf.appendSlice(v.gpa, name) catch return buf.deinit(v.gpa);
        v.markPathOwned(buf.toOwnedSlice(v.gpa) catch return buf.deinit(v.gpa));
    }

    /// Marks every live path of `id` (all hard links).
    fn markNode(v: *Vfs, id: NodeId) void {
        if (!v.track) return;
        const n = v.node(id);
        if (n.links == 0 or id == root_id) return;
        if (n.links == 1) return v.markEntry(n.parent, n.name);
        const Walk = struct {
            fn go(vv: *Vfs, dir: NodeId, target: NodeId) void {
                for (vv.node(dir).children.items) |c| {
                    if (c.node == target) vv.markEntry(dir, c.name);
                    if (vv.node(c.node).kind == .dir) go(vv, c.node, target);
                }
            }
        };
        Walk.go(v, root_id, id);
    }

    /// Marks `id` and everything below it (directory moves).
    fn markSubtree(v: *Vfs, id: NodeId) void {
        if (!v.track) return;
        v.markNode(id);
        const n = v.node(id);
        if (n.kind != .dir) return;
        for (n.children.items) |c| v.markSubtree(c.node);
    }

    pub fn dirtyCount(v: *const Vfs) usize {
        return v.dirty.count();
    }

    /// Moves the dirty set into `taken` and returns how many paths it holds.
    pub fn takeDirty(v: *Vfs) usize {
        _ = v.ready();
        v.releaseTaken();
        v.taken.ensureTotalCapacity(v.gpa, v.dirty.count()) catch return 0;
        for (v.dirty.keys()) |k| v.taken.appendAssumeCapacity(k);
        v.dirty.clearRetainingCapacity();
        return v.taken.items.len;
    }

    pub fn takenEntry(v: *Vfs, i: usize) Taken {
        const path = v.taken.items[i];
        const id = v.lookup(cwd_handle, path) catch return .{ .path = path, .kind = .deleted, .data = &.{}, .mtime_ns = 0 };
        const n = v.node(id);
        return .{ .path = path, .kind = if (n.kind == .dir) .dir else .file, .data = n.data.items, .mtime_ns = n.mtime };
    }

    pub fn releaseTaken(v: *Vfs) void {
        for (v.taken.items) |p| v.gpa.free(p);
        v.taken.clearRetainingCapacity();
    }

    /// Restores one persisted entry (parents are created as needed). Takes
    /// ownership of `data` (allocated with `gpa`). Not marked dirty.
    pub fn import(v: *Vfs, path: []const u8, kind: EntryKind, data: []u8, mtime_ns: i96) void {
        var ok = false;
        defer if (!ok) v.gpa.free(data);
        _ = v.ready();
        const saved = v.track;
        v.track = false;
        defer v.track = saved;
        if (kind == .deleted) return;
        var cur: NodeId = root_id;
        var it = std.mem.tokenizeScalar(u8, path, '/');
        while (it.next()) |comp| {
            if (isDot(comp)) return;
            const last = it.peek() == null;
            if (v.findChild(cur, comp)) |c| {
                if (last) {
                    const n = v.node(c);
                    if (n.kind == .dir and kind == .dir) {
                        n.mtime = mtime_ns;
                        return;
                    }
                    if (n.kind != .file or kind != .file) return;
                    n.data.deinit(v.gpa);
                    n.data = .fromOwnedSlice(data);
                    ok = true;
                    n.mtime = mtime_ns;
                    return;
                }
                if (v.node(c).kind != .dir) return;
                cur = c;
                continue;
            }
            const new_kind: Kind = if (last and kind == .file) .file else .dir;
            const id = v.newNode(new_kind, cur, comp) catch return;
            v.addChild(cur, comp, id) catch {
                v.maybeFree(id);
                return;
            };
            if (last) {
                const n = v.node(id);
                n.mtime = mtime_ns;
                if (new_kind == .file) {
                    n.data = .fromOwnedSlice(data);
                    ok = true;
                }
                return;
            }
            cur = id;
        }
    }

    // ── shared operations ──────────────────────────────────────────────

    fn statOf(v: *Vfs, id: NodeId) File.Stat {
        const n = v.node(id);
        return .{
            .inode = @intCast(id + 1),
            .nlink = @intCast(@max(n.links, 1)),
            .size = if (n.kind == .file) n.data.items.len else 0,
            .permissions = if (n.kind == .dir) .default_dir else .default_file,
            .kind = if (n.kind == .dir) .directory else .file,
            .atime = .{ .nanoseconds = n.atime },
            .mtime = .{ .nanoseconds = n.mtime },
            .ctime = .{ .nanoseconds = n.ctime },
            .block_size = 4096,
        };
    }

    fn mkdir(v: *Vfs, h: Handle, path: []const u8) Dir.CreateDirError!NodeId {
        const p = try v.lookupParent(h, path);
        if (isDot(p.name) or v.findChild(p.dir, p.name) != null) return error.PathAlreadyExists;
        const id = v.newNode(.dir, p.dir, p.name) catch return error.SystemResources;
        v.addChild(p.dir, p.name, id) catch {
            v.maybeFree(id);
            return error.SystemResources;
        };
        v.markEntry(p.dir, p.name);
        return id;
    }

    /// mkdir -p; returns the final directory and whether it was created.
    fn mkdirPath(v: *Vfs, h: Handle, path: []const u8) Dir.CreateDirPathError!struct { NodeId, Dir.CreatePathStatus } {
        var cur = try v.startOf(h, path);
        var status: Dir.CreatePathStatus = .existed;
        var it = std.mem.tokenizeScalar(u8, path, '/');
        while (it.next()) |comp| {
            if (v.findChild(cur, comp)) |c| {
                if (v.node(c).kind != .dir) return error.NotDir;
                cur = c;
                status = .existed;
                continue;
            }
            const id = v.newNode(.dir, cur, comp) catch return error.SystemResources;
            v.addChild(cur, comp, id) catch {
                v.maybeFree(id);
                return error.SystemResources;
            };
            v.markEntry(cur, comp);
            cur = id;
            status = .created;
        }
        return .{ cur, status };
    }

    fn touch(v: *Vfs, id: NodeId) void {
        const n = v.node(id);
        n.mtime = v.hooks.now_ns();
        n.ctime = n.mtime;
        v.markNode(id);
    }

    fn writeAt(v: *Vfs, id: NodeId, offset: u64, header: []const u8, data: []const []const u8, splat: usize) error{ SystemResources, FileTooBig }!usize {
        const n = v.node(id);
        var total: usize = header.len;
        if (data.len > 0) {
            for (data[0 .. data.len - 1]) |d| total += d.len;
            total += data[data.len - 1].len * splat;
        }
        const off = std.math.cast(usize, offset) orelse return error.FileTooBig;
        const end = std.math.add(usize, off, total) catch return error.FileTooBig;
        if (end > n.data.items.len) {
            const old = n.data.items.len;
            n.data.resize(v.gpa, end) catch return error.SystemResources;
            if (off > old) @memset(n.data.items[old..off], 0);
        }
        var w = off;
        @memcpy(n.data.items[w..][0..header.len], header);
        w += header.len;
        if (data.len > 0) {
            for (data[0 .. data.len - 1]) |d| {
                @memcpy(n.data.items[w..][0..d.len], d);
                w += d.len;
            }
            const last = data[data.len - 1];
            for (0..splat) |_| {
                @memcpy(n.data.items[w..][0..last.len], last);
                w += last.len;
            }
        }
        if (total > 0) v.touch(id);
        return total;
    }

    fn readAt(v: *Vfs, id: NodeId, offset: u64, data: []const []u8) usize {
        const n = v.node(id);
        const bytes = n.data.items;
        if (offset >= bytes.len) return 0;
        var r: usize = @intCast(offset);
        var total: usize = 0;
        for (data) |d| {
            const k = @min(d.len, bytes.len - r);
            @memcpy(d[0..k], bytes[r..][0..k]);
            r += k;
            total += k;
            if (r == bytes.len) break;
        }
        return total;
    }

    fn openFileImpl(v: *Vfs, h: Handle, path: []const u8, create: ?Dir.CreateFileOptions, mode: Dir.OpenFileOptions.Mode, allow_directory: bool) File.OpenError!File {
        const read = mode != .write_only;
        const write = mode != .read_only;
        if (create) |opts| {
            const p = try v.lookupParent(h, path);
            if (v.findChild(p.dir, p.name)) |existing| {
                if (opts.exclusive) return error.PathAlreadyExists;
                const n = v.node(existing);
                if (n.kind == .dir) return error.IsDir;
                if (opts.truncate and n.data.items.len > 0) {
                    n.data.clearRetainingCapacity();
                    v.touch(existing);
                }
                return .{ .handle = try v.openFd(existing, opts.read, true), .flags = .{ .nonblocking = false } };
            }
            if (isDot(p.name)) return error.IsDir;
            if (path.len > 0 and path[path.len - 1] == '/') return error.IsDir;
            const id = v.newNode(.file, p.dir, p.name) catch return error.SystemResources;
            v.addChild(p.dir, p.name, id) catch {
                v.maybeFree(id);
                return error.SystemResources;
            };
            v.markEntry(p.dir, p.name);
            return .{ .handle = try v.openFd(id, opts.read, true), .flags = .{ .nonblocking = false } };
        }
        const id = try v.lookup(h, path);
        if (v.node(id).kind == .dir and (write or !allow_directory)) return error.IsDir;
        return .{ .handle = try v.openFd(id, read, write), .flags = .{ .nonblocking = false } };
    }

    fn unlink(v: *Vfs, h: Handle, path: []const u8) Dir.DeleteFileError!void {
        const p = try v.lookupParent(h, path);
        if (isDot(p.name)) return error.IsDir;
        const id = v.findChild(p.dir, p.name) orelse return error.FileNotFound;
        if (v.node(id).kind == .dir) return error.IsDir;
        v.markEntry(p.dir, p.name);
        v.removeChild(p.dir, p.name);
    }

    fn rmdir(v: *Vfs, h: Handle, path: []const u8) Dir.DeleteDirError!void {
        const p = try v.lookupParent(h, path);
        if (isDot(p.name)) return error.BadPathName;
        const id = v.findChild(p.dir, p.name) orelse return error.FileNotFound;
        const n = v.node(id);
        if (n.kind != .dir) return error.NotDir;
        if (n.children.items.len != 0) return error.DirNotEmpty;
        v.markEntry(p.dir, p.name);
        v.removeChild(p.dir, p.name);
    }

    fn isAncestor(v: *Vfs, ancestor: NodeId, id: NodeId) bool {
        var cur = id;
        while (true) {
            if (cur == ancestor) return true;
            if (cur == root_id) return false;
            cur = v.node(cur).parent;
        }
    }

    fn renameImpl(v: *Vfs, old_h: Handle, old_path: []const u8, new_h: Handle, new_path: []const u8, preserve: bool) Dir.RenamePreserveError!void {
        const op = try v.lookupParent(old_h, old_path);
        const np = try v.lookupParent(new_h, new_path);
        if (isDot(op.name) or isDot(np.name)) return error.BadPathName;
        const src = v.findChild(op.dir, op.name) orelse return error.FileNotFound;
        const src_dir = v.node(src).kind == .dir;
        if (src_dir and v.isAncestor(src, np.dir)) return error.BadPathName;
        if (v.findChild(np.dir, np.name)) |dst| {
            if (dst == src) return;
            if (preserve) return error.PathAlreadyExists;
            const d = v.node(dst);
            if (d.kind == .dir and !src_dir) return error.IsDir;
            if (d.kind != .dir and src_dir) return error.NotDir;
            if (d.kind == .dir and d.children.items.len != 0) return error.DirNotEmpty;
            v.markEntry(np.dir, np.name);
            v.removeChild(np.dir, np.name);
        }
        v.markSubtree(src);
        // Keep the node alive across the unlink/link pair.
        const n = v.node(src);
        n.open += 1;
        defer {
            v.node(src).open -= 1;
            v.maybeFree(src);
        }
        v.removeChild(op.dir, op.name);
        v.addChild(np.dir, np.name, src) catch return error.SystemResources;
        v.node(src).ctime = v.hooks.now_ns();
        v.markSubtree(src);
    }

    fn linkImpl(v: *Vfs, src: NodeId, new_h: Handle, new_path: []const u8) File.HardLinkError!void {
        if (v.node(src).kind == .dir) return error.PermissionDenied;
        const np = try v.lookupParent(new_h, new_path);
        if (isDot(np.name) or v.findChild(np.dir, np.name) != null) return error.PathAlreadyExists;
        v.addChild(np.dir, np.name, src) catch return error.SystemResources;
        v.markEntry(np.dir, np.name);
    }

    fn writeConsole(v: *Vfs, header: []const u8, data: []const []const u8, splat: usize) usize {
        const out = v.hooks.console;
        var total: usize = 0;
        if (out) |f| f(header);
        total += header.len;
        if (data.len == 0) return total;
        for (data[0 .. data.len - 1]) |d| {
            if (out) |f| f(d);
            total += d.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| if (out) |f| f(last);
        return total + last.len * splat;
    }

    fn applyTimestamps(v: *Vfs, id: NodeId, atime: File.SetTimestamp, mtime: File.SetTimestamp) void {
        const n = v.node(id);
        const t = v.hooks.now_ns();
        switch (atime) {
            .unchanged => {},
            .now => n.atime = t,
            .new => |ts| n.atime = ts.nanoseconds,
        }
        switch (mtime) {
            .unchanged => {},
            .now => n.mtime = t,
            .new => |ts| n.mtime = ts.nanoseconds,
        }
        if (mtime != .unchanged) v.markNode(id);
    }
};

// ── std.Io.VTable glue ─────────────────────────────────────────────────

fn self(userdata: ?*anyopaque) *Vfs {
    const v: *Vfs = @ptrCast(@alignCast(userdata.?));
    return v.ready();
}

fn dirCreateDir(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.Permissions) Dir.CreateDirError!void {
    _ = try self(ud).mkdir(dir.handle, path);
}

fn dirCreateDirPath(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.Permissions) Dir.CreateDirPathError!Dir.CreatePathStatus {
    return (try self(ud).mkdirPath(dir.handle, path))[1];
}

fn dirCreateDirPathOpen(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.Permissions, _: Dir.OpenOptions) Dir.CreateDirPathOpenError!Dir {
    const v = self(ud);
    const id = (v.mkdirPath(dir.handle, path) catch |err| return switch (err) {
        error.Canceled, error.Unexpected => |e| e,
        else => |e| e,
    })[0];
    return .{ .handle = try v.openFd(id, true, false) };
}

fn dirOpenDir(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.OpenOptions) Dir.OpenError!Dir {
    const v = self(ud);
    const id = try v.lookup(dir.handle, path);
    if (v.node(id).kind != .dir) return error.NotDir;
    return .{ .handle = try v.openFd(id, true, false) };
}

fn dirStat(ud: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    const v = self(ud);
    const id = v.dirNode(dir.handle) catch return error.AccessDenied;
    return v.statOf(id);
}

fn dirStatFile(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.StatFileOptions) Dir.StatFileError!File.Stat {
    const v = self(ud);
    return v.statOf(try v.lookup(dir.handle, path));
}

fn dirAccess(ud: ?*anyopaque, dir: Dir, path: []const u8, _: Dir.AccessOptions) Dir.AccessError!void {
    _ = self(ud).lookup(dir.handle, path) catch |err| return switch (err) {
        error.NotDir => error.FileNotFound,
        else => |e| e,
    };
}

fn dirCreateFile(ud: ?*anyopaque, dir: Dir, path: []const u8, options: Dir.CreateFileOptions) File.OpenError!File {
    return self(ud).openFileImpl(dir.handle, path, options, .read_write, false);
}

fn dirOpenFile(ud: ?*anyopaque, dir: Dir, path: []const u8, options: Dir.OpenFileOptions) File.OpenError!File {
    return self(ud).openFileImpl(dir.handle, path, null, options.mode, options.allow_directory);
}

fn dirCreateFileAtomic(ud: ?*anyopaque, dir: Dir, dest_path: []const u8, options: Dir.CreateFileAtomicOptions) Dir.CreateFileAtomicError!File.Atomic {
    const v = self(ud);
    var target = dir;
    var close_dir = false;
    var basename = dest_path;
    if (Dir.path.dirname(dest_path)) |dirname| {
        const id = if (options.make_path)
            (v.mkdirPath(dir.handle, dirname) catch |err| return switch (err) {
                error.PathAlreadyExists, error.LinkQuotaExceeded, error.DiskQuota => error.Unexpected,
                error.IsDir, error.FileTooBig, error.PipeBusy, error.FileLocksUnsupported, error.FileBusy, error.DeviceBusy, error.Streaming => error.Unexpected,
                else => |e| e,
            })[0]
        else id: {
            const id = try v.lookup(dir.handle, dirname);
            if (v.node(id).kind != .dir) return error.NotDir;
            break :id id;
        };
        target = .{ .handle = try v.openFd(id, true, false) };
        close_dir = true;
        basename = Dir.path.basename(dest_path);
    }
    errdefer if (close_dir) v.closeFd(target.handle);
    while (true) {
        var random_integer: u64 = undefined;
        v.hooks.random(std.mem.asBytes(&random_integer));
        const tmp = std.fmt.hex(random_integer);
        const file = v.openFileImpl(target.handle, &tmp, .{ .exclusive = true, .read = true }, .read_write, false) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.IsDir, error.FileTooBig, error.FileLocksUnsupported, error.PipeBusy, error.DeviceBusy, error.FileBusy => return error.Unexpected,
            else => |e| return e,
        };
        return .{
            .file = file,
            .file_basename_hex = random_integer,
            .dest_sub_path = basename,
            .file_open = true,
            .file_exists = true,
            .close_dir_on_deinit = close_dir,
            .dir = target,
        };
    }
}

fn dirClose(ud: ?*anyopaque, dirs: []const Dir) void {
    for (dirs) |d| self(ud).closeFd(d.handle);
}

fn dirRead(ud: ?*anyopaque, r: *Dir.Reader, entries: []Dir.Entry) Dir.Reader.Error!usize {
    const v = self(ud);
    if (entries.len == 0) return 0;
    const id = v.dirNode(r.dir.handle) catch return error.AccessDenied;
    // Cursor = last returned name, kept in `buffer`; `end` = its length + 1
    // (0 = before the first entry). `Reader.init`/`reset`/`Iterator.init` all
    // zero `end`, also for `iterateAssumeFirstIteration` (state `.reading`).
    switch (r.state) {
        .finished => return 0,
        .reset => {
            r.end = 0;
            r.state = .reading;
        },
        .reading => {},
    }
    const n = v.node(id);
    const start: usize = if (r.end == 0) 0 else blk: {
        const ci = Vfs.childIndex(n, r.buffer[0 .. r.end - 1]);
        break :blk if (ci.found) ci.index + 1 else ci.index;
    };
    if (start >= n.children.items.len) {
        r.state = .finished;
        return 0;
    }
    const c = n.children.items[start];
    if (c.name.len > r.buffer.len) return error.SystemResources;
    @memcpy(r.buffer[0..c.name.len], c.name);
    r.end = c.name.len + 1;
    entries[0] = .{
        .name = r.buffer[0..c.name.len],
        .kind = if (v.node(c.node).kind == .dir) .directory else .file,
        .inode = @intCast(c.node + 1),
    };
    return 1;
}

fn dirRealPath(ud: ?*anyopaque, dir: Dir, out: []u8) Dir.RealPathError!usize {
    const v = self(ud);
    return v.writeRealPath(try v.dirNode(dir.handle), out);
}

fn dirRealPathFile(ud: ?*anyopaque, dir: Dir, path: []const u8, out: []u8) Dir.RealPathFileError!usize {
    const v = self(ud);
    return v.writeRealPath(try v.lookup(dir.handle, path), out);
}

fn dirDeleteFile(ud: ?*anyopaque, dir: Dir, path: []const u8) Dir.DeleteFileError!void {
    return self(ud).unlink(dir.handle, path);
}

fn dirDeleteDir(ud: ?*anyopaque, dir: Dir, path: []const u8) Dir.DeleteDirError!void {
    return self(ud).rmdir(dir.handle, path);
}

fn dirRename(ud: ?*anyopaque, old_dir: Dir, old_path: []const u8, new_dir: Dir, new_path: []const u8) Dir.RenameError!void {
    return self(ud).renameImpl(old_dir.handle, old_path, new_dir.handle, new_path, false) catch |err| switch (err) {
        error.PathAlreadyExists, error.OperationUnsupported => unreachable,
        else => |e| e,
    };
}

fn dirRenamePreserve(ud: ?*anyopaque, old_dir: Dir, old_path: []const u8, new_dir: Dir, new_path: []const u8) Dir.RenamePreserveError!void {
    return self(ud).renameImpl(old_dir.handle, old_path, new_dir.handle, new_path, true);
}

fn dirHardLink(ud: ?*anyopaque, old_dir: Dir, old_path: []const u8, new_dir: Dir, new_path: []const u8, _: Dir.HardLinkOptions) Dir.HardLinkError!void {
    const v = self(ud);
    return v.linkImpl(try v.lookup(old_dir.handle, old_path), new_dir.handle, new_path);
}

fn dirSetTimestamps(ud: ?*anyopaque, dir: Dir, path: []const u8, options: Dir.SetTimestampsOptions) Dir.SetTimestampsError!void {
    const v = self(ud);
    const id = v.lookup(dir.handle, path) catch |err| return switch (err) {
        // No FileNotFound in SetTimestampsError; AccessDenied is the closest.
        error.FileNotFound, error.NotDir => error.AccessDenied,
    };
    v.applyTimestamps(id, options.access_timestamp, options.modify_timestamp);
}

fn dirSetPermissions(_: ?*anyopaque, _: Dir, _: Dir.Permissions) Dir.SetPermissionsError!void {}
fn dirSetFilePermissions(_: ?*anyopaque, _: Dir, _: []const u8, _: File.Permissions, _: Dir.SetFilePermissionsOptions) Dir.SetFilePermissionsError!void {}

fn fileStat(ud: ?*anyopaque, file: File) File.StatError!File.Stat {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.AccessDenied;
    if (v.nodes.items[fd.node] == null) return error.AccessDenied;
    return v.statOf(fd.node);
}

fn fileLength(ud: ?*anyopaque, file: File) File.LengthError!u64 {
    return (try fileStat(ud, file)).size;
}

fn fileClose(ud: ?*anyopaque, files: []const File) void {
    for (files) |f| self(ud).closeFd(f.handle);
}

fn fileWritePositional(ud: ?*anyopaque, file: File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) File.WritePositionalError!usize {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.NotOpenForWriting;
    if (!fd.write) return error.NotOpenForWriting;
    return v.writeAt(fd.node, offset, header, data, splat);
}

fn fileReadPositional(ud: ?*anyopaque, file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.NotOpenForReading;
    if (v.node(fd.node).kind == .dir) return error.IsDir;
    if (!fd.read) return error.NotOpenForReading;
    return v.readAt(fd.node, offset, data);
}

fn fileWriteFileUnimplemented(_: ?*anyopaque, _: File, _: []const u8, _: *File.Reader, _: Io.Limit) File.Writer.WriteFileError!usize {
    return error.Unimplemented;
}
fn fileWriteFilePositionalUnimplemented(_: ?*anyopaque, _: File, _: []const u8, _: *File.Reader, _: Io.Limit, _: u64) File.WriteFilePositionalError!usize {
    return error.Unimplemented;
}

fn fileSeekBy(ud: ?*anyopaque, file: File, delta: i64) File.SeekError!void {
    const fd = self(ud).getFd(file.handle) orelse return error.Unseekable;
    const pos = @as(i128, fd.pos) + delta;
    if (pos < 0) return error.Unseekable;
    fd.pos = @intCast(pos);
}

fn fileSeekTo(ud: ?*anyopaque, file: File, offset: u64) File.SeekError!void {
    const fd = self(ud).getFd(file.handle) orelse return error.Unseekable;
    fd.pos = offset;
}

fn fileSync(_: ?*anyopaque, _: File) File.SyncError!void {}

fn fileIsTty(_: ?*anyopaque, _: File) Io.Cancelable!bool {
    return false;
}

fn fileSetLength(ud: ?*anyopaque, file: File, len: u64) File.SetLengthError!void {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.AccessDenied;
    if (!fd.write) return error.AccessDenied;
    const n = v.node(fd.node);
    if (n.kind == .dir) return error.NonResizable;
    const new_len = std.math.cast(usize, len) orelse return error.FileTooBig;
    const old = n.data.items.len;
    if (new_len == old) return;
    n.data.resize(v.gpa, new_len) catch return error.FileTooBig;
    if (new_len > old) @memset(n.data.items[old..], 0);
    v.touch(fd.node);
}

fn fileSetPermissions(_: ?*anyopaque, _: File, _: File.Permissions) File.SetPermissionsError!void {}

fn fileSetTimestamps(ud: ?*anyopaque, file: File, options: File.SetTimestampsOptions) File.SetTimestampsError!void {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.AccessDenied;
    v.applyTimestamps(fd.node, options.access_timestamp, options.modify_timestamp);
}

fn fileLock(_: ?*anyopaque, _: File, _: File.Lock) File.LockError!void {}
fn fileTryLock(_: ?*anyopaque, _: File, _: File.Lock) File.LockError!bool {
    return true;
}
fn fileUnlock(_: ?*anyopaque, _: File) void {}
fn fileDowngradeLock(_: ?*anyopaque, _: File) File.DowngradeLockError!void {}

fn fileRealPath(ud: ?*anyopaque, file: File, out: []u8) File.RealPathError!usize {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.FileNotFound;
    if (v.node(fd.node).links == 0) return error.FileNotFound;
    return v.writeRealPath(fd.node, out);
}

fn fileHardLink(ud: ?*anyopaque, file: File, new_dir: Dir, new_path: []const u8, _: File.HardLinkOptions) File.HardLinkError!void {
    const v = self(ud);
    const fd = v.getFd(file.handle) orelse return error.FileNotFound;
    return v.linkImpl(fd.node, new_dir.handle, new_path);
}

fn operate(ud: ?*anyopaque, operation: Io.Operation) Io.Cancelable!Io.Operation.Result {
    const v = self(ud);
    switch (operation) {
        .file_read_streaming => |o| return .{ .file_read_streaming = r: {
            const fd = v.getFd(o.file.handle) orelse break :r error.NotOpenForReading;
            if (v.node(fd.node).kind == .dir) break :r error.IsDir;
            if (!fd.read) break :r error.NotOpenForReading;
            var want: usize = 0;
            for (o.data) |d| want += d.len;
            const n = v.readAt(fd.node, fd.pos, o.data);
            if (n == 0 and want > 0) break :r error.EndOfStream;
            fd.pos += n;
            break :r n;
        } },
        .file_write_streaming => |o| return .{ .file_write_streaming = w: {
            if (o.file.handle == 1 or o.file.handle == 2) break :w v.writeConsole(o.header, o.data, o.splat);
            const fd = v.getFd(o.file.handle) orelse break :w error.NotOpenForWriting;
            if (!fd.write) break :w error.NotOpenForWriting;
            const n = v.writeAt(fd.node, fd.pos, o.header, o.data, o.splat) catch |err| break :w err;
            fd.pos += n;
            break :w n;
        } },
        else => return Io.failingOperate(ud, operation),
    }
}

/// Overlays the filesystem entries onto `base` (clocks, randomness, …).
pub fn overlay(base: Io.VTable) Io.VTable {
    var t = base;
    t.operate = operate;
    t.dirCreateDir = dirCreateDir;
    t.dirCreateDirPath = dirCreateDirPath;
    t.dirCreateDirPathOpen = dirCreateDirPathOpen;
    t.dirOpenDir = dirOpenDir;
    t.dirStat = dirStat;
    t.dirStatFile = dirStatFile;
    t.dirAccess = dirAccess;
    t.dirCreateFile = dirCreateFile;
    t.dirCreateFileAtomic = dirCreateFileAtomic;
    t.dirOpenFile = dirOpenFile;
    t.dirClose = dirClose;
    t.dirRead = dirRead;
    t.dirRealPath = dirRealPath;
    t.dirRealPathFile = dirRealPathFile;
    t.dirDeleteFile = dirDeleteFile;
    t.dirDeleteDir = dirDeleteDir;
    t.dirRename = dirRename;
    t.dirRenamePreserve = dirRenamePreserve;
    t.dirSetPermissions = dirSetPermissions;
    t.dirSetFilePermissions = dirSetFilePermissions;
    t.dirSetTimestamps = dirSetTimestamps;
    t.dirHardLink = dirHardLink;
    t.fileStat = fileStat;
    t.fileLength = fileLength;
    t.fileClose = fileClose;
    t.fileWritePositional = fileWritePositional;
    t.fileWriteFileStreaming = fileWriteFileUnimplemented;
    t.fileWriteFilePositional = fileWriteFilePositionalUnimplemented;
    t.fileReadPositional = fileReadPositional;
    t.fileSeekBy = fileSeekBy;
    t.fileSeekTo = fileSeekTo;
    t.fileSync = fileSync;
    t.fileIsTty = fileIsTty;
    t.fileSetLength = fileSetLength;
    t.fileSetPermissions = fileSetPermissions;
    t.fileSetTimestamps = fileSetTimestamps;
    t.fileLock = fileLock;
    t.fileTryLock = fileTryLock;
    t.fileUnlock = fileUnlock;
    t.fileDowngradeLock = fileDowngradeLock;
    t.fileRealPath = fileRealPath;
    t.fileHardLink = fileHardLink;
    return t;
}

fn hookNow(ud: ?*anyopaque, clock: Io.Clock) Io.Timestamp {
    _ = clock;
    return .{ .nanoseconds = self(ud).hooks.now_ns() };
}
fn hookRandom(ud: ?*anyopaque, buffer: []u8) void {
    self(ud).hooks.random(buffer);
}

/// Standalone vtable (filesystem + hook clock/random) used by `Vfs.io`.
const vtable: Io.VTable = blk: {
    var t = overlay(Io.failing.vtable.*);
    t.now = hookNow;
    t.random = hookRandom;
    break :blk t;
};

// ── tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

var test_clock: i96 = 1_700_000_000 * std.time.ns_per_s;
fn testNow() i96 {
    test_clock += 1000;
    return test_clock;
}
var test_seed: u64 = 1;
fn testRandom(buf: []u8) void {
    for (buf) |*b| {
        test_seed = test_seed *% 6364136223846793005 +% 1442695040888963407;
        b.* = @truncate(test_seed >> 33);
    }
}
fn testVfs() !Vfs {
    return Vfs.init(testing.allocator, .{ .now_ns = testNow, .random = testRandom });
}

test "web vfs: write/read through std.Io.Dir, absolute and relative" {
    var v = try testVfs();
    defer v.deinit();
    const io = v.io();
    const cwd = Dir.cwd();
    try cwd.createDirPath(io, "/app/data");
    try cwd.writeFile(io, .{ .sub_path = "/app/data/a.txt", .data = "hello" });
    const got = try cwd.readFileAlloc(io, "app/data/a.txt", testing.allocator, .unlimited);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("hello", got);

    var sub = try cwd.openDir(io, "/app", .{ .iterate = true });
    defer sub.close(io);
    try sub.writeFile(io, .{ .sub_path = "data/b.txt", .data = "world!" });
    const st = try cwd.statFile(io, "/app/data/b.txt", .{});
    try testing.expectEqual(@as(u64, 6), st.size);
    try testing.expectEqual(File.Kind.file, st.kind);
    try testing.expect(st.mtime.nanoseconds > 0);

    var buf: [64]u8 = undefined;
    const n = try sub.realPathFile(io, "data/../data/b.txt", &buf);
    try testing.expectEqualStrings("/app/data/b.txt", buf[0..n]);
    try testing.expectError(error.FileNotFound, cwd.statFile(io, "/app/nope", .{}));
    try testing.expectError(error.NotDir, cwd.statFile(io, "/app/data/a.txt/x", .{}));
    try testing.expectError(error.FileNotFound, cwd.access(io, "/missing", .{}));
    try cwd.access(io, "/app/data", .{});
}

test "web vfs: error contracts" {
    var v = try testVfs();
    defer v.deinit();
    const io = v.io();
    const cwd = Dir.cwd();
    try cwd.createDir(io, "d", .default_dir);
    try testing.expectError(error.PathAlreadyExists, cwd.createDir(io, "d", .default_dir));
    try testing.expectError(error.FileNotFound, cwd.createDir(io, "x/y", .default_dir));
    try cwd.writeFile(io, .{ .sub_path = "d/f", .data = "1" });
    try testing.expectError(error.IsDir, cwd.deleteFile(io, "d"));
    try testing.expectError(error.DirNotEmpty, cwd.deleteDir(io, "d"));
    try testing.expectError(error.NotDir, cwd.deleteDir(io, "d/f"));
    try testing.expectError(error.NotDir, cwd.openDir(io, "d/f", .{}));
    try testing.expectError(error.IsDir, cwd.openFile(io, "d", .{ .mode = .read_write }));
    try testing.expectError(error.PathAlreadyExists, cwd.createFile(io, "d/f", .{ .exclusive = true }));
    try testing.expectError(error.FileNotFound, cwd.openFile(io, "d/g", .{}));
    try testing.expectError(error.NotDir, cwd.createDirPath(io, "d/f/g"));
    try testing.expectEqual(Dir.CreatePathStatus.existed, try cwd.createDirPathStatus(io, "d", .default_dir));
    try cwd.deleteFile(io, "d/f");
    try testing.expectError(error.FileNotFound, cwd.deleteFile(io, "d/f"));
    try cwd.deleteDir(io, "d");
    try testing.expectError(error.FileNotFound, cwd.statFile(io, "d", .{}));
}

test "web vfs: atomic replace, rename, hard link, iteration, deleteTree" {
    var v = try testVfs();
    defer v.deinit();
    const io = v.io();
    const cwd = Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = "/doc.json", .data = "old" });
    {
        var buf: [16]u8 = undefined;
        var af = try cwd.createFileAtomic(io, "/lib/x/doc.json", .{ .make_path = true, .replace = true });
        defer af.deinit(io);
        var w = af.file.writer(io, &buf);
        try w.interface.writeAll("new contents");
        try w.interface.flush();
        try af.replace(io);
    }
    const got = try cwd.readFileAlloc(io, "/lib/x/doc.json", testing.allocator, .unlimited);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("new contents", got);

    try cwd.rename("/lib/x", cwd, "/lib/y", io);
    try cwd.access(io, "/lib/y/doc.json", .{});
    try testing.expectError(error.FileNotFound, cwd.access(io, "/lib/x", .{}));
    try testing.expectError(error.PathAlreadyExists, cwd.renamePreserve("/doc.json", cwd, "/lib/y/doc.json", io));
    try cwd.rename("/doc.json", cwd, "/lib/y/doc.json", io);
    try cwd.hardLink("/lib/y/doc.json", cwd, "/lib/link.json", io, .{});
    try cwd.writeFile(io, .{ .sub_path = "/lib/link.json", .data = "shared", .flags = .{ .truncate = true } });
    const shared = try cwd.readFileAlloc(io, "/lib/y/doc.json", testing.allocator, .unlimited);
    defer testing.allocator.free(shared);
    try testing.expectEqualStrings("shared", shared);

    for ([_][]const u8{ "c", "a", "b" }) |name| {
        var p: [32]u8 = undefined;
        try cwd.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&p, "/lib/y/{s}", .{name}), .data = name });
    }
    var dir = try cwd.openDir(io, "/lib/y", .{ .iterate = true });
    var it = dir.iterate();
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(testing.allocator);
    while (try it.next(io)) |e| {
        try names.appendSlice(testing.allocator, e.name);
        try names.append(testing.allocator, ' ');
        // Deleting the current entry must not skip the next one.
        if (e.kind == .file) try dir.deleteFile(io, e.name);
    }
    dir.close(io);
    try testing.expectEqualStrings("a b c doc.json ", names.items);
    try cwd.writeFile(io, .{ .sub_path = "/lib/y/z", .data = "z" });
    try cwd.deleteTree(io, "/lib");
    try testing.expectError(error.FileNotFound, cwd.access(io, "/lib", .{}));
}

test "web vfs: positional and streaming file I/O, seek, setLength" {
    var v = try testVfs();
    defer v.deinit();
    const io = v.io();
    const cwd = Dir.cwd();
    var f = try cwd.createFile(io, "/f.bin", .{ .read = true });
    try f.writeStreamingAll(io, "abcdef");
    try f.writePositionalAll(io, "XY", 2);
    try f.setLength(io, 8);
    var out: [8]u8 = undefined;
    try testing.expectEqual(@as(usize, 8), try f.readPositionalAll(io, &out, 0));
    try testing.expectEqualSlices(u8, "abXYef\x00\x00", &out);
    try testing.expectEqual(@as(u64, 8), try f.length(io));
    f.close(io);

    var rf = try cwd.openFile(io, "/f.bin", .{});
    defer rf.close(io);
    var rbuf: [3]u8 = undefined;
    var r = rf.readerStreaming(io, &rbuf);
    const all = try r.interface.allocRemaining(testing.allocator, .unlimited);
    defer testing.allocator.free(all);
    try testing.expectEqual(@as(usize, 8), all.len);
    try testing.expectError(error.NotOpenForWriting, rf.writeStreamingAll(io, "x"));
}

test "web vfs: dirty set and snapshot import" {
    var v = try testVfs();
    defer v.deinit();
    const io = v.io();
    const cwd = Dir.cwd();
    try cwd.createDirPath(io, "/p/q");
    try cwd.writeFile(io, .{ .sub_path = "/p/q/file", .data = "data" });
    try cwd.writeFile(io, .{ .sub_path = "/p/tmp", .data = "t" });
    try cwd.deleteFile(io, "/p/tmp");
    const n = v.takeDirty();
    try testing.expectEqual(@as(usize, 4), n);
    var saw_file = false;
    var saw_deleted = false;
    for (0..n) |i| {
        const e = v.takenEntry(i);
        if (std.mem.eql(u8, e.path, "/p/q/file")) {
            saw_file = true;
            try testing.expectEqual(EntryKind.file, e.kind);
            try testing.expectEqualStrings("data", e.data);
        }
        if (std.mem.eql(u8, e.path, "/p/tmp")) {
            saw_deleted = true;
            try testing.expectEqual(EntryKind.deleted, e.kind);
        }
    }
    try testing.expect(saw_file and saw_deleted);
    v.releaseTaken();
    try testing.expectEqual(@as(usize, 0), v.dirtyCount());

    // Renaming a directory dirties old and new paths of the whole subtree.
    try cwd.rename("/p", cwd, "/r", io);
    try testing.expectEqual(@as(usize, 6), v.takeDirty());
    v.releaseTaken();

    var w = try testVfs();
    defer w.deinit();
    w.import("/x/y/z.txt", .file, try testing.allocator.dupe(u8, "persisted"), 42);
    w.import("/x/empty", .dir, &.{}, 7);
    try testing.expectEqual(@as(usize, 0), w.dirtyCount());
    const got = try Dir.cwd().readFileAlloc(w.io(), "/x/y/z.txt", testing.allocator, .unlimited);
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("persisted", got);
    const st = try Dir.cwd().statFile(w.io(), "/x/y/z.txt", .{});
    try testing.expectEqual(@as(i96, 42), st.mtime.nanoseconds);
    try testing.expectEqual(File.Kind.directory, (try Dir.cwd().statFile(w.io(), "/x/empty", .{})).kind);
}
