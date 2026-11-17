// UI Automation reads only these owned snapshots, never the mutable Zig tree.
// Input is a parent-before-child projection. Element IDs retain Zig generations.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "accessibility_bridge.h"

namespace zenit_a11y {
// Why the last Snapshot::create on this thread failed (diagnostics only).
// Reset on every create; node is SIZE_MAX when the failure is not per node.
inline thread_local int last_reject_line = 0;
inline thread_local const char *last_reject_reason = "";
inline thread_local size_t last_reject_node = SIZE_MAX;
inline thread_local unsigned last_reject_role = 0;
constexpr uint32_t no_parent = UINT32_MAX;
constexpr size_t max_nodes = 4096, max_string_bytes = 8 * 1024 * 1024;
constexpr uint32_t secure_state = 1u << 17;
constexpr size_t max_geometry_segments = 65536, max_geometry_bytes = 8 * 1024 * 1024;
using Text = ZenitA11yText;
using InputNode = ZenitA11yNode;
#ifdef ZENIT_UIA_CONTRACT_CONTENT
inline thread_local size_t offset_mapping_passes = 0, offset_mapping_bytes = 0;
inline thread_local int offset_mapping_allocation_fail_after = -1;
#endif
struct Viewport { double x = 0, y = 0, width = 0, height = 0, scale = 1; };
struct Node {
    uint32_t id, parent_index, state;
    uint16_t role;
    uint8_t actions, setters;
    bool numeric;
    float x, y, width, height;
    double value_now, value_min, value_max, small_change, large_change;
    const wchar_t *name, *description, *value, *identifier;
    uint32_t *characters; size_t character_count;
    uint32_t *words, *paragraphs, *lines; size_t word_count, paragraph_count, line_count;
    bool editable, can_set_selection, uniform_format, can_scroll;
    uint32_t text_length, selection_start, selection_end, caret, visible_start, visible_end; // UTF-16 units.
    bool geometry_ready;
    ZenitA11yGeometrySegment *geometry; size_t geometry_count;
    bool carets_ready;
    ZenitA11yCaretCandidate *carets; size_t caret_count;
    bool rows_ready;
    ZenitA11yGeometrySegment *rows; size_t row_count;

};
struct Index { uint32_t id, index; };
// The value has already passed copy()'s strict UTF-8 validation. Store UTF-16
// positions at scalar starts once; every offset consumer shares this table.
// Continuation entries stay uninitialized and are rejected before lookup.
class TextOffsets final {
    Text text;
    uint32_t *positions = nullptr;
public:
    explicit TextOffsets(Text source): text(source) {
        if (!text.length || text.length > SIZE_MAX/sizeof(uint32_t)-1) return;
#ifdef ZENIT_UIA_CONTRACT_CONTENT
        if (offset_mapping_allocation_fail_after == 0) return;
        if (offset_mapping_allocation_fail_after > 0) --offset_mapping_allocation_fail_after;
#endif
        positions = (uint32_t *)malloc((text.length+1)*sizeof(uint32_t));
        if (!positions) return;
#ifdef ZENIT_UIA_CONTRACT_CONTENT
        ++offset_mapping_passes;
#endif
        size_t byte = 0; uint32_t wide = 0;
        while (byte < text.length) {
            positions[byte] = wide;
            const unsigned char lead = (unsigned char)text.bytes[byte];
            const size_t size = lead < 0x80 ? 1 : lead < 0xe0 ? 2 : lead < 0xf0 ? 3 : 4;
#ifdef ZENIT_UIA_CONTRACT_CONTENT
            offset_mapping_bytes += size;
#endif
            byte += size; wide += size == 4 ? 2 : 1;
        }
        positions[text.length] = wide;
    }
    ~TextOffsets() { free(positions); }
    TextOffsets(const TextOffsets &) = delete;
    TextOffsets &operator=(const TextOffsets &) = delete;
    bool ready() const { return !text.length || positions; }
    bool get(uint32_t byte, uint32_t &wide) const {
        if (byte > text.length || (byte < text.length && ((unsigned char)text.bytes[byte] & 0xc0) == 0x80)) return false;
        wide = byte ? positions[byte] : 0;
        return true;
    }
};
class Snapshot final {
    volatile LONG refs = 1;
    Node *nodes_ = nullptr;
    Index *index_ = nullptr;
    size_t count_ = 0;
    static bool copy_segments(const TextOffsets &offsets, const ZenitA11yGeometry &source, bool ready, bool allow_empty,
        ZenitA11yGeometrySegment *&output, size_t &output_count, size_t &budget) {
        const size_t count = source.count;
        if (!ready) return count == 0;
        if (!count) return true;
        if (!source.segments || count > max_geometry_segments ||
            count > (max_geometry_bytes-budget)/sizeof(ZenitA11yGeometrySegment)) return false;
        output = (ZenitA11yGeometrySegment *)malloc(count*sizeof(ZenitA11yGeometrySegment));
        if (!output) return false;
        output_count = count; budget += count*sizeof(ZenitA11yGeometrySegment);
        for (size_t i = 0; i < count; ++i) {
            const auto &piece = source.segments[i];
            if ((allow_empty ? piece.start > piece.end : piece.start >= piece.end) ||
                (allow_empty && i && piece.start < source.segments[i-1].end) ||
                !isfinite(piece.x) || !isfinite(piece.y) || !isfinite(piece.width) || !isfinite(piece.height) ||
                piece.width < 0 || piece.height < 0 || (allow_empty && piece.height <= 0)) return false;
            output[i] = piece;
            // Preserve visual/bidi order; no sorting or additional text scan.
            if (!offsets.get(piece.start, output[i].start) || !offsets.get(piece.end, output[i].end)) return false;
        }
        return true;
    }
    static bool copy_carets(const InputNode &in, const TextOffsets &offsets, Node &out, size_t &budget) {
        const size_t count = in.carets.count;
        if (!in.carets_ready) return count == 0;
        out.carets_ready = true;
        if (!count) return true;
        if (!in.carets.candidates || count > max_geometry_segments ||
            count > (max_geometry_bytes-budget)/sizeof(ZenitA11yCaretCandidate)) return false;
        out.carets = (ZenitA11yCaretCandidate *)malloc(count*sizeof(ZenitA11yCaretCandidate));
        if (!out.carets) return false;
        out.caret_count = count; budget += count*sizeof(ZenitA11yCaretCandidate);
        for (size_t i = 0; i < count; ++i) {
            const auto &piece = in.carets.candidates[i];
            if (piece.offset > in.value.length || piece.downstream > 1 || piece.visible > 1 ||
                !isfinite(piece.first_x) || !isfinite(piece.first_y) ||
                !isfinite(piece.last_x) || !isfinite(piece.last_y) ||
                (piece.first_x == piece.last_x && piece.first_y == piece.last_y) ||
                (piece.visible && (!isfinite(piece.visible_first_x) || !isfinite(piece.visible_first_y) ||
                    !isfinite(piece.visible_last_x) || !isfinite(piece.visible_last_y) ||
                    (piece.visible_first_x == piece.visible_last_x && piece.visible_first_y == piece.visible_last_y)))) {
                return false;
            }
            out.carets[i] = piece;
            if (!piece.visible) {
                out.carets[i].visible_first_x = out.carets[i].visible_first_y = 0;
                out.carets[i].visible_last_x = out.carets[i].visible_last_y = 0;
            }
            if (!offsets.get(piece.offset, out.carets[i].offset)) return false;
        }
        return true;
    }
    static int compare(const void *a, const void *b) {
        uint32_t x = ((const Index *)a)->id, y = ((const Index *)b)->id;
        return x < y ? -1 : x > y ? 1 : 0;
    }
    static wchar_t *copy(Text text, size_t &budget) {
        if (text.length > max_string_bytes - budget || (text.length && !text.bytes)) return nullptr;
        int count = text.length ? MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
            text.bytes, (int)text.length, nullptr, 0) : 0;
        if (text.length && !count) return nullptr;
        // Embedded NUL cannot be represented by UIA's string properties.
        for (size_t i = 0; i < text.length; ++i) if (!text.bytes[i]) return nullptr;
        wchar_t *result = (wchar_t *)calloc((size_t)count + 1, sizeof(wchar_t));
        if (!result) return nullptr;
        if (count && MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                text.bytes, (int)text.length, result, count) != count) { free(result); return nullptr; }
        budget += text.length;
        return result;
    }
    ~Snapshot() {
        for (size_t i = 0; i < count_; ++i) {
            // Unlabelled static text shares its owned value as its UIA Name.
            if (nodes_[i].name != nodes_[i].value) free((void *)nodes_[i].name);
            free((void *)nodes_[i].description); free((void *)nodes_[i].value);
            free((void *)nodes_[i].identifier); free(nodes_[i].characters); free(nodes_[i].words); free(nodes_[i].paragraphs); free(nodes_[i].lines);
            free(nodes_[i].geometry); free(nodes_[i].carets); free(nodes_[i].rows);
        }
        free(nodes_); free(index_);
    }
public:
    Snapshot() = default;
    Snapshot(const Snapshot &) = delete;
    Snapshot &operator=(const Snapshot &) = delete;
    Viewport viewport;
    static void *operator new(size_t size) noexcept { return malloc(size); }
    static void operator delete(void *memory) noexcept { free(memory); }
    // Per-node input contract; returns the violated rule, or null.
    static const char *invalid_input(const InputNode &in, size_t i) {
        if (in.id == no_parent) return "id";
        if (in.parent_index != no_parent && in.parent_index >= i) return "parent order";
        if (in.numeric > 1 || in.editable > 1 || in.can_set_selection > 1 || in.uniform_format > 1 || in.can_scroll > 1 ||
            in.geometry_ready > 1 || in.carets_ready > 1 || in.rows_ready > 1) return "flag value";
        if (in.can_set_selection && !in.editable) return "selection without editable";
        if (in.setters & ~15) return "setters";
        if (in.state & ~((1u << 19) - 1)) return "state bits";
        if (in.actions & ~15) return "actions";
        if (!isfinite(in.x) || !isfinite(in.y) || !isfinite(in.width) || !isfinite(in.height)) return "non-finite frame";
        if (in.width < 0 || in.height < 0) return "negative size";
        if (!isnan(in.small_change) && (!isfinite(in.small_change) || in.small_change < 0)) return "small change";
        if (!isnan(in.large_change) && (!isfinite(in.large_change) || in.large_change < 0)) return "large change";
        if (in.numeric && (!isfinite(in.value_now) || !isfinite(in.value_min) || !isfinite(in.value_max) ||
            in.value_min > in.value_max || in.value_now < in.value_min || in.value_now > in.value_max)) return "range value";
        return nullptr;
    }
    static Snapshot *create(const InputNode *input, size_t count) {
        last_reject_line = 0; last_reject_reason = "node text or geometry data"; last_reject_node = SIZE_MAX; last_reject_role = 0;
        if (count > max_nodes || (count && !input)) { last_reject_line = __LINE__; last_reject_reason = "node count"; return nullptr; }
        Snapshot *snapshot = new Snapshot;
        if (!snapshot) { last_reject_line = __LINE__; last_reject_reason = "allocation"; return nullptr; }
        if (count) {
            snapshot->nodes_ = (Node *)calloc(count, sizeof(Node));
            snapshot->index_ = (Index *)calloc(count, sizeof(Index));
            if (!snapshot->nodes_ || !snapshot->index_) { last_reject_line = __LINE__; last_reject_reason = "allocation"; delete snapshot; return nullptr; }
        }
        snapshot->count_ = count;
        size_t budget = 0, boundary_budget = 0, geometry_budget = 0, caret_budget = 0, row_budget = 0;
        for (size_t i = 0; i < count; ++i) {
            const InputNode &in = input[i]; Node &out = snapshot->nodes_[i];
            last_reject_node = i; last_reject_role = in.role;
            if (const char *reason = invalid_input(in, i)) {
                last_reject_line = __LINE__; last_reject_reason = reason;
                delete snapshot; return nullptr;
            }
            out.id = in.id; out.parent_index = in.parent_index; out.state = in.state;
            out.role = in.role; out.actions = in.actions; out.setters = in.setters; out.numeric = in.numeric && !(in.state & secure_state);
            out.x = in.x; out.y = in.y; out.width = in.width; out.height = in.height;
            out.value_now = in.value_now; out.value_min = in.value_min; out.value_max = in.value_max;
            out.small_change = in.small_change; out.large_change = in.large_change;
            if (in.state & secure_state) out.value_now = out.value_min = out.value_max = 0;
            out.value = copy(in.state & secure_state ? Text{nullptr, 0} : in.value, budget);
            // AXStaticText uses Value; UIA Text uses Name and has no ValuePattern.
            // Preserve explicit labels and avoid copying/counting visible text twice.
            out.name = in.role == 52 && !in.name.length ? out.value : copy(in.name, budget);
            out.description = copy(in.description, budget);
            out.identifier = copy(in.identifier, budget);
            if (!out.name || !out.description || !out.value || !out.identifier) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
            // Password snapshots expose neither text length nor caret/selection
            // offsets. Their unredacted value is never read for conversion.
            out.editable = in.editable && !(in.state & secure_state);
            out.can_set_selection = in.can_set_selection && out.editable;
            out.uniform_format = in.uniform_format && out.editable;
            out.can_scroll = in.can_scroll && out.editable;
            if (out.editable) {
                // Scratch is per value and freed before publication, not retained
                // by snapshots/proxies. String validation above bounds it to
                // 4*(max_string_bytes+1) bytes even for hostile input.
                const TextOffsets offsets(in.value);
                if (!offsets.ready()) { last_reject_line = __LINE__; last_reject_reason = "text offset mapping allocation"; delete snapshot; return nullptr; }
                const uint32_t visible_end = in.visible_end == UINT32_MAX ? (uint32_t)in.value.length : in.visible_end;
                if (in.visible_start > visible_end ||
                    !offsets.get((uint32_t)in.value.length, out.text_length) ||
                    !offsets.get(in.selection_start, out.selection_start) ||
                    !offsets.get(in.selection_end, out.selection_end) ||
                    !offsets.get(in.caret, out.caret) ||
                    !offsets.get(in.visible_start, out.visible_start) ||
                    !offsets.get(visible_end, out.visible_end)) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
                const ZenitA11yOffsets inputs[] = {in.characters, in.words, in.paragraphs, in.lines};
                uint32_t **outputs[] = {&out.characters, &out.words, &out.paragraphs, &out.lines};
                size_t *counts[] = {&out.character_count, &out.word_count, &out.paragraph_count, &out.line_count};
                for (size_t unit = 0; unit < 4; ++unit) if (inputs[unit].count) {
                    size_t count = inputs[unit].count;
                    if (!inputs[unit].bytes || count > in.value.length+1 || count > 4*(max_string_bytes+max_nodes)-boundary_budget ||
                        inputs[unit].bytes[0] != 0 || inputs[unit].bytes[count-1] != in.value.length) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
                    *outputs[unit] = (uint32_t *)malloc(count*sizeof(uint32_t));
                    if (!*outputs[unit]) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
                    *counts[unit] = count; boundary_budget += count;
                    for (size_t j = 0; j < count; ++j) {
                        uint32_t target = inputs[unit].bytes[j];
                        if (target > in.value.length || (j && target <= inputs[unit].bytes[j-1])) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
                        if (!offsets.get(target, (*outputs[unit])[j])) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
                    }
                }
                out.geometry_ready = in.geometry_ready; out.rows_ready = in.rows_ready;
                if (!copy_segments(offsets,in.geometry,in.geometry_ready,false,out.geometry,out.geometry_count,geometry_budget) ||
                    !copy_segments(offsets,in.rows,in.rows_ready,true,out.rows,out.row_count,row_budget) ||
                    !copy_carets(in,offsets,out,caret_budget)) { last_reject_line = __LINE__; delete snapshot; return nullptr; }
            }

            snapshot->index_[i] = {in.id, (uint32_t)i};
        }
        if (count) qsort(snapshot->index_, count, sizeof(Index), compare);
        for (size_t i = 1; i < count; ++i)
            if (snapshot->index_[i-1].id == snapshot->index_[i].id) { last_reject_line = __LINE__; last_reject_reason = "duplicate id"; last_reject_node = SIZE_MAX; delete snapshot; return nullptr; }
        return snapshot;
    }
    void retain() { InterlockedIncrement(&refs); }
    void release() { if (!InterlockedDecrement(&refs)) delete this; }
    size_t count() const { return count_; }
    const Node *at(size_t index) const { return index < count_ ? &nodes_[index] : nullptr; }
    const Node *find(uint32_t id) const {
        size_t lo = 0, hi = count_;
        while (lo < hi) {
            size_t mid = lo + (hi - lo) / 2;
            if (index_[mid].id < id) lo = mid + 1; else hi = mid;
        }
        return lo < count_ && index_[lo].id == id ? &nodes_[index_[lo].index] : nullptr;
    }
};

// A retained provider keeps Context alive after the owning window disconnects.
// Publication and disconnection are serialized with reader acquisition; readers
// release independently, so old snapshots remain valid during a frame update.
class Context final {
    volatile LONG refs = 1;
    SRWLOCK lock = SRWLOCK_INIT;
    Snapshot *current = nullptr;
    bool connected = true;
    ~Context() { disconnect(); }
public:
    Context() = default;
    Context(const Context &) = delete;
    Context &operator=(const Context &) = delete;
    static void *operator new(size_t size) noexcept { return malloc(size); }
    static void operator delete(void *memory) noexcept { free(memory); }
    void retain() { InterlockedIncrement(&refs); }
    void release() { if (!InterlockedDecrement(&refs)) delete this; }
    bool publish(const InputNode *input, size_t count, const Viewport &viewport = {}) {
        Snapshot *next = Snapshot::create(input, count);
        if (!next) return false;
        next->viewport = viewport;
        AcquireSRWLockExclusive(&lock);
        bool accepted = connected;
        Snapshot *old = current;
        if (accepted) current = next;
        ReleaseSRWLockExclusive(&lock);
        if (accepted) { if (old) old->release(); } else next->release();
        return accepted;
    }
    Snapshot *acquire() {
        AcquireSRWLockShared(&lock);
        Snapshot *result = connected ? current : nullptr;
        if (result) result->retain();
        ReleaseSRWLockShared(&lock);
        return result;
    }
    void disconnect() {
        AcquireSRWLockExclusive(&lock);
        connected = false; Snapshot *old = current; current = nullptr;
        ReleaseSRWLockExclusive(&lock);
        if (old) old->release();
    }
};
} // namespace zenit_a11y
