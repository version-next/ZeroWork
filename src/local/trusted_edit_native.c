/* Worker-owned private local ZLE channel. No state crosses into the PTY. */
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <dirent.h>
#include <signal.h>
#include <sys/sysctl.h>

typedef struct zw_local_edit {
    int listener, connection, execution_listener, execution_connection;
    char directory[PATH_MAX], socket_path[104], execution_path[104], nonce[33];
} ZW_LOCAL_EDIT;
int zw_local_edit_poll_fd(ZW_LOCAL_EDIT *edit) { return edit->connection >= 0 ? edit->connection : edit->listener; }
static int edit_flags(int fd) {
    int flags = fcntl(fd, F_GETFL);
    return flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) || fcntl(fd, F_SETFD, FD_CLOEXEC);
}
static int edit_file(const char *directory, const char *name, const char *text, size_t length) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/%s", directory, name) >= (int)sizeof(path)) return -1;
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    size_t offset = 0;
    while (offset < length) {
        ssize_t n = write(fd, text + offset, length - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { close(fd); return -1; }
        offset += (size_t)n;
    }
    return close(fd);
}
/* Quote only our generated constants and the original ZDOTDIR, never protocol
 * payloads. Shell text is not used to encode replacement buffers. */
static void edit_quote(FILE *file, const char *text) {
    fputc('\'', file);
    for (; *text; ++text) {
        if (*text == '\'') fputs("'\\''", file); else fputc(*text, file);
    }
    fputc('\'', file);
}
/* ---- Removal when the process is terminated by a signal -----------------
 * A SIGTERM / SIGINT / SIGHUP ends the app without its normal session
 * teardown. Every directory this process created is listed here; the handler
 * removes the files it may contain and the directory itself (unlink / rmdir are
 * async-signal-safe), then lets the signal take its previous course. SIGKILL
 * cannot be caught: the next start reclaims those directories by owner proof
 * (zw_local_edit_sweep). Slot states: 0 free, 1 being written, 2 live. */
#define EDIT_LIVE_SLOTS 64
static char edit_live_paths[EDIT_LIVE_SLOTS][PATH_MAX];
static int edit_live_state[EDIT_LIVE_SLOTS];
static const int edit_exit_signals[] = {SIGTERM, SIGINT, SIGHUP};
#define EDIT_EXIT_SIGNAL_COUNT (sizeof(edit_exit_signals) / sizeof(edit_exit_signals[0]))
static struct sigaction edit_previous_actions[EDIT_EXIT_SIGNAL_COUNT];
static int edit_handler_installed;
static void edit_remove_live(void) {
    static const char *const names[] = {"control", "execution", "execution-secret", ".zshenv", "integration.zsh", "owner"};
    for (size_t slot = 0; slot < EDIT_LIVE_SLOTS; ++slot) {
        if (__atomic_load_n(&edit_live_state[slot], __ATOMIC_ACQUIRE) != 2) continue;
        int dirfd = open(edit_live_paths[slot], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (dirfd < 0) continue;
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) unlinkat(dirfd, names[i], 0);
        close(dirfd);
        rmdir(edit_live_paths[slot]);
    }
}
static void edit_exit_signal(int signal_number) {
    int saved = errno;
    edit_remove_live();
    for (size_t i = 0; i < EDIT_EXIT_SIGNAL_COUNT; ++i) if (edit_exit_signals[i] == signal_number) {
        struct sigaction previous = edit_previous_actions[i];
        sigaction(signal_number, &previous, NULL);
        if (previous.sa_handler == SIG_DFL) { raise(signal_number); break; }
        if (previous.sa_flags & SA_SIGINFO) { if (previous.sa_sigaction) previous.sa_sigaction(signal_number, NULL, NULL); }
        else if (previous.sa_handler != SIG_IGN && previous.sa_handler) previous.sa_handler(signal_number);
        break;
    }
    errno = saved;
}
static void edit_install_exit_handler(void) {
    if (__atomic_exchange_n(&edit_handler_installed, 1, __ATOMIC_ACQ_REL)) return;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = edit_exit_signal;
    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < EDIT_EXIT_SIGNAL_COUNT; ++i) {
        if (sigaction(edit_exit_signals[i], NULL, &edit_previous_actions[i])) continue;
        if (edit_previous_actions[i].sa_handler == SIG_IGN) continue;   // an ignored signal does not end the app
        sigaction(edit_exit_signals[i], &action, NULL);
    }
}
static int edit_track(const char *directory) {
    for (int slot = 0; slot < EDIT_LIVE_SLOTS; ++slot) {
        int expected = 0;
        if (!__atomic_compare_exchange_n(&edit_live_state[slot], &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) continue;
        snprintf(edit_live_paths[slot], sizeof(edit_live_paths[slot]), "%s", directory);
        __atomic_store_n(&edit_live_state[slot], 2, __ATOMIC_RELEASE);
        return slot;
    }
    return -1;   // more live sessions than slots: those rely on the next start's reclamation
}
static void edit_untrack(const char *directory) {
    for (size_t slot = 0; slot < EDIT_LIVE_SLOTS; ++slot)
        if (__atomic_load_n(&edit_live_state[slot], __ATOMIC_ACQUIRE) == 2 && !strcmp(edit_live_paths[slot], directory)) {
            __atomic_store_n(&edit_live_state[slot], 0, __ATOMIC_RELEASE);
            return;
        }
}
void zw_local_edit_destroy(ZW_LOCAL_EDIT *edit) {
    if (!edit) return;
    if (edit->connection >= 0) close(edit->connection);
    if (edit->listener >= 0) close(edit->listener);
    if (edit->execution_connection >= 0) close(edit->execution_connection);
    if (edit->execution_listener >= 0) close(edit->execution_listener);
    if (*edit->execution_path) unlink(edit->execution_path);
    if (*edit->socket_path) unlink(edit->socket_path);
    if (*edit->directory) {
        edit_untrack(edit->directory);
        char path[PATH_MAX];
        const char *files[] = {".zshenv", "integration.zsh", "owner"};
        for (size_t i = 0; i < 3; ++i) {
            snprintf(path, sizeof(path), "%s/%s", edit->directory, files[i]); unlink(path);
        }
        rmdir(edit->directory);
    }
    free(edit);
}

/* ---- Temporary directory placement and orphan reclamation ----------------
 * Formal builds pass root == NULL and keep the historic template
 * /tmp/zw-edit-<uid>-XXXXXX. Isolated builds pass their private temporary root
 * (TMPDIR or the private HOME); when <root>/zw-edit-<uid>-XXXXXX/execution would
 * not fit sun_path (104 bytes), the directory falls back to
 * /tmp/zw-edit-<uid>-t<fnv32(root)>-XXXXXX so test runners can find it by tag. */
/* execution-secret: the per-consumer secret socket (secret_native.c) bound in the same directory. */
static const char *const edit_names[] = {"control", "execution", "execution-secret", ".zshenv", "integration.zsh", "owner"};
#define EDIT_NAME_COUNT (sizeof(edit_names) / sizeof(edit_names[0]))
#define EDIT_OWNER_MAGIC "zerowork-trusted-edit v1\n"
uint32_t zw_local_edit_root_tag(const char *root) {
    uint32_t hash = 2166136261u;
    for (; *root; ++root) { hash ^= (unsigned char)*root; hash *= 16777619u; }
    return hash;
}
/* 0 on success; writes the mkdtemp template. */
int zw_local_edit_template(const char *root, char *out, size_t capacity) {
    unsigned uid = (unsigned)getuid();
    if (!root) return snprintf(out, capacity, "/tmp/zw-edit-%u-XXXXXX", uid) >= (int)capacity ? -1 : 0;
    int n = snprintf(out, capacity, "%s/zw-edit-%u-XXXXXX", root, uid);
    if (n > 0 && n < (int)capacity && (size_t)n + sizeof("/execution") <= 104) return 0;
    return snprintf(out, capacity, "/tmp/zw-edit-%u-t%08x-XXXXXX", uid, zw_local_edit_root_tag(root)) >= (int)capacity ? -1 : 0;
}
static int edit_start_time(pid_t pid, long long *seconds, int *micros) {
    struct kinfo_proc info; size_t size = sizeof(info); int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) || size == 0 || info.kp_proc.p_pid != pid) return -1;
    *seconds = (long long)info.kp_proc.p_starttime.tv_sec; *micros = (int)info.kp_proc.p_starttime.tv_usec;
    return 0;
}
/* 1 only when the recorded owner provably no longer runs: the pid does not
 * exist (ESRCH), or it exists with a different start time (pid reused). */
static int edit_owner_gone(pid_t pid, int have_start, long long seconds, int micros) {
    if (pid <= 0 || pid == getpid()) return 0;
    if (kill(pid, 0) && errno == ESRCH) return 1;
    long long now_seconds; int now_micros;
    if (!have_start || edit_start_time(pid, &now_seconds, &now_micros)) return 0;
    return now_seconds != seconds || now_micros != micros;
}
static int edit_read_small(int dirfd, const char *name, char *buffer, size_t capacity) {
    int fd = openat(dirfd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_size <= 0 || (size_t)st.st_size >= capacity) { close(fd); return -1; }
    ssize_t n = read(fd, buffer, capacity - 1);
    close(fd);
    if (n != st.st_size) return -1;
    buffer[n] = 0; return 0;
}
/* Removal criteria, all required (otherwise the directory is left alone):
 *  - name starts with `prefix` (zw-edit-<our uid>-...), lstat says a real
 *    directory (not a symlink) owned by our uid with mode 0700;
 *  - every entry is one of edit_names, not a directory, owned by our uid;
 *  - ownership proof: `owner` starts with EDIT_OWNER_MAGIC and names pid and
 *    start time, or (directories made before `owner` existed) .zshenv carries
 *    our generated `typeset -g _zw_session=... _zw_parent=<pid>` line;
 *  - that owner process is gone (edit_owner_gone).
 * Returns the number of directories removed. */
int zw_local_edit_sweep_dir(const char *parent, const char *prefix) {
    int parentfd = open(parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (parentfd < 0) return 0;
    DIR *listing = fdopendir(dup(parentfd));
    if (!listing) { close(parentfd); return 0; }
    int removed = 0; size_t prefix_length = strlen(prefix);
    struct dirent *entry;
    while ((entry = readdir(listing))) {
        if (strncmp(entry->d_name, prefix, prefix_length)) continue;
        struct stat st;
        if (fstatat(parentfd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW) || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 07777) != 0700) continue;
        int dirfd = openat(parentfd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (dirfd < 0) continue;
        int ok = 1;
        DIR *inner = fdopendir(dup(dirfd));
        if (!inner) ok = 0;
        for (struct dirent *item; ok && inner && (item = readdir(inner));) {
            if (!strcmp(item->d_name, ".") || !strcmp(item->d_name, "..")) continue;
            size_t i = 0;
            while (i < EDIT_NAME_COUNT && strcmp(item->d_name, edit_names[i])) ++i;
            struct stat child;
            if (i == EDIT_NAME_COUNT || fstatat(dirfd, item->d_name, &child, AT_SYMLINK_NOFOLLOW) || S_ISDIR(child.st_mode) || child.st_uid != getuid()) ok = 0;
        }
        if (inner) closedir(inner);
        pid_t pid = 0; int have_start = 0; long long seconds = 0; int micros = 0;
        char text[8192];
        if (ok && !edit_read_small(dirfd, "owner", text, sizeof(text))) {
            int parsed_pid = 0;
            if (strncmp(text, EDIT_OWNER_MAGIC, sizeof(EDIT_OWNER_MAGIC) - 1) ||
                sscanf(text + sizeof(EDIT_OWNER_MAGIC) - 1, "pid %d\nstart %lld.%d\n", &parsed_pid, &seconds, &micros) != 3) ok = 0;
            pid = parsed_pid; have_start = 1;
        } else if (ok && !edit_read_small(dirfd, ".zshenv", text, sizeof(text))) {
            char *line = strstr(text, "\ntypeset -g _zw_session="), *parent_field = line ? strstr(line, " _zw_parent=") : NULL;
            int parsed_pid = 0;
            if (!parent_field || sscanf(parent_field, " _zw_parent=%d ", &parsed_pid) != 1) ok = 0;
            pid = parsed_pid;
        } else ok = 0;
        if (ok && edit_owner_gone(pid, have_start, seconds, micros)) {
            for (size_t i = 0; i < EDIT_NAME_COUNT; ++i) unlinkat(dirfd, edit_names[i], 0);
            if (!unlinkat(parentfd, entry->d_name, AT_REMOVEDIR)) ++removed;
        }
        close(dirfd);
    }
    closedir(listing); close(parentfd);
    return removed;
}
/* Scans exactly where this build creates directories. */
int zw_local_edit_sweep(const char *root) {
    char prefix[64]; unsigned uid = (unsigned)getuid();
    if (!root) { snprintf(prefix, sizeof(prefix), "zw-edit-%u-", uid); return zw_local_edit_sweep_dir("/tmp", prefix); }
    snprintf(prefix, sizeof(prefix), "zw-edit-%u-", uid);
    int removed = zw_local_edit_sweep_dir(root, prefix);
    snprintf(prefix, sizeof(prefix), "zw-edit-%u-t%08x-", uid, zw_local_edit_root_tag(root));
    return removed + zw_local_edit_sweep_dir("/tmp", prefix);
}
static int edit_swept;
ZW_LOCAL_EDIT *zw_local_edit_create(uint64_t session, uint64_t generation, const char *script, size_t length, const char *root) {
    if (!__atomic_exchange_n(&edit_swept, 1, __ATOMIC_ACQ_REL)) zw_local_edit_sweep(root);
    ZW_LOCAL_EDIT *edit = calloc(1, sizeof(*edit));
    if (!edit) return NULL;
    edit->listener = edit->connection = edit->execution_listener = edit->execution_connection = -1;
    char executable[PATH_MAX], resolved[PATH_MAX]; uint32_t capacity = sizeof(executable);
    if (_NSGetExecutablePath(executable, &capacity) || !realpath(executable, resolved)) goto fail;
    char *slash = strrchr(resolved, '/');
    if (!slash) goto fail;
    *slash = 0;
    char module[PATH_MAX];
    if (snprintf(module, sizeof(module), "%s/zw_ipc.so", resolved) >= (int)sizeof(module) || access(module, R_OK)) goto fail;
    if (zw_local_edit_template(root, edit->directory, sizeof(edit->directory))) { *edit->directory = 0; goto fail; }
    if (!mkdtemp(edit->directory)) { *edit->directory = 0; goto fail; }
    edit_install_exit_handler();
    edit_track(edit->directory);
    if (chmod(edit->directory, 0700)) goto fail;
    {
        long long seconds = 0; int micros = 0; char owner[128];
        if (edit_start_time(getpid(), &seconds, &micros)) goto fail;
        int n = snprintf(owner, sizeof(owner), EDIT_OWNER_MAGIC "pid %d\nstart %lld.%06d\n", getpid(), seconds, micros);
        if (n <= 0 || n >= (int)sizeof(owner) || edit_file(edit->directory, "owner", owner, (size_t)n)) goto fail;
    }
    if (snprintf(edit->socket_path, sizeof(edit->socket_path), "%s/control", edit->directory) >= (int)sizeof(edit->socket_path)) goto fail;
    unsigned char random[16]; arc4random_buf(random, sizeof(random));
    for (size_t i = 0; i < sizeof(random); ++i) snprintf(edit->nonce + 2*i, 3, "%02x", random[i]);
    edit->listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (edit->listener < 0 || edit_flags(edit->listener)) goto fail;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strcpy(address.sun_path, edit->socket_path);
    if (bind(edit->listener, (struct sockaddr *)&address, sizeof(address)) || chmod(edit->socket_path, 0600) || listen(edit->listener, 2)) goto fail;
    if (snprintf(edit->execution_path, sizeof(edit->execution_path), "%s/execution", edit->directory) >= (int)sizeof(edit->execution_path)) goto fail;
    edit->execution_listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (edit->execution_listener < 0 || edit_flags(edit->execution_listener)) goto fail;
    strcpy(address.sun_path, edit->execution_path);
    if (bind(edit->execution_listener, (struct sockaddr *)&address, sizeof(address)) || chmod(edit->execution_path, 0600) || listen(edit->execution_listener, 1)) goto fail;
    if (edit_file(edit->directory, "integration.zsh", script, length)) goto fail;
    char *wrapper = NULL; size_t wrapper_length = 0;
    FILE *file = open_memstream(&wrapper, &wrapper_length);
    if (!file) goto fail;
    const char *original = getenv("ZDOTDIR");
    if (original) { fputs("export ZDOTDIR=", file); edit_quote(file, original); fputc('\n', file); }
    else fputs("unset ZDOTDIR\n", file);
    fputs("[[ ! -r ${ZDOTDIR-$HOME}/.zshenv ]] || source ${ZDOTDIR-$HOME}/.zshenv\n", file);
    fputs("[[ -o interactive && -o rcs ]] || return\n", file);
    fprintf(file, "typeset -g _zw_session=%llu _zw_generation=%llu _zw_parent=%d _zw_nonce='%s' _zw_socket=", (unsigned long long)session, (unsigned long long)generation, getpid(), edit->nonce);
    edit_quote(file, edit->socket_path); fputs(" _zw_exec_socket=", file); edit_quote(file, edit->execution_path); fputs(" _zw_module_dir=", file); edit_quote(file, resolved);
    fputs("\nsource ", file); char script_path[PATH_MAX]; snprintf(script_path, sizeof(script_path), "%s/integration.zsh", edit->directory); edit_quote(file, script_path); fputc('\n', file);
    int failed = fclose(file);
    if (!failed) failed = edit_file(edit->directory, ".zshenv", wrapper, wrapper_length);
    free(wrapper);
    if (failed) goto fail;
    return edit;
fail:
    zw_local_edit_destroy(edit); return NULL;
}
const char *zw_local_edit_directory(ZW_LOCAL_EDIT *edit) { return edit->directory; }
const char *zw_local_edit_nonce(ZW_LOCAL_EDIT *edit) { return edit->nonce; }
/* 0 would-block, 1 bytes, 2 disconnected, 3 newly authenticated connection. */
int zw_local_edit_read(ZW_LOCAL_EDIT *edit, int shell_pid, unsigned char *buffer, size_t length, size_t *count) {
    *count = 0;
    if (edit->connection < 0) {
        int fd = accept(edit->listener, NULL, NULL);
        if (fd < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? 0 : -1;
        uid_t uid; gid_t gid; pid_t peer = -1; socklen_t size = sizeof(peer);
        if (edit_flags(fd) || getpeereid(fd, &uid, &gid) || uid != getuid() ||
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) || peer != shell_pid) { close(fd); return 0; }
        edit->connection = fd;
        return 3;
    }
    ssize_t n = read(edit->connection, buffer, length);
    if (n > 0) { *count = (size_t)n; return 1; }
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return 0;
    close(edit->connection); edit->connection = -1;
    return 2;
}
int zw_local_edit_write(ZW_LOCAL_EDIT *edit, const unsigned char *buffer, size_t length, size_t *count) {
    *count = 0;
    if (edit->connection < 0) return -1;
    ssize_t n = send(edit->connection, buffer, length, MSG_NOSIGNAL);
    if (n >= 0) { *count = (size_t)n; return 1; }
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? 0 : -1;
}

/* Independent execution channel: it stays authenticated while edit reconnects. */
int zw_local_execution_poll_fd(ZW_LOCAL_EDIT *edit) { return edit->execution_connection >= 0 ? edit->execution_connection : edit->execution_listener; }
int zw_local_execution_read(ZW_LOCAL_EDIT *edit, int shell_pid, unsigned char *buffer, size_t length, size_t *count) {
    *count = 0;
    if (edit->execution_connection < 0) {
        int fd = accept(edit->execution_listener, NULL, NULL);
        if (fd < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? 0 : -1;
        uid_t uid; gid_t gid; pid_t peer = -1; socklen_t size = sizeof(peer);
        if (edit_flags(fd) || getpeereid(fd, &uid, &gid) || uid != getuid() ||
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) || peer != shell_pid) { close(fd); return 0; }
        edit->execution_connection = fd; return 3;
    }
    ssize_t n = read(edit->execution_connection, buffer, length);
    if (n > 0) { *count = (size_t)n; return 1; }
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return 0;
    close(edit->execution_connection); edit->execution_connection = -1; return 2;
}
int zw_local_execution_write(ZW_LOCAL_EDIT *edit, const unsigned char *buffer, size_t length, size_t *count) {
    *count = 0;
    if (edit->execution_connection < 0) return -1;
    ssize_t n = send(edit->execution_connection, buffer, length, MSG_NOSIGNAL);
    if (n >= 0) { *count = (size_t)n; return 1; }
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? 0 : -1;
}

void zw_local_execution_close(ZW_LOCAL_EDIT *edit) {
    if (edit->execution_connection >= 0) close(edit->execution_connection);
    edit->execution_connection = -1;
}
