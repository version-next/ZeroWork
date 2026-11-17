# Yix 技术验证（P0 · V 项）

基线：集成分支 `feat/ui-arch-revamp` @ `7034789d`；Zig 0.17.0；vendored zenit（`vendor/zenit`，未修改）。
代码：`tools/mockups/yix_spike.zig` + `tools/mockups/yix_spike/`；真实窗口取证脚本 `e2e/yix_spike_native.ts`。
范围：V-1、V-2、V-3、V-4、V-5、V-11（V1 包）；V-9、V-10（T0 包，结论汇总于此）。V-6/7/8/12 不在本轮。
**P3 补充**：V-6、V-7 与 V-11 的原生实证见「P3 实证（F-set-preview）」一节（设置预览 runner 的完整窗口与多窗口夹具）。

## 总表

| 编号 | 假设 | 结论 | 证据类型 | 对方案的影响 |
|---|---|---|---|---|
| V-1 | 模块根源文件在子目录时不能 `@import("../…")` 越出模块根目录 | **成立**。同一模块内跨子目录 `../` 可以；命名模块绕不开，因为一个文件只能属于一个模块。`.yix`/`.yss` 的 import 只改写成孪生文件名，路径仍按 Zig 相对路径解析，规则相同 | 最小构建实验（4 个用例）+ spike 子目录组件 + 孪生文件内容 | §5.4 的多路复用根（`src/preview.zig`、`src/tests_*.zig`）**必须保留**；删掉“若 V-1 证明可以向上 import…”这条退路 |
| V-2 | 组件参数可为 `*ViewModel`，`helper(vm)` 选择器跟随其内部读取的信号 | **成立**。只在被读的信号变化时重跑，同内容 `set` 和无关信号都不触发；可用于插值、`visible`、`switch`、组件属性 | spike 运行 + 无窗口自检 + Harness | §4.4/§4.5 的选择器写法可照用；补一条“选择器在挂载时可能被求值不止一次（实测 2 次），必须纯且便宜” |
| V-3 | `onClick={send(vm, .back)}` 可编译，点击时求值，处理器里读信号是 `peek` 语义 | **成立**，有一处限制：实参里**不能写结构体字面量**（`.{ .x = 1 }`、`T{ .x = 1 }`），yix gen 会拒绝。替代写法：`@unionInit` 或 Intent 构造函数 | spike 运行 + 无窗口自检 + Harness 真实指针点击 + 孪生文件 | §4.4“动作上行”补限制；§4.5 `rows.yix` 的 `set(vm, field, v)` 这种“一行转发函数”是正确写法 |
| V-4 | 模板里直接写 `vm.title`（`*ui.Signal`）会被当作响应式源，可省掉选择器 | **不成立**。插值 `{vm.title}` 能编译，但渲染出 Signal 结构体的调试转储（**静默错误**）；`visible`、`if`、`switch`、`for`、组件属性则直接编译失败。替代写法：内联 `.get()`（如 `{vm.title.get()}`），或选择器函数 | spike 运行 + 无窗口自检 + 编译错误原文 + 孪生文件 | §4.4 明确禁止 `{vm.field}`，写 `vm.field.get()` 或选择器；§3.2 增加一行限制；建议 `check-arch` 或上游加一条拦截 |
| V-5 | 旧命令式视图经 `ComponentOf` 嵌入后，主题切换、卸载清理、test_id 查询都正常 | **成立，前提是旧面板的 `Binding.scope` 用组件传入的子 scope**。三种主题机制（`boxStyled` 重放、`on_theme` 钩子、`themeSignal` effect）都跟随；分支卸载时 `onCleanup` 执行、after-layout 钩子被移除，21 轮挂载/卸载后 DebugAllocator 无泄漏；内部 test_id 在树遍历和 Harness query 里都能查到。**反例**：沿用外部长寿命 scope 时卸载不清理 | 无窗口自检（含 DebugAllocator）+ Harness；旧面板为手写仿制品 | P3 的 3d 过渡步骤可行；适配层必须把组件 scope 交给 `Binding`；真实 `Binding.init` 不是 `pub`，嵌入粒度要按 `mountPage` 定，或补公开构造函数；`Mounted` 句柄要另外拿出来 |
| V-11 | `windowRegion` 能替代 aux 窗口现在的 `titlebar_height` 拖动带 | **有条件成立**。Yix 可以直接写 `windowRegion={.drag}`，命中语义正确（交互子元素、显式 `.client` 不拖窗口）。但它**只在 `WindowConfig.chrome = .custom` 下才被原生层读取**；aux 窗口和 mockup runner 用的是旧的 `titlebar = .custom_inset` + `titlebar_height`，在这条路径上 `windowRegion` 完全不起作用（显式 `.client` 的非交互区域照样拖窗口）。两者不会叠加，而是二选一 | 无窗口自检（`windowRegionAt` 对照 `legacyWindowControlAt`）；原生路径**仅源码结论**，待 P3 在设置预览 runner 上实证 | 设置/向导改用 `windowRegion` 时，`aux_window.Spec` 与 `main.zig:92` 必须从 `.titlebar = .custom_inset` 改为 `.chrome = .{ .custom = … }`；红绿灯布局与 `setTrafficLightsLayout` 的配合待 P3 实证 |
| V-9 | `std.zig.Tokenizer` 能稳定地从 `.yix` 中提取 `@import` | **成立**。扫描 `vendor/zenit` 下全部 40 个 `.yix`，提取 101 处，与 grep 结果逐条一致 | `check-arch` 工具单测（3 个 zenit 样本，含对抗性模板文本）+ `list-imports` 全量比对 | §4.3 第 2 条的“推测”改为已验证；`check-arch` 直接扫 `.yix` 源文件，不需要改扫生成物 |
| V-10 | `zig build test --summary all` 的输出足以得到各步骤的用例总数 | **不成立，有替代写法**。`test` / `test-ui` 用 `Run.create` 运行测试二进制，构建器不走测试协议，`--summary all` 不显示用例数；改读测试二进制自己输出的 `N passed; M skipped; K failed.` 与逐用例行，后备为 `count-tests` 静态上界 | 两个步骤的全量运行输出 + `count-tests` | §6.2 P0 第 4 条与 P1 退出标准的计数口径改为“测试二进制统计行 + count-tests”，见 `baselines/tests.md` |

取证汇总：无窗口自检 `SELFCHECK 61/61`；Harness 真实窗口 8/8 PASS；`check-yix` 退出码 0；`zig build mockup -Dmockup=yix_spike` 与 `zig build -j2` 通过（命令与输出见“复现方法”和各节）。

---

## V-1 模块根与 `../` import

### 结论
- **成立**：模块根源文件 `features/settings/preview.zig` 里写 `@import("../../shared/util.zig")`，Zig 0.17 报 `error: import of file outside module path`。
- 模块根在上层目录（`root.zig`）时，同一模块内的 `features/settings/preview_lib.zig` 用 `../../shared/util.zig` **可以**。
- 用 `addImport` 把上层文件做成命名模块能编译（用例 c），但前提是该文件**不能再被根模块按相对路径 import**：一个文件只能属于一个模块（用例 d：`error: file exists in modules 'root' and 'shared'`）。ZeroWork 的 view 文件之间全靠相对路径互相 import，所以无法靠命名模块把 `features/<f>/preview.zig` 做成独立根。
- `.yix` / `.yss`：编译器只把 `@import("x.yss")` / `@import("../y.yix")` 改写成同目录孪生名（`../_y.yix.zig`，`vendor/zenit/src/yix/compiler.zig:440-471` 的 `markZig` / `twinPath`），路径仍是普通的 Zig 相对路径，受同样的模块根约束。spike 里 `parts/count_row.yix` 用 `../styles.yss`、`../vm.zig` 引回上层，生成的孪生文件是：
  ```zig
  // tools/mockups/yix_spike/parts/_count_row.yix.zig
  const S = @import("../_styles.yss.zig");
  const m = @import("../vm.zig");
  ```
  它能工作，是因为 mockup 视图模块的根是 `tools/mockups/yix_spike.zig`，模块根目录是 `tools/mockups/`。

### 最小实验（仓库外 `/private/tmp/zw-v1-import-exp/`，未入库，内容原样）

`build.zig`
```zig
const std = @import("std");

// V-1 最小实验：
//  a) 根源文件在子目录（features/settings/preview.zig），@import("../../shared/util.zig") 越出模块根目录
//  b) 根源文件在上层（root.zig），同一模块内 features/settings/preview_lib.zig 再 @import("../../shared/util.zig")
//  c) 根源文件在子目录，通过 addImport 把上层文件做成命名模块 "shared"
//  d) 同一个文件既被根模块按相对路径 import，又作为命名模块的根（一个文件属于两个模块）
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const which = b.option([]const u8, "case", "a|b|c|d") orelse "a";
    const eq = struct {
        fn f(x: []const u8, y: []const u8) bool {
            return std.mem.eql(u8, x, y);
        }
    }.f;
    const root_path = if (eq(which, "a"))
        "features/settings/preview.zig"
    else if (eq(which, "b"))
        "root.zig"
    else if (eq(which, "c"))
        "features/settings/preview_named.zig"
    else
        "root_dup.zig";
    const mod = b.createModule(.{ .root_source_file = b.path(root_path), .target = target });
    if (eq(which, "c") or eq(which, "d")) {
        const shared = b.createModule(.{ .root_source_file = b.path("shared/util.zig"), .target = target });
        mod.addImport("shared", shared);
    }
    const exe = b.addExecutable(.{ .name = b.fmt("case-{s}", .{which}), .root_module = mod });
    const run = b.addRunArtifact(exe);
    b.step("run", "run").dependOn(&run.step);
}
```
`shared/util.zig`
```zig
pub const answer: u32 = 42;
```
`features/settings/preview.zig`
```zig
const std = @import("std");
const util = @import("../../shared/util.zig");
pub fn main() void {
    std.debug.print("case A answer={d}\n", .{util.answer});
}
```
`features/settings/preview_lib.zig`
```zig
const util = @import("../../shared/util.zig");
pub fn answer() u32 {
    return util.answer;
}
```
`root.zig`
```zig
const std = @import("std");
const preview = @import("features/settings/preview_lib.zig");
pub fn main() void {
    std.debug.print("case B answer={d}\n", .{preview.answer()});
}
```
`features/settings/preview_named.zig`
```zig
const std = @import("std");
const util = @import("shared");
pub fn main() void {
    std.debug.print("case C answer={d}\n", .{util.answer});
}
```
`root_dup.zig`
```zig
const std = @import("std");
const by_path = @import("shared/util.zig");
const by_name = @import("shared");
pub fn main() void {
    std.debug.print("case D answer={d} {d}\n", .{ by_path.answer, by_name.answer });
}
```

### 证据（`cd /private/tmp/zw-v1-import-exp && zw-nonet.sh zig build run -Dcase=<x>`）
```
== case a
features/settings/preview.zig:2:22: error: import of file outside module path
const util = @import("../../shared/util.zig");
                     ^~~~~~~~~~~~~~~~~~~~~~~
== case b
case B answer=42
== case c
case C answer=42
== case d
shared/util.zig:1:1: error: file exists in modules 'root' and 'shared'
shared/util.zig:1:1: note: files must belong to only one module
root_dup.zig:2:25: note: file is imported here by the root of module 'root'
shared/util.zig:1:1: note: file is the root of module 'shared'
```
spike 自检：`PASS V-1 parts/count_row.yix (imports ../vm.zig, ../styles.yss) renders count=1`、`PASS V-1 subdirectory component follows vm.count -> 7`。

### 坑与限制
- mockup 通道的视图模块根是 `tools/mockups/<name>.zig`，所以 mockup 不能 import `src/**`（`design_tokens` 是 build.zig 以命名模块方式提供的特例）。这也是 V-5 只能用手写仿制面板的原因。
- `parts` 是 Yix 保留字：`const parts = @import("parts/count_row.yix");` 报 `` `parts` is a Yix builtin (signal / computed / ref / parts); give this declaration another name ``（`compiler.zig:1105`）。子目录名可以叫 `parts/`，但 import 出来的常量不能叫 `parts`。

### 建议修订的方案条目
- **§5.4“预览 runner”**：删掉“若 V-1 证明子目录里的根文件可以向上 import，则 runner 直接放 `features/<f>/preview.zig`，不需要多路复用”。改为：V-1 已证实不可行（越出模块根报错，命名模块也绕不开“一文件一模块”），预览与测试统一用 `src/` 下的多路复用根；`features/<f>/preview.zig` 只导出预览入口，不做模块根。
- **§5.1 目录树**：`src/preview.zig`、`src/acceptance.zig`、`src/tests_*.zig` 这几个根保留在 `src/` 顶层，并注明原因是 V-1。
- **§5.3 命名规范**：补一条“Yix 文件里不要用 `parts`、`signal`、`computed`、`ref` 做 import 常量名”。

---

## V-2 `*ViewModel` 参数 + 选择器函数

### 结论
**成立。** 组件参数 `vm: *m.ViewModel` 被编译成 `ui.Source(*m.ViewModel)` 字段；模板里的 `titleOf(vm)` 被包进 `scope.derive`，选择器内部对 `vm.title.get()` 的实际读取建立依赖。只在被读的信号变化时重跑；同内容 `set` 不重跑（`Signal.set` 按内容判等）；无关信号不重跑。在插值、宿主属性 `visible`、`{switch}`、组件属性 `W.Button disabled=` 上都已验证；把 `vm` 再传给子目录里的组件（`<Rows.CountRow vm={vm} />`）同样有效。

### 最小示例
```zig
// view.yix
const m = @import("vm.zig");
fn titleOf(vm: *m.ViewModel) []const u8 { return vm.title.get(); }
fn cannotBack(vm: *m.ViewModel) bool { return !vm.can_back.get(); }
fn modeOf(vm: *m.ViewModel) m.Mode { return vm.mode.get(); }

pub fn SelectorPanel(vm: *m.ViewModel) View {
    return (
        <col>
            <text testId="spike.v2.title">{titleOf(vm)}</text>
            <box visible={cannotBack(vm)}><text>已在最前</text></box>
            {switch (modeOf(vm)) {
                .overview => <text>overview</text>,
                .panes => <text>panes</text>,
                .search => <text>search</text>,
            }}
        </col>
    );
}
```
```zig
// vm.zig（节选）
pub const ViewModel = struct {
    title: *ui.Signal([]const u8),
    mode: *ui.Signal(Mode),
    can_back: *ui.Signal(bool),
    doubled: *ui.Memo(i32),
    // …
};
// 挂载：ui.view.render(scope, cx, views.SelectorPanel(.{ .vm = vm }))
```

### 证据
孪生文件（`tools/mockups/yix_spike/_views.yix.zig`）：
```zig
pub const SelectorPanelProps = struct {
    vm: ui.Source(*m.ViewModel),
    …
};
…
const __yix_T = @TypeOf(titleOf(__yix_view_ctx.vm.peek()));
break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
    return titleOf(__yix_ctx.vm.get());
} }.__yix_compute);
```
自检输出：
```
PASS V-2 titleOf(vm) initial = 概览 (selector runs at mount = 2)
PASS V-2 vm.title.set -> text=子页面, selector re-ran 1x
PASS V-2 same content set() does not re-run selector (runs=1)
PASS V-2 unrelated signal (count) does not re-run titleOf (runs=1)
PASS V-2 visible={cannotBack(vm)} follows can_back (true -> false)
PASS V-2 switch (modeOf(vm)) re-branches overview -> panes
PASS V-2 no leak
```
Harness（真实窗口）：`PASS V-3 pointer click on onClick={send(vm, .forward)} -> v2.title=子页面, v2.mode=panes`。

### 坑与限制
- **挂载时选择器跑了 2 次**（`derive` 先探测一次依赖再建 memo，`vendor/zenit/src/ui/reactive/scope.zig:470-483`）。选择器必须是纯函数，不能有副作用、不能做重活。
- `{switch}` **不支持多值分支** `.panes, .search => …`，yix gen 报 `unexpected token`；要拆成多个分支，或用 `else =>`（已验证可用）。§4.5 的示例 `.panes, .search => <Panes.Panes vm={vm} />` 照抄会编译失败。
- `//` 注释写在标签内部会变成文本节点（`literal_text = "// …"`），注释只能写在模板外。

### 建议修订的方案条目
- **§4.4“数据下行”**：保留“选择器函数”为主写法，补充：①选择器在挂载时可能被求值多次，必须纯且便宜；②`vm` 参数本身是静态源，信号依赖只来自选择器内部的 `.get()`；③同内容 `set` 不触发更新，列表必须整体换切片（与现有表述一致）。
- **§4.5 `settings_window.yix` 草图**：把 `.panes, .search => <Panes.Panes vm={vm} />` 改成两个分支（或 `else =>`）。
- **§3.2**：增加“`switch` 不支持多值分支”“标签内不能写 `//` 注释”两行。

---

## V-3 `onClick={send(vm, .back)}`

### 结论
**成立（有一处限制）。**
- 编译：带参数的函数调用、枚举字面量实参、`@unionInit(m.Intent, "set_count", 5)` 实参都能编译；宿主 `<box onClick>` 与组件 `W.Button onClick` 都能用。
- 求值时机：处理器被编译成闭包 `struct { fn __yix_run(__yix_ctx) void { …; send(__yix_ctx.vm.peek(), .back); } }`，挂载时不求值（`send_calls=0`），每次点击都重新求值。
- `peek` 语义：`vm` 参数在处理器里是 `.peek()`；处理器执行时信号图上没有正在追踪的观察者（`tracking_stack` 深度为 0），所以 `dispatch` 里写的 `.get()` 也不会建立订阅；之后改这些信号不会重跑处理器。处理器外包了 `beginBatch/endBatch`，一次点击里的多次 `set` 合并传播。
- **限制**：实参里写结构体字面量（`send(vm, .{ .set_count = 5 })` 或 `send(vm, m.Intent{ .set_count = 5 })`）会被 yix gen 拒绝：
  ```
  tools/mockups/yix_spike/views.yix:44:99: error: field writes and nested event statements are not implemented
  ```
  原因是事件语句里一旦引用了响应式参数，编译器就把含 `=` 的语句当作字段写入拒绝（`compiler.zig:2618` 的 `containsAssignment` 检查）。替代写法：`@unionInit(m.Intent, "set_count", 5)`、Intent 上的构造函数（`m.Intent.edit(key, value)`），或 `.yix` 顶层的一行转发函数（`fn setCount(vm: *m.ViewModel, n: i32) void { vm.dispatch(.{ .set_count = n }); }`）。

### 最小示例
```zig
fn send(vm: *m.ViewModel, intent: m.Intent) void { vm.dispatch(intent); }

<W.Button testId="spike.v3.back" label="后退" disabled={cannotBack(vm)} onClick={send(vm, .back)} />
<W.Button testId="spike.v3.add" label="+5" onClick={send(vm, @unionInit(m.Intent, "set_count", 5))} />
<box testId="spike.v3.host" onClick={send(vm, .toggle_flag)}><text>宿主 box</text></box>
```

### 证据
孪生文件（原文）：
```zig
struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .back);  }
struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .forward);  }
struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), @unionInit(m.Intent, "set_count", 5));  }
struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .toggle_flag);  }
```
自检输出：
```
PASS V-3 mount does not evaluate handlers (send_calls=0)
PASS V-3 back disabled={cannotBack(vm)} initially disabled=true
PASS V-3 click forward -> send(vm, .forward) once, last=forward
PASS V-3 inside handler tracking_stack depth=0 (0 = .get() acts as peek, no subscription)
PASS V-3 state written by handler propagates (back disabled -> false)
PASS V-3 signals read in handler do not re-run it (send_calls still 1)
PASS V-3 @unionInit(m.Intent, "set_count", 5) payload -> count=47
PASS V-3 host <box onClick={send(vm, .toggle_flag)}> works, last=toggle_flag
PASS V-3 disabled W.Button swallows the click (send_calls stays 3)
PASS V-3 each click re-evaluates the call (send_calls=5, expected 5)
PASS V-3 no leak
```
Harness（真实窗口，`clickAt` 走命中测试与事件分发）：
```
PASS V-3 pointer click on onClick={send(vm, .forward)} -> v2.title=子页面, v2.mode=panes
PASS V-3 pointer click on onClick={send(vm, @unionInit(m.Intent, "set_count", 5))} -> v1.count=6, v4.inline_get=106
PASS V-3 back -> v2.title=概览
```

### 坑与限制
- 禁用的 `W.Button` 会吞掉点击（处理器不执行），符合预期，但 view-model 里不必再重复判断“禁用时忽略”。
- 事件里不能写字段赋值 `vm.x = 1`（§3.2 已列）；同一机制还会拒绝结构体字面量实参，见上。

### 建议修订的方案条目
- **§4.4“动作上行”**：补一句“事件实参里不能写结构体字面量；带载荷的 Intent 用构造函数（`Intent.edit(key, value)` 之类）或 `.yix` 顶层的一行转发函数；处理器里读信号是 peek 语义，可直接调用 `dispatch`”。
- **§4.5 view-model 草图**：给 `Intent` 加几个构造函数（`pub fn edit(key: Key, value: values.Value) Intent`、`pub fn open(loc: Location) Intent`），模板里写 `send(vm, m.Intent.open(loc))`。
- **§3.2**：在“事件里不能写字段”那一行补“也不能写结构体字面量实参”。

---

## V-4 模板里直接写 `vm.<信号字段>`

### 结论
**不成立。** 原因：组件参数 `vm` 是 `ui.Source(*ViewModel)`，任何引用它的表达式都会被包进 `scope.derive`，结果类型是 `Source(*ui.Signal(T))`。运行时只解开一层源，得到的是 `*ui.Signal(T)` 指针本身，而不是 `T`。`yixValue`（`vendor/zenit/src/ui/view.zig:2045-2057`）按类型判定的是**表达式的类型**，而表达式的类型已经是外层的 `Source`。
- **插值 `{vm.field}`**：能编译，但 `yixFormat`（`view.zig:2101-2110`）对 `*Signal` 选了 `{any}`，渲染出整个 Signal / Memo 结构体的调试转储，**不报错、不更新**。对 `[]const u8`、`i32`、`*ui.Memo(i32)`、枚举、`bool` 都是这样（见截图与自检）。这是最危险的情况：编译通过，界面上出现一长串 `.{ .base = .{ .vtable = …`。
- **`visible={vm.flag}`、`{if (vm.flag)}`**：编译失败 `ui.view .visible: expected a source of bool, got reactive.source.Source(*reactive.signal.Signal(bool))`。
- **`{switch (vm.mode)}`**：编译失败 `Yix {switch}: the value must be an enum or a tagged union, got *reactive.signal.Signal(yix_spike.vm.Mode)`。
- **`{if (vm.note) |n|}`（可选值）**：编译失败 `Yix {if (x) |v| …}: x must be an optional or an error union, got *reactive.signal.Signal(?[]const u8)`。
- **`{for (vm.rows) |r|}`**：编译失败 `no field named 'len' in struct 'reactive.signal.Signal([]const yix_spike.vm.Row)'`。
- **组件属性 `<W.Button disabled={vm.can_back} />`**：编译失败 `expected type 'bool', found '*reactive.signal.Signal(bool)'`。
- 试过的另一种绕法 `fn sig(s: anytype) @TypeOf(s) { return s; }` + `{sig(vm.title)}`：同样被包进 `derive`（孪生文件里是 `return sig(__yix_ctx.vm.get().title);`），`visible` / `if` / `switch` / `for` / 组件属性仍然编译失败。已删除，不保留。

**可用的替代写法**（都已验证会跟随更新）：
1. 内联 `.get()`：`{vm.title.get()}`、`{vm.count.get() + 100}`、`visible={vm.can_back.get()}`、`disabled={vm.can_back.get()}`、`{if (vm.can_back.get())}`、`{switch (vm.mode.get())}`（含 `else =>`）、`{if (vm.note.get()) |n|}`、`{for (vm.rows.get()) |r|}`。它是函数调用，走和选择器相同的 derive + 实际读取跟踪。
2. 选择器函数（V-2）。

所以“省掉选择器函数”可以做到，但写法是 `vm.field.get()`，不是 `vm.field`。

### 最小示例
```zig
pub fn Direct(vm: *m.ViewModel) View {
    return (
        <col>
            <text>{vm.title.get()}</text>
            <box visible={vm.can_back.get()} />
            <W.Button label="后退" disabled={!vm.can_back.get()} onClick={send(vm, .back)} />
            {switch (vm.mode.get()) { .overview => <text>overview</text>, else => <text>其他</text> }}
            {if (vm.note.get()) |n| <text>{n}</text> else <text>none</text>}
            {for (vm.rows.get()) |r| <text key={r.id}>{r.title}</text> else <text>empty</text>}
        </col>
    );
}
```
```zig
// 不要这样写：能编译，但渲染出 Signal 结构体转储
<text>{vm.title}</text>
```

### 证据
编译错误原文（把上面的 `.get()` 去掉后 `zig build mockup -Dmockup=yix_spike`）：
```
tools/mockups/yix_spike/_views.yix.zig:209:38: error: expected type 'bool', found '*reactive.signal.Signal(bool)'
tools/mockups/yix_spike/_views.yix.zig:336:63: error: no field named 'len' in struct 'reactive.signal.Signal([]const yix_spike.vm.Row)'
vendor/zenit/src/ui/view.zig:3444:17: error: Yix {if (x) |v| …}: x must be an optional or an error union, got *reactive.signal.Signal(?[]const u8)
vendor/zenit/src/ui/view.zig:3467:17: error: Yix {switch}: the value must be an enum or a tagged union, got *reactive.signal.Signal(yix_spike.vm.Mode)
vendor/zenit/src/ui/view.zig:6735:21: error: ui.view .visible: expected a source of bool, got reactive.source.Source(*reactive.signal.Signal(bool))
vendor/zenit/src/ui/view.zig:6735:21: error: ui.view.lazyIf condition: expected a source of bool, got reactive.source.Source(*reactive.signal.Signal(bool))
```
孪生文件（`{vm.title}`）：
```zig
const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().title);
break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
    return __yix_ctx.vm.get().title;
} }.__yix_compute);
```
自检输出（`{vm.field}` 反例保留在 `DirectPanel` 里，断言它**不是值**）：
```
PASS V-4 NOT-A-VALUE spike.v4.title renders a struct dump: .{ .base = .{ .vtable = .{ .cleanup = fn (*react…
PASS V-4 NOT-A-VALUE spike.v4.count renders a struct dump: count=.{ .base = .{ .vtable = .{ .cleanup = fn (…
PASS V-4 NOT-A-VALUE spike.v4.doubled renders a struct dump: doubled=.{ .owner = .{ .test_write_trace = void,…
PASS V-4 NOT-A-VALUE spike.v4.mode renders a struct dump: mode=.{ .base = .{ .vtable = .{ .cleanup = fn (*…
PASS V-4 NOT-A-VALUE spike.v4.flag renders a struct dump: can_back=.{ .base = .{ .vtable = .{ .cleanup = f…
PASS V-4 NOT-A-VALUE spike.v4.title after set still a dump (no unwrap): .{ .base = .{ .vtable = .{ .cleanup = fn (*react…
PASS V-4 NOT-A-VALUE spike.v4.count after set still a dump (no unwrap): count=.{ .base = .{ .vtable = .{ .cleanup = fn (…
PASS V-4 NOT-A-VALUE spike.v4.doubled after set still a dump (no unwrap): doubled=.{ .owner = .{ .test_write_trace = void,…
PASS V-4 NOT-A-VALUE spike.v4.mode after set still a dump (no unwrap): mode=.{ .base = .{ .vtable = .{ .cleanup = fn (*…
PASS V-4 NOT-A-VALUE spike.v4.flag after set still a dump (no unwrap): can_back=.{ .base = .{ .vtable = .{ .cleanup = f…
PASS V-4 {vm.count.get() + 100} inline .get() tracks -> 105
PASS V-4 visible={vm.can_back.get()} follows -> shown=true
PASS V-4 W.Button disabled={vm.can_back.get()} follows -> true
PASS V-4 {if (vm.can_back.get())} re-branches -> yes
PASS V-4 {switch (vm.mode.get())} re-branches -> search
PASS V-4 {if (vm.note.get()) |n|} capture none -> 有备注
PASS V-4 {for (vm.rows.get()) |r|} rows 2 -> 3 -> empty
PASS V-4 no leak
```
Harness：`PASS V-1/V-2/V-4 initial text: v2.title=概览 v4.inline_get=101 v1.count=1`；点击后 `v4.inline_get=106`。

### 坑与限制
- `{vm.field}` 是**静默错误**，审查时容易漏看；P3 起需要机器拦截（见缺口 G1 与下方建议）。
- `vm.field.get()` 和选择器一样建 memo（`derive`），开销相同；它只是少写一个函数，不是更轻。
- 对比：如果直接把信号作为**组件参数**传入（`<Label count={sig} />`，参数类型 `count: i32`），Yix 会按响应式源处理，这是 zenit 的常规用法；问题只出在“经由 `vm` 参数取字段”这条路径。

### 建议修订的方案条目
- **§4.4“数据下行”**：明确两种合法写法：选择器函数，或内联 `vm.field.get()`；**禁止**在模板里写裸的 `vm.field`。
- **§4.3 静态检查**：`check-arch` 增加一条规则：`.yix` 模板表达式里出现 `<参数名>.<字段>` 而后面没有 `.get()` / `.peek()` / 函数调用时报错（或在 V-9 的 tokenizer 里实现），直到上游 G1 修复。
- **§3.1 表“读取外部信号”一行**：证据补上“组件参数形式已验证（spike V-2）”，并注明“经参数取信号字段必须 `.get()`”。
- **§3.2**：增加一行“`{vm.field}` 不会解开信号字段：插值静默输出结构体转储，其余位置编译失败”。

---

## V-5 旧命令式视图经 `ComponentOf` 嵌入

### 结论
**成立，前提是旧面板的 cleanup / effect 挂在组件传入的子 scope 上。**
- 嵌入机制：`ui.view.ComponentOf(f)` 要求 `fn (Props, *Scope, *Cx) !*Node`（`view.zig:2172-2187`），与旧面板的 `fn mountContent(cx, bound)` 参数顺序不同，需要一层 3 行的适配函数。`Component.mount` 为每次挂载新建子 scope 并绑定到返回的根节点（`view.zig:2207-2240`），节点释放时子 scope 一起销毁。
- 主题：三种旧写法都跟随 `Cx.setTheme`。①`ui.boxStyled` / `ui.textStyled` 挂的 `on_theme` 重放；②手写的 `node.meta.per_frame.hooks.on_theme`（同 `app_theme.bindInk`）；③`scope.createEffect` 读 `cx.themeSignal()`（同 `app_theme.bindMaterial` / `paintSignal`）。dark → light → dark 三次切换，颜色都等于对应主题的 token，钩子和 effect 每次各执行 1 次。
- 卸载：条件分支 `{if (legacyShown(vm)) <legacy.LegacyPanel … />}` 关掉后，`scope.onCleanup` 执行，cleanup 里的 `removeAfterLayoutHook` 生效（after-layout 钩子数回到 0），之后再切主题，旧面板的 effect 和钩子不再执行。再做 20 轮挂载/卸载：`mounts=21 cleanups=21 live=0`，钩子数回到基线，DebugAllocator 报告无泄漏。
- test_id：旧面板内部用 `node.meta.ownership.meta.test_id` 设的 5 个 id，树遍历全部找到；真实窗口里 Harness `query` 也全部找到，卸载后查不到，重挂后又能查到。旧面板里的 `W.Button`（`cx.on` 处理器）能被真实指针点击。
- **反例**：如果旧面板沿用外部长寿命的 `Binding.scope`（适配函数不把组件 scope 交给它），分支卸载时 cleanup **不会执行**，`Live` 状态和 after-layout 钩子一直挂着，直到外部 scope 销毁才释放；期间若切主题，effect 会写已释放的节点（自检里刻意在切主题前先销毁外部 scope，避免 UAF）。

### 最小示例
```zig
// 旧面板：签名同 settings_parts/*.zig 的 mountContent(cx, bound)
pub fn mountContent(cx: *ui.Cx, bound: *Binding) !*ui.Node { … }

// 适配：Binding.scope 必须是组件给的子 scope
const LegacyProps = struct { label: []const u8 = "legacy" };
fn mountLegacy(props: LegacyProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const bound = try scope.createState(Binding, .{ .scope = scope, .label = props.label });
    return mountContent(cx, bound);
}
pub fn LegacyPanel(props: LegacyProps) ui.view.ComponentOf(mountLegacy) {
    return ui.view.component(mountLegacy, props);
}
```
```zig
// .yix 里当标签用
const legacy = @import("legacy.zig");
{if (legacyShown(vm)) <legacy.LegacyPanel label="旧面板（子 scope）" />}
```

### 证据
自检输出：
```
PASS V-5 embedded legacy panel mounted once; 5/5 legacy test_ids found by tree walk
PASS V-5 setTheme(dark): boxStyled/textStyled replay, on_theme hook (+1), themeSignal effect (+1) all follow
PASS V-5 setTheme(light): boxStyled/textStyled replay, on_theme hook (+1), themeSignal effect (+1) all follow
PASS V-5 setTheme(dark): boxStyled/textStyled replay, on_theme hook (+1), themeSignal effect (+1) all follow
PASS V-5 legacy W.Button cx.on handler fires (clicks=1)
PASS V-5 legacy addAfterLayoutHook registered (hooks 0 -> 1)
PASS V-5 branch unmount -> scope.onCleanup ran (cleanups=1, live=0), node gone
PASS V-5 after-layout hook removed by cleanup (hooks=0)
PASS V-5 after unmount theme effect / hook no longer run (effects +0, hooks +0)
PASS V-5 20 more mount/unmount cycles: mounts=21 cleanups=21 live=0
PASS V-5 remount: test_ids queryable again
PASS V-5 COUNTER-EXAMPLE outer Binding.scope: branch unmount does NOT run cleanup (cleanups +0, live=2) -> must pass the component scope
PASS V-5 counter-example released only when the outer scope is disposed (live=1)
PASS V-5 no leak (DebugAllocator) after all cycles
```
Harness（真实窗口）：
```
PASS V-5 harness query finds 5 test_ids inside the embedded imperative panel
PASS V-5 branch unmount -> legacy test_ids gone from harness query
PASS V-5 remount -> legacy test_ids queryable again
PASS V-5 pointer click on legacy W.Button (cx.on handler) dispatched without error
```

### 与真实旧面板的差距（spike 用的是手写仿制品 `tools/mockups/yix_spike/legacy.zig`）
1. **Binding 的构造**：真实的 `settings_content_view.Binding.init` 是私有的（`src/config/settings_content_view.zig:486`），只能经 `mountPage(cx, scope, controller, hooks)` 或 `mountContent` 间接创建；它们正好用传入的 `scope` 建 `Binding`（`:189`、`:194`），所以按 `mountPage` 粒度嵌入时 scope 自然正确。单独嵌入某个面板（如 `settings_notify.mountContent(cx, bound)`）需要 `Binding.init` 改为 `pub`，或新增一个公开构造函数。
2. **Mounted 句柄**：真实 host 依赖 `mountPage` 返回的 `Mounted`（`isComposing`、`captureFocus`、`consumeEscape`、`refreshFooter`，`settings_content_view.zig:100-175`）。`ComponentOf` 只返回节点，适配函数要通过 props 里的输出指针（例如 `out: *?Mounted`）把它交还给 host，并在 scope cleanup 里清空。
3. **主题色来源**：真实面板读 `app_theme.current()` 这个全局（`src/ui/app_theme.zig:588`），spike 读 `ThemeTokens`。重放路径相同（都是 `on_theme` 钩子 / `themeSignal` effect），但真实面板要求 `app_theme.select()` 先更新全局再 `cx.setTheme`（`app_theme.zig:386-411` 正是这样做的）；嵌入不改变这一点。
4. **重放范围**：`setTheme` 只遍历 `cx.root`、popover portal 和 overlay 层（`vendor/zenit/src/ui/core.zig:2324-2362`，`core/builders.zig:104-110` 的注释）。嵌在 Yix 树里的旧面板在 `cx.root` 之下，没问题；旧面板里手工 `appendChild` 到别处的浮层（如 `ui/ai_sessions_view.zig:61` 的做法）不在本次验证范围。
5. **规模**：真实面板还有 Tooltip / Popover / IME 客户端注册（`Binding.popovers`、`ime_clients`、`escape_clients`），它们也挂在 `bound.scope` 上，按上面的规则同样会随组件 scope 释放，但没有实测。

### 建议修订的方案条目
- **§3.4 第 2 条 / §4.5 第 4 点 / P3 的 3d 过渡步骤**：补“旧视图包成组件时，适配函数必须把 `ComponentOf` 传入的子 scope 交给旧代码（`Binding.scope`），否则卸载不清理；示例见 YIX_SPIKE.md §V-5”。
- **P3 任务包**：把“`Binding.init` 公开或新增构造函数”“`Mounted` 句柄经 props 输出指针交还 host”列为 3d 的前置小改；嵌入粒度优先用 `mountPage`。
- **§6.2 P0 第 7 条**：注明 mockup 通道无法 import `src/**`（V-1），V-5 用的是仿制面板；用真实旧面板复验放到 P3 的设置预览 runner 上。

---

## V-11 `windowRegion` 与 `titlebar_height` 拖动带

### 结论
**有条件成立：只有改用新的窗口 chrome API 后，`windowRegion` 才能替代拖动带；两者是二选一，不会叠加。**

1. **Yix 写法**：`windowRegion` 是 box 类宿主元素的属性（`vendor/zenit/src/yix/compiler.zig:312`），可直接写 `windowRegion={.drag}` / `{.client}` / `{.close}` 等，编译后设置 `node.behavior.interaction.window_region`（自检第一条）。也可以用现成组件 `W.WindowHeader` / `W.DragRegion` / `W.ClientRegion` / `W.WindowControls`（`vendor/zenit/src/ui/components/mod.zig:16-19`，用法见 `examples/window_chrome/main.zig:55-58`）。
2. **命中语义**（`Cx.windowRegionAt`，`core.zig:2876-2890`）：取最上层命中节点，沿父链向上，遇到第一个非 `.inherit` 的 `window_region` 就返回它；途中遇到可交互节点（pointer/scroll 命中角色或文本输入）就返回 `.client`。所以拖动区里的按钮、输入框自动被排除，显式 `.client` 的非交互块也被排除，`.close` 等标题栏按钮语义按声明返回；被裁剪、隐藏、透明的节点不参与；树正在变动时一律返回 `.client`。
3. **原生层只在新 API 下读 `windowRegion`**：
   - `zenit_app/runtime.zig:970-975`：只有 `config.window.chrome != null` 且有效模式不是 `.native` 时才装 `chromeHit`（调用 `windowRegionAt`）；否则在 `titlebar = .custom_inset` 下装 `titlebarHitTestCb`（调用 `legacyWindowControlAt`）。
   - `runtime.zig:812-818`：只有 `chrome == null` 且 `titlebar == .custom_inset` 时才设置 `setTitlebarDragHeight(titlebar_height)` 与 `setTitlebarDragRightInset`。
   - `native/macos/window_bridge.m:3283-3307`（`zenitArmTitlebarMouseDown`）：有 `chromeHitCallback` 时，整个内容区里返回值等于 `2`（`.drag`）的点拖窗口，原生红绿灯按钮除外；没有时，只在高度 `titlebarDragHeight` 的带内、左侧 78px 与右侧 inset 之外拖窗口，带内命中可交互节点（`legacyWindowControlAt` 返回 true）时交给应用。
   - 所以在旧路径上，`windowRegion` **被完全忽略**：显式 `.client` 的非交互块照样拖窗口，`.drag` 写在带外也没用。
4. **mockup runner 的影响**：`tools/mockups/runner.zig` 固定 `titlebar = .custom_inset, titlebar_height = 40, titlebar_drag_right_inset = 220`，`chrome == null`，走的是旧路径。spike 窗口顶部 40pt 的 `ChromeHeader` 只是正好落在旧拖动带里，能拖是旧拖动带的效果，不是 `windowRegion` 的效果；右侧 220pt 内（spike 的 `.close` 块就在这里）不拖。因此 **mockup 通道无法实证 `windowRegion` 的原生行为**。仓库现有的 `tabs.behavior.interaction.window_region = .client`（`src/main.zig:13910`）在主窗口的旧路径下同样不生效，真正起作用的是同一行附近设置的 `hit_roles.pointer = true`。
5. **macOS 上非 `.drag` 区域**：原生 mouseDown 路径只判断是否为 `.drag`；`.close` / `.minimize` / `.maximize` / `.resize_*` 在 macOS 上没有看到被原生层消费的代码（Win32 走 `native/windows/window_bridge.c` 的非客户区命中）。**仅源码结论**。

### 最小示例
```zig
// .yix：设置窗口标题区（需要窗口用 chrome = .custom）
<row testId="settings.titlebar" windowRegion={.drag} style={S.titlebar}>
    <text style={S.title}>偏好设置</text>
    <W.Button testId="settings.history.back" … />   // 交互节点自动是 .client
    <box windowRegion={.client} style={S.search_slot}>…</box>
</row>
```
```zig
// host：创建 aux 窗口时改用新 API（替代 .titlebar = .custom_inset + titlebar_height）
.window = .{ …, .titlebar_height = 44, .chrome = .{ .custom = .{} } },
```

### 证据
自检（无窗口 Cx，`windowChrome()` 设为 `.custom`，对同一棵 Yix 树分别问新旧两条路径）：
```
PASS V-11 Yix windowRegion={.drag} sets node.behavior.interaction.window_region = drag
PASS V-11 blank @(40,20): windowRegionAt=drag (want drag); legacyWindowControlAt=false (want false)
PASS V-11 button @(259,20): windowRegionAt=client (want client); legacyWindowControlAt=true (want true)
PASS V-11 client @(318,20): windowRegionAt=client (want client); legacyWindowControlAt=false (want false)
PASS V-11 plain @(379,20): windowRegionAt=drag (want drag); legacyWindowControlAt=false (want false)
PASS V-11 close @(918,20): windowRegionAt=close (want close); legacyWindowControlAt=false (want false)
PASS V-11 below @(400,150): windowRegionAt=client (want client); legacyWindowControlAt=false (want false)
PASS V-11 no leak
```
`client` 那一行是关键：新路径返回 `.client`（不拖），旧路径返回 `false`（拖）。zenit 自己的覆盖：`vendor/zenit/src/ui/core/window_chrome_tests.zig:37-72`（交互子元素、显式 `.client`、隐藏、平移、透明）与 `:99-134`（裁剪、顶层 overlay）。

### 待 P3 实证（仅源码结论）
- 改用 `.chrome = .{ .custom = … }` 后，aux 窗口的红绿灯布局：`main.zig:101` 的 `setTrafficLightsLayout` 与 `chrome_backend.configure(…, titlebar_height)`（`zenit_app/chrome_backend.zig:103-113`）的配合，以及标题区高度、全屏时的行为。
- 原生拖动、双击缩放在 `chromeHit` 路径上的实际表现；`.close` 等区域在 macOS 上是否需要应用自己处理点击。
- 这些需要可配置 chrome 的预览 runner（mockup runner 不许改），建议放到 P3 的设置预览 runner 上验证。

### 建议修订的方案条目
- **§3.1 表“窗口区域”一行**：补“仅在 `WindowConfig.chrome = .custom/.frameless` 下生效；旧的 `titlebar = .custom_inset` 路径忽略它”。
- **§3.3 表“原生 aux 窗口”一行 / P3**：增加一步“`aux_window.Spec` 增加 `chrome` 字段（或直接改为 `.chrome = .{ .custom = .{} }`），`main.zig:92` 的窗口配置随之改；标题栏改用 `windowRegion={.drag}` 后删掉 `titlebar_height` 拖动带依赖”，并把红绿灯布局列为实证项。
- **§9.2 V-11**：验证方式改为“P3 设置预览 runner（chrome = .custom）上实证原生拖动；spike 已给出 headless 语义”。

---

## P3 实证（F-set-preview：设置预览 runner 的完整窗口与多窗口夹具）

基线：`revamp/set-preview` 自集成分支 `fce71182` 切出；Zig 0.17.0；`vendor/zenit` 未修改。主程序运行时行为未改（本包只改 `src/features/settings/preview/**`、两个 e2e 脚本与文档；`build.zig` 不需要改）。

### 夹具

- `src/features/settings/preview/settings_preview_runner.zig`：`--layout=window`（默认）挂**完整设置窗口**——生产的 `Controller` + `ViewModel` + `.yix` 外壳 `SettingsWindow`（或 `.legacy` 外壳，随 `settings_view_mode.zig`），经 `aux_window.Slot` → `MultiWindowApp.createWindowWith` 打开，窗口参数与 `ProcessWindows.drainAux` 相同（960×780、最小 760×480、`titlebar_height` 46、红绿灯 `(28, 32, 12)`、`maximizable`、`restorable = false`、owner + `center_on_owner`）。参数：`--page=<0-8|slug> [--sub=n] [--search=text] [--theme=…] [--chrome=inset|custom] [--multi] [--main-theme=…] [--plugin-fixture] [--self-check=v7|v11]`；`--layout=content`（636×628 内容区，协议插件页）保留；`--preview-kind` 随 `PreviewKind` 删除（plugin-truth）。
- `preview_host.zig`：最小宿主。**不经 `SettingsHost`**——它依赖 `process_state`、`AppNavHost`、`ProcessWindows` 与 `application_options`，要把整个主程序模块图（SSH、VT、通知、更新…）拉进预览步骤；这里按原样复刻了 `mountWindow` / `mountYixWindow`、`WindowHook.run`（跟随进程主题、无焦点时把焦点给卡片、输入法组合中推迟重建、`.yix` 两阶段重挂）、`rebuildYixContent` / `settleYixContent`、旧路径的 `rebuildNav` / `rebuildContent`（焦点快照与恢复）与 `detachWindow`（`vm.detach()`）。`Ports` 是不做 I/O 的假实现：选择器、快捷键录制、AI 提供方 / 扩展、外观 worker、保存流水线、通知授权、滚动位置记忆不复刻，对应 Effect 只记日志，保存不落盘。**代价**：V-6 的观察针对复刻后的宿主逻辑，`SettingsHost` 以后若改这几段，runner 需要同步。
- `self_checks.zig`：进程内自检，逐行 `PASS|FAIL|INFO <V-id> …`，有 FAIL 时退出码 1；用 `DebugAllocator` + 计数分配器。Harness 没有 `windowRegionAt` 的 RPC，所以 V-11 的命中判定直接调 `Cx.windowRegionAt`（原生 mouseDown 调的同一个函数）。
- `--plugin-fixture`：发布两条只有元数据的插件清单（无 factory / 服务），协议插件页不再显示“没有已注册的插件”。生产注册表由 `application_host.registry()` 从 `src/plugins` 组装，runner 不能跨 feature 引用，所以用夹具。
- `e2e/settings_preview_windows_native.ts`：`plugins`、`selfcheck`、`geometry`（V-11）、`v6` 四部分；`e2e/settings_previews.ts` 的 5 个规划视图 case 在 content / window 两种布局下各跑一遍（10/10 通过）。

### P3 总表

| 编号 | 结论 | 证据类型 |
|---|---|---|
| V-7 | **成立**。两个窗口各有自己的 `Cx` / `SignalOwner`；投影信号归设置窗口所有；设置信号变化不触发主窗口 effect，反之亦然；主窗口 effect **即使读了**设置窗口的信号也不会被订阅（跨 `SignalOwner` 读取不建立依赖——是隔离也是陷阱，见下）；关窗时窗口 scope 的 cleanup 全部执行、`ViewModel.detach` 执行、存活内存从 ~6.4 MB 回落到关闭前水平，4 轮开关关闭态存活字节完全相同，`DebugAllocator` 无泄漏；重开得到新信号，位置与未保存草稿来自 `Controller`，搜索词 / 搜索框 / 历史复位。`.yix` 与 `.legacy` 两种实现结果相同。**主题不是窗口级状态**：`app_theme` 选择是进程全局，设置窗口每帧跟随，两个窗口不能各用一个主题 | runner 自检（24 PASS） |
| V-11 | **成立，并发现生产拖动带失效**。① 几何与像素：`.custom_inset` 与 `chrome = .custom` 下 15 个节点矩形逐一相同，整窗截图（1920×1560）**逐像素相同**，最小尺寸都夹在 760×480，生效模式都是 `.custom`，原生标题栏高度都是 32。② 命中：`windowRegion={.drag}` 标在导航窗口顶与页头后，空白区 / 标题文字为 `.drag`，搜索框、导航行、后退 / 前进 / 帮助、内容视口为 `.client`，拖动区内没有任何控件命中点。③ **生产 `.custom_inset` 拖动带在设置窗口里一个可拖点都没有**：宿主让整窗卡片 `settings.panel` `focusable`（接 Escape / ⌘W），`legacyWindowControlAt` 在卡片内恒为真；取消 focusable 后立刻恢复 4693 个可拖点。④ 红绿灯、双击缩放两条路径等价（源码）。真实拖动、双击、红绿灯悬停 / 点击、全屏布局**未实证** | runner 自检（custom 15 PASS / inset 9 PASS）+ Harness 几何与截图 + 仅源码 |
| V-6 | **切换分类不重复挂载、不崩溃，已输入文本经草稿保留；焦点落到卡片；Harness 注入的输入法组合文本在点导航时被丢弃**。`.yix` 与 `.legacy` 逐项相同。真实输入法组合态**未实证** | Harness（5 个场景 × 2 种实现） |

### V-7 窗口 scope 隔离与回收

```
zw-nonet.sh zig build settings-preview -Dtest-mode=true -j2 --prefix /private/tmp/zw-set-preview
cd <空临时目录> && HOME=$PWD ZENIT_E2E_BACKGROUND=1 ZENIT_E2E_ISOLATE_POINTER=1 ZENIT_E2E_FILE_RPC_DIR=$PWD \
  zw-nonet.sh /private/tmp/zw-set-preview/bin/settings-preview-runner --self-check=v7
```
```
PASS V-7 主窗口与设置窗口各有自己的 Cx 与 SignalOwner（window_id 主=188741 设置=188742）
PASS V-7 view-model 投影信号 attach 在设置窗口的 root scope 上（attach=1）
PASS V-7 投影信号归设置窗口的 SignalOwner 所有，不归主窗口
PASS V-7 设置窗口 scope 上的 effect 随投影信号重算（1 → 3）
PASS V-7 主窗口自己的 effect 不因设置信号变化重算（1 → 1）
PASS V-7 主窗口 effect 即使读了设置窗口的信号也不被订阅（1 → 1；跨 SignalOwner 读取不建立依赖）
PASS V-7 主窗口信号变化重算主窗口 effect（1 → 2）
PASS V-7 主窗口信号变化不触发设置窗口 effect（3 → 3）
INFO V-7 主题是进程级全局（app_theme.select）：在主窗口侧切到 dark 后，设置窗口重新发布主题 1 次并跟随；两个窗口不能各用一个主题
PASS V-7 设置窗口跟随进程主题（与生产 WindowHook 相同）
PASS V-7 关闭前：草稿已改（ssh.keepalive_sec=45，dirty 信号为真）
PASS V-7 关闭前：搜索中（query 信号 = "超时"）
PASS V-7 关闭设置窗口后只剩主窗口（windowCount=1）
PASS V-7 窗口 scope 销毁时执行 ViewModel.detach（detach=1）
PASS V-7 窗口 scope 的 cleanup 全部执行（宿主钩子 +1、探针 +1）
PASS V-7 关闭后存活内存下降：6395447 B / 5392 块 → 685581 B / 148 块（窗口 Cx、scope、投影信号一并释放）
PASS V-7 设置窗口关闭后主窗口的信号与 effect 照常工作
PASS V-7 再次打开：重新 attach，窗口 scope 上的探针是新实例（attach=2）
PASS V-7 持久：位置来自 Controller（page=2；关闭前在搜索，回到搜索起点）
PASS V-7 持久：未保存草稿保留（dirty 信号为真，keepalive_sec=45）
PASS V-7 瞬时：搜索词与搜索框文字复位（query=""，输入框=""）
PASS V-7 瞬时：历史从当前位置重新开始（后退 / 前进不可用）
INFO V-7 关闭态存活字节（4 轮）：685575 / 685575 / 685575 / 685575
PASS V-7 反复开关 4 轮，关闭态存活内存波动 0 B（阈值 64 KiB，不随轮次累积）
PASS V-7 attach / detach 成对（5 / 5）
PASS V-7 DebugAllocator: 进程退出时无泄漏（全部窗口、宿主、Controller 释放后）
SELF-CHECK V-7 passed=24 failed=0
```
`.legacy` 构建同样 24/24（`report-legacy.json`）。

要点与坑：
- **跨窗口读取静默不订阅**：`Signal.get` 只在信号自己的 `SignalOwner` 的图上记依赖（`vendor/zenit/src/ui/reactive/signal.zig:270-283`）。主窗口 effect 读设置窗口信号不会报错，也永远不会因它重算；窗口关闭后再读就是悬空指针。结论：跨窗口只能经 `Controller`（普通数据）或宿主转发，**不要把投影信号指针交给另一个窗口**。
- **关窗是异步的**：原生关闭有约 250 ms 保留期（日志 `macos_window_close_complete … retention=0.250s`），App / 窗口 scope 在那之后才销毁、`destroyed` 回调才执行。依赖“`slot.close()` 之后立即 detach”的代码会出错；自检按 `slot.phase == .closed` 等待。
- **主题**：`app_theme.select` 是进程级全局（`app_theme.zig` 头注释“Selection is global and main-thread owned”），设置窗口 `WindowHook` 每帧比对 `widgetTheme(currentName())` 并重新发布。这与 V-7 的 scope 隔离无关——主题从来不是窗口 scope 上的状态；若将来要“每窗口主题”，需要把 `theme.current()` 的读取全部改成从 `cx.tokens` 取。

### V-11 P3 实证

命令：`--self-check=v11 --chrome=custom` 与 `--chrome=inset`（同上环境变量）；几何：`node e2e/settings_preview_windows_native.ts --parts geometry`。

`--chrome=custom`（关键行；矩形行略）：
```
INFO V-11 chrome=custom requested=custom effective=custom controls=native native_titlebar_height=32.0 maximizable=true
PASS V-11 窗口内容尺寸与生产一致 960x780（实际 960x780）
PASS V-11 windowRegionAt 导航窗口顶空白（红绿灯右侧） (204,32) = .drag（期望 .drag；生产拖动带：逐字 不拖动 / 排除卡片后 拖动）
PASS V-11 windowRegionAt 红绿灯占位中心（原生按钮优先，见源码） (48,32) = .drag（期望 .drag；生产拖动带：逐字 不拖动 / 排除卡片后 不拖动）
PASS V-11 windowRegionAt 页头标题文字 (343,32) = .drag（…）
PASS V-11 windowRegionAt 页头标题与帮助之间的空白 (654,32) = .drag（…）
PASS V-11 windowRegionAt 搜索框 (116,72) = .client（…）
PASS V-11 windowRegionAt 导航行（SSH 与网络） (116,170) = .client（…）
PASS V-11 windowRegionAt 后退按钮 (256,32) = .client（…）
PASS V-11 windowRegionAt 前进按钮 (291,32) = .client（…）
PASS V-11 windowRegionAt 帮助按钮 (928,32) = .client（…）
PASS V-11 windowRegionAt 内容视口 (592,414) = .client（…）
INFO V-11 生产拖动带（逐字：卡片 focusable 使 legacyWindowControlAt 恒真）：0 点
INFO V-11 生产拖动带（排除卡片后的设计意图）：4693 点（x 80..952, y 0..44）
INFO V-11 windowRegion 拖动：4747 点（x 16..956, y 8..54）
INFO V-11 两者都拖动：3609 点（x 80..952, y 8..44）
INFO V-11 仅拖动带（排除卡片）：1084 点（x 80..952, y 0..44）
INFO V-11 仅 windowRegion：1138 点（x 16..956, y 8..54）
INFO V-11 生产拖动带（逐字，卡片暂时取消 focusable）：4693 点（x 80..952, y 0..44）
PASS V-11 windowRegion 拖动区内没有交互控件（指针命中目标是按钮/输入框/导航行的点 = 0）
INFO V-11 方案 A（只标导航窗口顶 + 页头）未覆盖的拖动带点（不含 8pt 外边距 / 缝；即导航 10pt 上内边距与右内边距）：208 点（x 80..220, y 8..44）
PASS V-11 方案 B（再给卡片 settings.panel 标 .drag）覆盖拖动带全部可拖点且不含交互控件（未覆盖 0，控件冲突 0）
INFO V-11 方案 B 在标题栏以下（y≥100，步长 8x8）也可拖的点（导航说明、外边距与缝、Save Bar 外的空白）：522 点（x 0..952, y 104..776）
PASS V-11 DebugAllocator: 进程退出时无泄漏（全部窗口、宿主、Controller 释放后）
SELF-CHECK V-11 passed=15 failed=0
```
`--chrome=inset`：同样 `effective=custom`、`native_titlebar_height=32.0`，控件点全为 `.client`，`SELF-CHECK V-11 passed=9 failed=0`，并输出：
```
INFO V-11 发现：生产 .custom_inset 下设置窗口卡片 settings.panel 为 focusable（宿主为接住 Escape/⌘W），legacyWindowControlAt 在卡片内恒为真，拖动带 0 点可拖（取消 focusable 后 4693 点）——仅源码 + runner 自检推断，真实拖动未实证
```
Harness 几何（`report-yix.json` 的 `geometry`）：15 个节点矩形 `mismatched_rects: []`；截图比对 `full / island / viewport / navigation` 均 `different: 0`（2x，1920×1560）；`resizeWindow(600, 400)` 后两种配置的 `settings.window` 都是 760×480。截图不含原生红绿灯（它们是 AppKit 子视图），所以“红绿灯与导航的相对位置”由源码判定。

逐项结论：

| 项 | 结论 | 证据 |
|---|---|---|
| 生效模式 | `.custom_inset`（`chrome == null`）经 `window_config.zig:60` `requestedChrome` 翻成 `.custom`；两条路径的差别只有：拖动判定（拖动带 + `legacyWindowControlAt` vs `chromeHit` + `windowRegionAt`）与 `runtime.zig:812-819` 额外的 `setTrafficLightsInset(7, h/2)` + `setTitlebarDragHeight` | 自检 + 源码 |
| 标题栏高度 / 布局 | 节点几何与整窗像素完全相同；原生标题栏高度都是 32 | Harness + 自检 |
| 窗口尺寸 / 最小尺寸 | 960×780；两者都夹在 760×480 | Harness |
| 拖动命中 | 方案 A（导航窗口顶 + 页头 `.drag`）：控件全部 `.client`，覆盖设计意图里拖动带的 77%，漏掉导航 10pt 上内边距、导航右内边距、窗口 8pt 外边距与导航 / 内容间 8pt 缝；多出页头 46–56pt 一条与红绿灯左侧（被原生按钮接管）。方案 B（再给卡片标 `.drag`）：完全覆盖、无控件冲突，但标题栏以下的非交互空白（导航说明、边距、缝）也可拖 | 自检 |
| **生产拖动带** | **设置窗口当前拖不动**（推断）：卡片 `focusable`（`settings_host.zig:743`、`:1610`）→ pointer 命中角色 → `legacyWindowControlAt` 恒真 → `zenitArmTitlebarMouseDown`（`window_bridge.m:3283-3307`）对带内每个点都交给应用 | 自检 + 源码；**真实拖动未实证** |
| 红绿灯 | 两条路径都先由 `macos_chrome_configure`（`window_bridge.m:8263`）放到 `(7, h/2)`，`.custom_inset` 再由 `runtime.zig:814` 重复一次；生产与 runner 随后都调 `setTrafficLightsLayout(28, 32, 12)`（`process_windows.zig:116`），后者覆盖前者并在每次 AppKit 重排时重放 → **最终布局等价**。`chrome` 路径用 `chromePointInNativeButton`（`window_bridge.m:3270`）让原生按钮优先；拖动带路径靠 `x <= 78` 排除 | 仅源码 |
| 双击缩放 | 两条路径都是 `MetalView mouseDown`（`window_bridge.m:954-962`）在 `zenitTakePendingWindowDrag` 成立后调 `zenitPerformTitlebarDoubleClick`（`:646`，遵循系统“双击标题栏”设置，缩放受 `maximizable` 约束）→ **等价**，前提是该点被判定为可拖 | 仅源码；**未实证** |
| 全屏 | 两条路径在全屏和全屏过渡中都不拖、不缩放（`zenitArmTitlebarMouseDown` 第一行）；Harness 没有全屏命令，原生全屏会占用用户桌面空间，**未实证** | 仅源码 |

#### 给人执行的手工验证清单（V-11 + V-6，5 步）
1. 构建并前台启动（不设 `ZENIT_E2E_BACKGROUND`）：`zw-nonet.sh zig build settings-preview -j2 --prefix /private/tmp/zw-set-preview-manual`，然后分别运行 `…/bin/settings-preview-runner --page=ssh --sub=0 --chrome=custom` 与 `--chrome=inset`（两个窗口可并排）。
2. 拖动：在两扇窗口里分别按住红绿灯右侧空白、页头“连接”标题、页头标题与帮助按钮之间的空白拖动。期望：`custom` 能拖；`inset` 若拖不动即证实上面的“生产拖动带失效”（再到正式 App 的偏好设置窗口顶部试一次确认）。按住后退 / 前进 / 帮助 / 搜索框不应移动窗口，按钮照常响应。
3. 双击：在 `custom` 窗口的同一空白处双击，期望按“系统设置 → 桌面与程序坞 → 双击窗口标题栏”执行（缩放 / 最小化），再双击还原；双击后退按钮不缩放。
4. 红绿灯：悬停时出现符号，位置与导航顶部的占位对齐、两扇窗口一致；点黄色最小化、绿色进入全屏，全屏时看导航顶部布局，退出全屏后位置复原。
5. 输入法（V-6）：在 `custom` 窗口点“保活间隔”输入框，切到拼音输入 `shi` 不上屏，直接点左侧“文件传输”，再点后退。记录：候选窗是否关闭、`shi`/汉字是否上屏、字段值是否变化、焦点位置；在搜索框重复一次。

#### 生产窗口是否切到 `chrome = .custom` + `windowRegion`
**建议切**（设置窗口先切，向导窗口随后），理由：现有拖动带在设置窗口里被卡片的 focusable 整体屏蔽（需第 2 步人工确认）；`windowRegion` 路径的几何、像素、尺寸与现状完全相同，控件排除由命中语义自动保证，不再依赖“左 78pt / 右 inset”矩形。**只给建议，本包未改生产。**

改动清单：
1. `src/shared/ui/window/aux_window.zig`：`Spec` 增加 `chrome: enum { titlebar_band, window_regions } = .titlebar_band`（默认保持现状，逐窗口切换）。
2. `src/app/process_windows.zig:107`（`drainAux`）：`window_regions` 时设 `.chrome = .{ .custom = .{} }`，保留 `.titlebar_height`（`chrome_backend.configure` 需要正数高度），去掉 `.titlebar = .custom_inset`；`:116` 的 `setTrafficLightsLayout` 不变。
3. `src/features/settings/view/settings_shell.zig` `window_spec`：选 `window_regions`。
4. 视图标注（二选一）：方案 A——`view/nav.yix` 的 `settings.header` 与 `view/header.yix` 的 `settings.page.intro` 加 `windowRegion={.drag}`（建议同时把导航顶部内边距并进 `settings.header`，补上 10pt 上内边距）；方案 B——`view/settings_window.yix` 的 `settings.panel` 加 `windowRegion={.drag}`。3f 前 `.legacy` 外壳若仍要可用，`settings_shell.mount` 里对同名节点设 `behavior.interaction.window_region`。
5. 向导窗口（同一 `aux_window` 路径，默认 `titlebar_height` 44）：先核查它的根卡片是否也 focusable（同样会让拖动带失效），再给它的标题区标 `.drag`。
6. 测试：`aux_window.zig` / `settings_shell.zig` 的 spec 单测；runner 的 `--self-check=v11` 改为断言生产 spec；主程序的设置 e2e 不受影响（Harness 点击不经原生拖动判定）。

已知差异与风险：
- 方案 A 漏掉导航 10pt 上内边距与外边距；方案 B 让标题栏以下的非交互空白（导航说明、边距）也可拖，可能误拖。
- `windowRegionAt` 在 tick 中或树变动时一律返回 `.client`（故意的 fail-closed），重建期间的按下不会拖窗口。
- `chrome` 路径不再有“左 78pt”保护带；红绿灯由 `chromePointInNativeButton` 保护，但红绿灯占位（`settings.header.traffic_lights`）里按钮之间的缝在方案 A/B 下是可拖的（现状是不可拖）。
- 主窗口同样是 `.custom_inset` + 拖动带（`process_windows.zig:139`），本包没有核查它的根是否 focusable；若同样被屏蔽，应一并处理。
- macOS 不消费 `.close` / `.minimize` / `.maximize` 区域（P0 结论），不要用它们代替原生红绿灯。

### V-6 切换分类时的焦点与未提交文本

命令：`.yix`（默认构建）与 `.legacy`（临时把 `settings_view_mode.zig` 改成 `.legacy`，`--prefix /private/tmp/zw-set-preview-legacy` 构建后**还原、未提交**）各跑 `node e2e/settings_preview_windows_native.ts --parts v6 --label yix|legacy`。起点均为 SSH 与网络 › 连接（`--page=ssh --sub=0`）。

| 场景 | `.yix` | `.legacy` |
|---|---|---|
| 字段里输入 `47`（未按回车）→ 点“文件传输” → 后退 | 切换后标题“文件传输”、`settings.content` 1 个、搜索框 1 个、Save Bar“未保存”；焦点落到卡片 `settings.panel`；后退后字段显示 `47`（来自草稿），焦点仍在卡片 | 相同 |
| 字段里逐字输入 `4`、`6` | 焦点一直在同一个输入节点（节点 id 不变），值 `46`，内容页不重挂 | 相同 |
| 字段里 Harness 注入输入法预编辑 `12`（`ime_phase=composing`）→ 点“文件传输” → `imeCommit` → 后退 | 点导航后立即切到“文件传输”，字段已卸载（`isComposing` 推迟重建的保护没有拦住——推断：点击先让输入框失焦、组合随之结束）；之后的提交落空；后退后字段为原值 `30`，**预编辑文本被丢弃**；无崩溃 | 相同 |
| 搜索框输入 `超时`（结果页）→ 点“文件传输” | 搜索框被清空（`clear_search_field`，导航清空搜索是设计行为）、焦点落到卡片、搜索框仍是同一个 | 相同 |
| 搜索框逐字输入 `保`、`活` | 每次输入结果页重挂，焦点一直在搜索框（同一节点），值 `保活` | 相同 |

结论：在 runner 复刻的宿主逻辑下，`.yix` 外壳与旧实现行为一致；没有重复挂载或崩溃；字段文本经草稿保留，搜索词按设计清空；切换分类后焦点落到卡片而不是被点的导航行（`.yix` 的导航行随内容纪元重挂，旧实现整列重建），键盘用户需要再按 Tab 才回到导航——如需“焦点留在导航行”，要在重挂后按行 key 恢复焦点。**真实输入法**：Harness 的 `imePreedit` 直接写组件的组合状态、不经过 macOS 输入法，候选窗、`unmarkText` 与系统在失焦时提交还是丢弃都**未实证**，见手工清单第 5 步。

### 门禁与复现（本包运行结果）

- `zig build settings-preview -Dtest-mode=true -j2 --prefix /private/tmp/zw-set-preview` 通过；`node e2e/settings_previews.ts` 10/10（content 5 + window 5）；`node e2e/settings_preview_windows_native.ts`（yix：plugins / selfcheck / geometry / v6 全部通过；legacy：selfcheck / v6 通过）。
- `zig build check-yix` 退出码 0；`zig build check-arch`：import 基线 785 条，当前 785 条，无新增；test-ids 通过（源码新增 0 条）。
- `zig build -j2`、`zig build compile-tests -j2`（不带过滤地编译测试的全部用例但不运行；原先的 `-Dtest-filter=__none__` 兜底已废弃：过滤会跳过不匹配用例的语义分析，拦不住测试体里的错误）、`connection-progress-preview` / `auth-challenge-preview` / `transfer-events-preview`（`-Dtest-mode=true`）均通过。
  - `compile-tests` 的覆盖范围（build-compile-tests 包起）：两个聚合根 `src/root.zig`（`-Dtest-filter` 用的 `tests`）与 `src/tests_ui.zig`（`-Dui-test-filter`），以及六个带固定过滤的独立根各自的无过滤编译 `<root>-tests-unfiltered`：`test-update`（`src/tests_update.zig`）、`test-bmc`（`src/tests_bmc.zig`，本身也经 `root.zig` 进聚合根）、`test-plugin-fixture`（`src/tests_plugin_fixture.zig`）、`test-builtin-records`、`test-compaction-e2e`、`test-ai-gateway`（后三者经 `src/acceptance.zig` 选根）。无过滤编译与运行用的编译共用 `build.zig` 的 `addStandaloneTest()` 配置；`acceptance.zig` 三个根去掉过滤后会分析实现文件 import 闭包里的全部 test，所以无过滤编译额外补 `ui` / `zenit_app` / `icon_ir` / ssh 与 ghostty 的 translate-c 模块（`unfiltered_closure`），运行步骤不变。该步骤只做语义分析（构建系统给不被消费的产物传 `-fno-emit-bin`），不链接、不运行；与 `-Dtest-filter` / `-Dui-test-filter` 同用时直接报错。其它测试根（如 `test-arch`、`test-font`、`test-appearance`、`test-applog`、`test-local` 系列及各 native 回归）不在本步骤内。
- 主程序：`zig build -Dtest-mode=true -j2 --prefix /private/tmp/zw-set-preview-app` 后 `settings_revamp_native.ts`（light、dark）与 `workspace.ts` 通过；对 `p0-baseline/SHA256SUMS`：59 OK，仅 `dark-updates.png`、`light-updates.png` 不同（构建信息，预期）。
- 证据目录：`~/work/ZeroWork-evidence/set-preview/`（`previews/`、`windows-yix/`、`windows-legacy/`、`settings_revamp-*`、`workspace/`）。

---

## V-9 `std.zig.Tokenizer` 提取 `.yix` 的 `@import`

**成立。** 详见 `tools/arch/README.md` 的“V-9”一节：用 `check-arch` 的 `list-imports` 扫描 `vendor/zenit` 下全部 40 个 `.yix`，提取 101 处 `@import`，与 grep 的结果逐条（文件 + 目标）一致；`zig build test-arch` 里有 3 个以 zenit 自带 `.yix` 为样本的单测，含撇号、引号、URL 中 `//` 等对抗性模板文本。`check-arch` 因此直接扫描 `.yix` 源文件，跳过生成的孪生文件。

建议修订：§4.3 第 2 条去掉“推测”。

## V-10 `--summary all` 能否给出用例总数

**不成立，有替代写法。** 详见 `docs/ui-revamp/baselines/tests.md` 的“V-10 结论”：`test` / `test-ui` 用 `Run.create` + `addFileArg` 运行测试二进制，构建器不走测试协议，`--summary all` 的步骤树里没有用例数。替代口径是测试二进制自己的输出（逐用例 `序号/总数 名称...OK|SKIP|FAIL` 与末尾 `N passed; M skipped; K failed.`，有失败时同样完整）；后备口径是 `zig build check-arch -Darch-args="count-tests <根文件>"` 的静态上界。

建议修订：§6.2 P0 第 4 条、P1 退出标准里“用例总数”的口径改为上述两种；§9.2 同步状态。

---

## 复现方法

所有执行命令都包在无网络 sandbox 里（`~/work/zerowork-security-audit/zw-nonet.sh`，下文简写 `zw-nonet.sh`），在工作树根目录执行。

```sh
# 孪生文件与检查
zw-nonet.sh zig build gen-yix          # 输出: yix gen: 6 file(s)；之后 git status 干净
zw-nonet.sh zig build check-yix        # 退出码 0

# 预览程序
zw-nonet.sh zig build mockup -Dmockup=yix_spike -j2 --prefix /private/tmp/zw-v1-spike-out

# 无窗口自检（会短暂创建窗口，后台模式不抢前台；自检结束即退出）
cd /private/tmp/zw-v1-spike-run && YIX_SPIKE_SELFCHECK=1 ZENIT_E2E_BACKGROUND=1 ZENIT_E2E_ISOLATE_POINTER=1 \
  zw-nonet.sh /private/tmp/zw-v1-spike-out/bin/mockup-yix_spike
# 期望最后一行: SELFCHECK 61/61，退出码 0

# 真实窗口 Harness 取证
zw-nonet.sh zig build mockup -Dmockup=yix_spike -Dtest-mode=true -j2 --prefix /private/tmp/zw-v1-spike-tm
zw-nonet.sh node e2e/yix_spike_native.ts /private/tmp/zw-v1-spike-tm/bin/mockup-yix_spike /private/tmp/zw-v1-spike-run/e2e
# 期望 8 行 PASS，report.json status=passed；截图 initial.png / final.png 在证据目录

# V-1 最小实验（仓库外；文件内容见 §V-1）
cd /private/tmp/zw-v1-import-exp && for c in a b c d; do zw-nonet.sh zig build run -Dcase=$c; done

# V-4 编译错误复现：把 views.yix 里 DirectPanel / DirectIf / DirectSwitch / DirectOptional / DirectFor
# 中的 vm.<field>.get() 改回 vm.<field>，gen-yix 后构建 mockup。
# V-3 结构体字面量复现：把 spike.v3.add 的实参改成 .{ .set_count = 5 }，gen-yix 即报错。

# 主程序
zw-nonet.sh zig build -j2
```

本次运行结果：gen-yix 后 `git status --short` 无孪生差异；check-yix 退出码 0；mockup（含 `-Dtest-mode=true`）构建通过；自检 `SELFCHECK 61/61`、退出码 0；Harness 8/8 PASS；`zig build -j2` 通过（输出尾行 `SSH sources/configuration/archives verified`）。运行后没有残留的 `mockup-yix_spike` 进程。

spike 文件一览：

| 路径 | 内容 |
|---|---|
| `tools/mockups/yix_spike.zig` | mockup 入口：`mount` / `title` / `window_size`；`YIX_SPIKE_SELFCHECK` 分流 |
| `tools/mockups/yix_spike/vm.zig` | view-model（信号字段、`ui.Memo` 字段、`dispatch(Intent)`、探针计数） |
| `tools/mockups/yix_spike/views.yix` | 每个 V 项一个组件（含 V-4 反例） |
| `tools/mockups/yix_spike/parts/count_row.yix` | V-1：子目录组件，`../` 引回上层 |
| `tools/mockups/yix_spike/styles.yss` | 样式 |
| `tools/mockups/yix_spike/legacy.zig` | V-5：仿旧面板 + `ComponentOf` 适配 + 外部 scope 反例 |
| `tools/mockups/yix_spike/selfcheck.zig` | 无窗口自检（DebugAllocator 查泄漏） |
| `e2e/yix_spike_native.ts` | Harness 真实窗口取证 |

---

## 验证中发现的 zenit 缺口 / 需要上游补的点（只登记，未改 vendor）

| 编号 | 缺口 | 现象 | 建议 |
|---|---|---|---|
| G1 | 经组件参数取响应式字段不展开（`{vm.field}`） | `derive` 产出 `Source(*Signal(T))`，运行时只解一层；插值静默输出 `{any}` 结构体转储，其他位置编译报错 | `derive` / `yixValue` 对“值本身是响应式源”的结果做一次扁平化（转发内层源，与 `ReturnedSource` 路径一致）；至少让 `yixFormat` 遇到响应式指针时 `@compileError`，不要静默转储 |
| G2 | 事件实参不能含结构体字面量 | `send(vm, .{ .x = 1 })` 被当作字段写入拒绝（`compiler.zig:2618` `containsAssignment`） | `containsAssignment` 跳过 `.{ … }` / `T{ … }` 初始化列表里的 `=` |
| G3 | `{switch}` 不支持多值分支 | `.a, .b => …` 报 `unexpected token` | 支持逗号分隔的分支值（Zig 原生语法） |
| G4 | 标签内的 `//` 注释变成文本节点 | `literal_text = "// …"` | 模板内识别并丢弃 Zig 行注释，或报错提示 |
| G5 | `windowRegion` 与旧 `titlebar = .custom_inset` 路径静默不兼容 | 旧路径下设置 `windowRegion` 不报错也不生效 | 旧路径下检测到非 `.inherit` 的 `window_region` 时打一次警告，或让旧路径也读 `windowRegionAt` |
| G6 | `ComponentOf` 只接受 `(Props, *Scope, *Cx)` | 旧代码普遍是 `(cx, scope, …)` 或 `(cx, bound)`，每个都要手写适配 | 可选：提供 `ui.view.componentFromLegacy(f)` 之类的适配助手；不阻塞 |
| G7 | 文档未进 vendor 快照 | 本次只能读编译器与测试源码得出 Yix 语法限制 | 即方案 §3.5 的 Z1 |

## 存疑与未覆盖

- V-5 用的是仿制面板；真实设置面板（Tooltip / Popover / IME 客户端注册、`Mounted` 句柄）的嵌入在 P3 复验。
- V-11 的原生拖动、红绿灯布局、macOS 上 `.close` 等区域的处理只有源码结论。
- 自检运行在独立的无窗口 `Cx` 上（与 zenit 自己的 `tests/yix/runtime_tests.zig` 同法），主题切换用的是 zenit 内置 light/dark token，不是 ZeroWork 的 `app_theme`。
- 没有测量编译时间与体积（V-8，不在本轮）。

---

## P3 样板阶段的复验与新增结论（F-set-shell，3c + 3d）

基线：`revamp/set-shell`（自 `b23880f3` 切出）。代码：`src/features/settings/view/{settings_window,nav,header,page,overview,save_bar}.yix`、
`view/components/{shell,legacy_body,fields}/mod.zig`、`view/components/rows.yix`、`view/window_frame.zig`；
测试：`tests/settings_window_semantic_tests.zig`（7 个用例对新旧两种实现各跑一遍）、`tests/settings_window_yix_tests.zig`（8 个）、
`tests/settings_rows_tests.zig`（4 个）。

| 编号 | 结论 | 证据类型 |
|---|---|---|
| V-5（真实面板） | **成立**。真实旧正文按 `settings_content_view.mountBodyOnly`（新增，`Binding` 建在传入的 scope 上）经 `ComponentOf` 嵌入：内部 test_id 可从窗口查到；内容页换纪元时旧组件 scope（`Binding`、输入法客户端、Tooltip / Popover 登记、after-layout 钩子）随之释放，20 轮重挂后 after-layout 钩子数不变，`std.testing.allocator` 无泄漏；`Binding` / scope 经 `Frame` 交还宿主，并在组件 cleanup 里清空。**主题**：`.yix` 外壳的具名样式在主题发布时直接重放；真实旧面板的卡片颜色是挂载时求值（`settings_styles.paneSurface()` 读 `app_theme.current()`），不随 on_theme 重放——旧宿主本来就靠“主题发布 → 整页重建”跟随，`.yix` 路径同样发一个纪元重挂，重挂后为新主题颜色 | 无窗口组件测试（`settings yix window embeds the real legacy panes …`、`… theme publication repaints …`）；真实窗口 e2e（`settings_revamp_native.ts` 明暗各 13/13） |
| V-6 | **部分成立**。搜索框在纪元重挂范围之外（与旧外壳相同，挂一次），切换分类不会重建它，搜索框里的组合与焦点不受导航影响。面板正文 3d 仍是旧实现，切换分类 / 草稿变化仍要整页重挂正文，所以“组合期间推迟重建”（宿主 `WindowHook` 读 `Page.isComposing()`）**保留**，`.yix` 路径照用；焦点快照 / 恢复照旧（两阶段重挂的第二阶段恢复）。正文 Yix 化（3e）后才能去掉推迟逻辑，届时再实证。Harness 合成输入不经过输入法，组合态本身**未实证** | 源码 + 无窗口合成输入（语义用例的 `typeInto`） |
| V-7 | **未实证**。设置预览 runner 本包没有升级到多窗口（见“未完成”）。源码层面：view-model 信号由 `attach(scope)` 建在设置窗口的 scope 上，窗口销毁时宿主 `detachWindow` → `vm.detach()`，信号随窗口 scope 释放 | 仅源码 |
| V-11 | **未实证**，生产窗口**保持** `titlebar = .custom_inset` + `titlebar_height` 拖动带，没有切 `chrome = .custom`；`.yix` 外壳没有写 `windowRegion`（写了也会被旧路径忽略，G5）。红绿灯位置、拖动、双击缩放留给预览 runner 升级后实证 | 仅源码 |

### 写法与坑（3c / 3d 实测，均有绕法）

1. **after-layout 钩子在批处理里**（`cx_render.runAfterLayoutHooks` 包了 `beginBatch / endBatch`）。宿主在钩子里改信号（发纪元）后，Yix 的重挂要等批结束才发生；同一轮里读组件交还的句柄拿到的是**旧页**的（随后被释放）。首次真实窗口 e2e 因此在 `restoreScroll` 段错误。绕法：两阶段——`rebuildYixContent` 只发纪元并置 `yix_settling`，下一轮钩子 `settleYixContent` 再取新句柄、释放选择器节点、恢复焦点与滚动。无窗口测试里没有批，重挂是同步的，**测不出这个问题**；宿主类改动必须跑真实窗口 e2e。
2. **`ComponentOf` 标签的属性**：引用了组件参数 / 行变量的表达式以 `ui.Source(T)` 传入；常量表达式（`.save`、`T.x`、字面量）**原样传值**。Props 字段类型要按实际写法声明（随数据变的用 Source，只写常量的用值类型）；把枚举字面量传给 Source 字段报 `union has no member`。
3. Zig 组件 Props 字段名必须是 `snake_case`：Yix 把标签上的 camelCase 属性映射成 snake_case 字段（`fieldId` → `field_id`）。
4. Yix 事件处理器（`onChange={|t| …}`）传给 Zig 组件时类型是 `ui.on.AnyHandler(...)`，具体类型的 Props 字段（`?ui.Handler(T)`）接不住；绕法：把 `vm` 与字段传进组件，组件内自己 `dispatch`。
5. 组件参数不能叫 `key`（`{for}` 行 key 属性）或 `testId`（写在组件标签上是组件根节点的属性，不进 props，必填参数会报 `missing required prop 'test_id'`）。行组件用 `setting`、`paneId`。
6. 一个组件只能有一个 `Text` 参数（文本子节点归它）；其余字符串参数写 `[]const u8`。
7. `parts={.{ .input_container = id }}` 只收静态字面量；经参数传进来的 id 是 Source，报 `props must be a struct literal`。要把 id 落在内部部件（输入框 `input_container`、选择框 `trigger`，§6.3 第 4 条），只能用 Zig 小组件挂载后写（`components/fields/mod.zig`）。
8. 文本节点自己的盒样式（宽度、`min_width`、`flex_shrink`）不能写进 `TextStyle`，用 `<text box={S.x}>`。
9. 无参、返回大结构体（`?BoxStyle`）的函数作属性值（`hoverStyle={hover()}`）会让 `yixCallMayDerive` 递归超过 1000 次 backwards branches；给函数加一个 `vm` 参数即可绕开。
10. `W.Button` 没有 children 插槽。旧导航行 / 概览行是把图标与文字追加进 ghost Button 的根节点，Yix 表达不出同构树；要截图逐字节一致，只能 Zig 组件挂同样的 widget（`components/shell`）。Tooltip 包按钮（页头帮助）同理。
11. Yix 的 `{for}` 是列表重挂的唯一 key 机制（`key=` 只能写在 for 行根）；“按纪元整页重挂”写成单行列表：`{for (vm.contentEpochs()) |e| <Page key={e} …/>}`。返回的切片要换地址（view-model 里两份交替），否则按内容判等可能当作没变。
12. yix 编译器遇到花括号不配平的 `.yix` 会直接 panic（`compiler.zig:1027` `catalogRoots` integer overflow），不是报错定位。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 建议 |
|---|---|---|
| G8 | `parts` 的 id 不能是源 | 允许 `Source([]const u8)`（挂载时取值，同 `testId`）。**已由上游修复（vendor @6062d925）**，F-set-thin 实测：`rows.yix` 的 `parts={.{ .input_container = fieldId }}` / `.trigger = fieldId` |
| G9 | `ComponentOf` Props 接不住 Yix 事件处理器（`AnyHandler`） | `coerceLiteral` 识别 `zenit_any_handler`，按目标 `Handler(T)` 调 `.as(T)`。**已由上游修复（vendor @6062d925）**：入口写 `fn X(props: anytype)`，实测 `SearchField onChange={|q| …}`、`SaveButton onClick={run(vm, .save)}` |
| G10 | 常量 / 非常量属性传给 `ComponentOf` 的形态不一致（值 vs Source） | 一律包成 Source，或在 Props 为值类型时对 Source 报清楚的编译错。**已由上游修复（vendor @6062d925）**：`anytype` 入口下 Source 字段常量 / 源都收，值字段收到源编译报错 |
| G11 | `W.Button` 无 children 插槽 | 增加内容插槽（图标 + 文字列这类行按钮），否则行按钮只能 Zig 组装。**已由上游修复（vendor @6062d925）**：新增 `W.Pressable`（往 Button 写子元素改为编译错误）；导航行 / 概览行已改用，截图逐字节一致 |
| G12 | yix 编译器对不配平花括号 panic | 报带位置的错误。上游声明已修复（vendor @6062d925），本包未复验 |
| G13 | 无参函数属性的 `yixCallMayDerive` 递归超 branch quota | 在生成代码里提高 quota，或对 `BoxStyle` 一类已知类型短路。上游声明已修复（vendor @6062d925），本包未复验（本包删掉了这类函数） |

---

## P3 “去覆盖”（F-set-thin，vendor @6062d925）

基线：`revamp/set-thin`（自 `fce71182` 切出）。目标：设置外壳“薄 Zig、厚视图”。结果：外壳 `.yix` 里不再有读
`app_theme` 的颜色（Glass Nav 的几何 / 35% 与“保存更改”的渐变除外，见下表）；导航行、概览行、行组件的输入 / 选择框、
Save Bar 的“恢复默认 / 撤销”、宿主状态行收回 `.yix`；截图 61 张里 59 张与 P0 基线逐字节一致（两张 `*-updates.png` 是构建信息）。

### 仍留在 Zig 的组件与原因（`view/components/shell/mod.zig`，入口都是 `props: anytype`）

| 组件 | 原因 |
|---|---|
| `NavScroll` / `Viewport` | 宿主要 `ScrollState` 记忆 / 恢复滚动（after-layout 钩子里），视口还把句柄交给 `Frame` |
| `SearchField` | 宿主要 `InputResult`：`Effect.clear_search_field` 改输入状态；`paintSearch` 把占位符色写进输入状态、聚焦描边随 `state.focused`（都不是节点样式，parts 叠加不了）；跨内容页存活 |
| `HelpButton` | Tooltip 的 trigger 插槽只有 Zig 视图 API（`.trigger(…)`），Yix 没有写法；`settings.help.content` 在 `TooltipResult.content` 上，不在 `viewParts`（G16）；玻璃外观是 Button 的 StyleOverride（G15） |
| `SaveButton`（“保存更改”） | 渐变随悬停 / 按下 / 主题发布逐帧写 inline；YSS `gradient` 没有 token 写法、读主题的 `{t}` 样式不收条件块，渐变端点（`states().primary*_to`）也不是 token（G17） |

### 新坑（实测，均有绕法）

13. **配方维度值只能是单个名字**：`style={S.NavRow.of(.{ .selected = item.selected })}`（行变量的字段访问）或
    `.{ .locked = locked(vm) }`（带参调用）不会像普通属性那样提升为源，生成代码把 `Source` 原样塞进去 → Zig 编译错误
    （`no field named 'selected' in union Source(NavItem)`、`expected *ViewModel, found Source(*ViewModel)`）。
    绕法：把行写成行组件（字段变成参数），或在组件体里 `const off = computed(locked(vm));` 再 `.{ .locked = off }`。登记 G14。
14. **ghost `W.Button` 根的墨色会级联到追加进根的文字**：文字节点总是读继承色，盖过自己 `TextStyle.color`；显式 `iconTint`
    的图标不读继承色。旧导航行 / 概览行里设计要求的次要墨色（分类名 fg_2、概览摘要 secondaryInk）实际画成 fg_1。
    用 `W.Pressable` 复刻时要照搬（根上写 `color`，文字不写颜色）才能逐字节一致——是否改回设计值需另行裁决。
15. **Button 空 content 槽占位**：`label = ""` 且没有图标时 `shows_label` 为真，宽 0 的 content 槽仍参与 flex，多出一个 `gap`
    的左偏移（导航行 8、概览行 12）。Pressable 复刻用左内边距补齐。
16. **yss 的 `border: 1 <颜色>` 写的是细粒度 `border_color`**，Zig 里整体替换 `.border` 结构体改不了它的颜色：原
    `glassNav` / `footer` 的描边覆盖一直没生效（改成 `border: 1 border` 实测 918 像素差），token 化时保持 `bg-active`。
17. **Button 的 `baseStyle` / `hoverStyle` / `pressedStyle` 只收具体值**（`StyleOverride`，没有 token 引用）：要主题色只能在
    Zig 里读 `app_theme`，或者写根上的 `style` 叠加层（token 配方）——叠加层压过色调的**一切**状态（含 `:disabled`），
    需要禁用态时把禁用作为配方维度显式写（`GlassNavButton.of(.{ .off = … })`、`FooterLink.of(.{ .off = … })`）。登记 G15。
18. **`<text>` 上可以用配方**（`S.NavLabel.of(.{ .selected = s })`），文字属性与盒属性仍分开（盒的部分写 `box={…}`）。
19. **新 token 要两处登记**：`zerowork.tokens.json` 只声明字段与没有发布时的默认值；运行期值由
    `app_theme.widgetTokensFrom` 按当前调色板发布（39 个注册表主题、材质透明度、壁纸都经它；`select` / `selectTokens` /
    `setMaterial*` 都会 `refreshWidgets`）。只加 json 的话，内置调色板下会画成 json 的默认值。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G14 | 配方维度值不提升 | `{for (xs) \|x\| <box style={S.R.of(.{ .on = x.on })} />}` → `no field named 'on' in union Source(…)` | 维度值按普通属性表达式处理（引用源时生成 memo）。**已由上游修复（vendor @9e97b7a6）**，F-set-recover 已采用：`NavEntry` / `OverviewEntry` 并回 `{for}` |
| G15 | Button 状态样式不收 token | `<W.Button pressedStyle={…}>` 只能给 `?StyleOverride` 具体颜色 | `baseStyle` / `hoverStyle` / `pressedStyle` 接受 YSS 配方或 `ConditionalStyle` 源（同 Pressable 的 `look`），按色调状态并入。**已由上游修复（vendor @9e97b7a6，`W.Button` 的 `look`）**，F-set-recover 已采用：“保存更改”、帮助、后退 / 前进 |
| G16 | Tooltip 没有 Yix 形态 | `<W.Tooltip text="x"><W.Button …/></W.Tooltip>` 无 trigger 插槽写法；`TooltipResult.content` 不在 `viewParts` | Yix 里 children 进 trigger；`viewParts` 暴露 `content` 供 `parts={.{ .content = id }}`。**已由上游修复（vendor @9e97b7a6）**，F-set-recover 已采用：页头帮助 |
| G17 | 渐变不能 token 化且不能分状态 | `style g { gradient: …; :hover { gradient: … } }` 只能写 `{zig}`；读主题的 `{t}` 样式静默丢掉 `:hover` | `gradient: <token> <token> diagonal` 写法，条件块里可用。**已由上游修复（vendor @9e97b7a6）**，F-set-recover 已采用：`save_fill` |

### 修订后的样板写法要点（供方案 §4 / §5 定稿）

- **颜色只走 token**：`.yix` / `.yss` 不读 `app_theme`。ZeroWork 特有的派生色（不透明窗面、玻璃悬停、随材质加深的次要墨色）
  做成 `zw_*` token：json 声明 + `widgetTokensFrom` 发布 + 一个“token == 原 Zig 算式”的全主题等值测试（见
  `settings_window_yix_tests.zig` 的 `expectWindowTokens`）。能复用 zenit 语义 token 的直接复用（`bg-hover` = states().hover，
  `bg-active` = states().pressed，`button-primary-bg/fg` = action accent 及其前景，`info` = accent_ink，`success` = ok_ink）。
- **行按钮用 `W.Pressable`**，外观写成配方（`selected` / `locked` 维度，`:hover` / `:active` 条件，`transition`）；
  行写成**行组件**（`fn NavEntry(vm, page: u8, selected: bool, locked: bool) View`），`{for}` 里只放 `<NavEntry key={…} … />`。
- **控件内部部件的 id 用 `parts`**（`parts={.{ .input_container = fieldId }}`），控件值受控（`value={…}` 来自 view-model）。
- **Button 的主题色走根上的 `style` 叠加层**，几何留在 `baseStyle` 常量；叠加层会压过禁用态，禁用要作为配方维度。
- **宿主状态进 `Ports.status`**（`HostStatus`），view-model 出选择器，模板 `<text visible={…}>{…}</text>`；宿主改状态后 `vm.sync()`；
  宿主持有的字符串换文字时换地址（双缓冲）。
- **手写 Zig 组件入口一律 `fn X(props: anytype)`**，Props 里随数据变的字段写 `ui.Source(T)`，事件写 `?ui.Handler(T)`，
  由模板直接传 `onX={…}`；组件不自己 `vm.dispatch`。
- **像素基线是硬约束时先比对旧 widget 的隐性外观**（色调级联、空槽占位、被压过的覆盖），照搬并在 yss 注释里写明；
  是否回到设计值单列裁决，不在“行为不变”的包里顺手改。

---

## P3 收回上游缺口（F-set-recover，vendor @9e97b7a6）

基线：`revamp/set-recover`（自 `0db03c96` 切出）。用上游补的 G14–G17 把例外 S-1、S-2、S-3 收回 `.yix` / `.yss`，清理 S-9。
截图 61 张里 59 张与 P0 基线逐字节一致（两张 `*-updates.png` 是构建信息）。`view/components/shell/mod.zig` 只剩 `NavScroll`、
`Viewport`、`SearchField`（S-4 / S-5，待 G18 / G19）。

| 例外 | 写法 | 提交 |
|---|---|---|
| S-1 “保存更改” | `W.Button variant={.primary} baseStyle={footer_geometry} look={S.save_fill}`；`save_fill` 每个状态写 `background` + `gradient`（token `zw-primary*`，不可用是 `zw-island-rest`） | `657e8874` |
| S-2 页头帮助 | `<W.Tooltip text={help(vm)} openDelayMs={450} parts={.{ .content = m.ids.help_content }}><W.Button testId={m.ids.help} … look={S.glass_icon} /></W.Tooltip>`；几何、颜色、投影都在 `glass_icon` | `5c2db63e` |
| S-3 行组件 / computed | 行直接写在 `{for}` 里（`S.NavRow.of(.{ .selected = item.selected, .locked = item.locked })`）；后退 / 前进 `look={S.GlassNavButton.of(.{ .dim = backDim(vm) })}`（几何、按下、`:disabled`、35% 维度） | `b7df4a0a` |
| S-9 宿主改写标题色 | 删除（`.yix` 的 `window_title` 与旧 `titleText` 都是 token，自行重放） | `de17126b` |

**像素之外的证明**：截图基线里“保存更改”多数不可用、页头按钮多为静止态。语义测试
`settings window controls paint the same in every pointer state for both implementations`（`settings_window_semantic_tests.zig`）
对帮助、后退、前进、“保存更改”逐个走“静止 → 悬停 → 按下 → 按下移出 → 移出松开”，覆盖不可用 / 可用 / 保存中 / 保存失败，
记录根节点的底色（变化后第一帧与 150ms 渐变结束后）、渐变、墨色、文字墨色、不透明度、描边、投影、尺寸、禁用，
三个外观族 + 浅色材质 60 + 深色材质 25，旧实现与 `.yix` 逐值相同。另把同一套记录在改动前后的 `.yix` 上各跑一遍（临时打印，未入库）：
S-1 前后、S-3 前后各 175 条记录逐字节相同。

### 新坑（实测）

20. **look 里每个状态要同时写 `background` 与 `gradient`**。上游示例只写 `gradient`；底色仍是色调的（`button-primary-bg` /
    `button-primary-hover` / `disabled-bg`），而不可用填充 surface_2 带材质透明度，渐变是半透明叠在底色上的，底色不同像素就不同。
    原 inline 层两样都写，look 照写即可；`:disabled` 里写了底色，色调的 disabled-bg 就被压过（look 自己的 `:disabled` 在色调之上）。
21. **色调已给的墨色不必再写**：primary 色调的 `button-primary-fg` / `:disabled` 的 `fg-disabled` 与旧 baseStyle 的
    `actionForeground(action_accent)` / `fg_3` 逐值相同（旧 baseStyle 的墨色本来就被色调的 `:disabled` 压过）；色调没有禁用不透明度，
    `opacity: 1` 只需写在 base。旧 `hoverStyle` / `pressedStyle` 的 `action_accent` 一直被 inline 层压着，没有对应物是对的；
    150ms 底色渐变新旧都有（第一帧的值也相同）。
22. **`{for}` 里内联的行，派生值不要读“会让列表本身换掉”的信号**：概览行内联后 `subTitle(vm, row.sub)` 读 `vm.pageIndex()`，
    切换分类时它先于列表协调、以新分类配旧序号重算而越界（行组件形态下没出现）。改成行数据自带分类（`OverviewItem.page`），
    行的标题 / 图标 / id 只读行变量。登记 G21。
23. **ZeroWork 的焦点填充（`zenit_ext/focus_fill`）按下即生效**，失焦时恢复聚焦那一刻看到的底色（按下前是悬停色）。`.yix` 页头在保存
    前后不重挂（旧实现整页重建），所以先按过后退再进入保存中，后退会留着悬停色——改动前后都如此，不是本包引入。测试里在状态切换前
    清焦点并调整了录制顺序；是否修 focus_fill 另议。**已处理（native-buttons）**：删除 `focus_fill` 扩展，焦点改用 zenit 原生焦点环（键盘焦点描边，指针焦点不改底色），`bg_focus` / `border_focus` / `focus_ring` 不再由主题改写；失焦停在悬停色的问题随之消失（回归测试 `chrome_policy_tests.zig`）。
24. 无窗口测试里 Tooltip 只把指针移开不关闭，要 `cx.handlePointerLeave()`（旧实现同样）。

### 对上游写法示例的修正

- `SaveButton`：`:disabled { gradient: …; color: …; opacity: 1; }` 不够——每个状态都要写 `background`（第 20 条）；`color` 与
  `:disabled` 里的 `opacity` 不需要（第 21 条）。几何用 `.yix` 里的 `ui.StyleOverride` 常量作 `baseStyle`（`footer_geometry`，与“撤销更改”共用），
  没有试过把 YSS 样式直接给 `baseStyle`。
- `HelpButton` / 后退前进：几何也可以写进 look（look 并入的位置与 baseStyle 相同、排在其后），所以 `glass_icon` /
  `GlassNavButton` 连几何一起写在 `.yss`，页头不再引用 `settings_styles`。后退 / 前进的 35% 不能写成 `:disabled`
  （保存中只禁用、不变淡），是配方维度 `dim`。
- `parts={.{ .content = m.ids.help_content }}`：常量声明可以直接用，不必写字面量。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G21 | `{for}` 内联行的派生值先于列表协调重算 | `vm.page: Signal(u8)`；`items(vm) = table[vm.page.get()]`（各页长度不同，key = 序号）；`{for (items(vm)) \|row\| <text>{name(vm, row.i)}</text>}`，`name` 读 `names[vm.page.get()][i]`。把 `page` 换到项更少的一页：将被删除的那一行的 `name` memo 先以新 `page` + 旧 `row.i` 重算 → 越界 panic。同样的表达式写在行组件 `<Row vm={vm} i={row.i} />` 里不出现 | 列表源与行内派生同时变脏时，先协调列表（按所有权自上而下），被删除的行不再重算；至少在文档里写明“行内派生不要读驱动列表的信号” |
| G22 | 窗口空闲后的第一次过渡没有中间帧 | 原生 `W.Switch`（无下游覆盖）：窗口空闲 1 秒以上、指针未移动时直接点击，`translate-x` 过渡第一帧即到终点；点击前约 60ms 移动指针则平滑。复现：`node e2e/switch_initial_state_native.ts <bin> <out> light --strict-idle` 失败（点击后第一次采样已在终点）。用户可感知：空闲一会儿再点开关，开关不滑动而是直接跳过去 | 过渡起点应锚定到事件之后的第一帧，而不是空闲前的时钟；**已由上游修复**（zenit `92e8f8e1`，vendor @88bd7a0c）：根因是事件期间的命中刷新在停表的帧时钟上 tick 后没有恢复事件时钟。下游 e2e 的空闲点击断言已改为默认必过 |
| G23 | ~~多个 `Cx` 之间样式状态疑似串扰~~ → **ZeroWork 缺陷，已修复**（非 zenit） | 同一测试进程按特定顺序运行（`test-ui -Dui-test-filter=socks`）时，原生 `W.Switch`（`.sm`）从开切到关后轨道背景停在“开”的颜色；单独运行正常 | **已判定并修复（下游）**：二分得最小触发 = 前序用例 `socks_background_ui_tests` “attached list … theme roles” 第一行 `theme.select(.dark)`（结束时也恢复成 `.dark`，进程级主题从此停在 dark）。根因在 ZeroWork 的保留式换肤遍历 `repaint(node, previous)`（`quick_connect_styles.repaint` 等 9 处）：它对子树每个节点都 `setBackground`，多数是原色重写；对带 style host 的 zenit 视图节点，这一写进入 host 的 inline 层并永久压过配方，于是 `View.mount` 末尾的 `retheme()` 把开关轨道当时的填充钉死，之后 `checked` 翻转只能移动滑块。取证：失败时轨道 `styleHostStateForTest(track).inline_decl.background` 非空、过渡槽位 `active=false`、两个时钟一致、`cx.tokens` 与 `app_theme` 一致。单独跑能过只是因为 mount 时的 Cx 默认 token 不等于 light/sauber 调色板任何角色；真实应用先 `setTheme` 再 mount，任意主题都会钉死（转发配置弹窗的两个开关）。修复：新增 `app_theme.setRetainedBackground`，对有 style host 的节点只做真正的重映射、跳过原色重写，9 处遍历统一改用它；恢复断言并新增回归用例（三套主题 × 是否换调色板）。后续：配方色恰好等于旧调色板角色色时仍会被重映射——组件 token 回到 zenit 默认后被系统性命中，见 G26（原生组件一律不写） |

---

## P3 收回上游缺口（F-set-handles，vendor @ed8e829e）

基线：`revamp/set-handles`（自 `8129ccbf` 切出）。用上游补的 G18–G21 把例外 S-4、S-5、S-6 收回 `.yix` / view-model，S-8 缩到只剩
旧正文（S-7）的桥接，S-10 评估后不切 `chrome = .custom`。截图 61 张里 59 张与 P0 基线逐字节一致（两张 `*-updates.png` 是构建信息），
每个代码提交后都跑过。`view/components/shell/` 整个删除。

| 例外 | 写法 | 提交 |
|---|---|---|
| S-4 搜索框 | `<W.Input testId={m.ids.search} value={searchField(vm)} placeholder="搜索设置" leadingIconAsset={ui.icons.search} size={.sm} style={S.search} onChange={…searchFor…} parts={.{ .input_container = .{ .style = .{ S.search_pill, searchRadius(vm) } } }} />`；view-model 新增 `search_field` 信号 | `4a170ae9` |
| S-5 滚动容器 | `<W.ScrollArea … testId={m.ids.viewport} style={S.viewport} scrollY={pageScroll(vm)} onScrollYChange={\|y\| send(vm, m.Intent.scrolledTo(y))} parts={.{ .content = .{ .style = S.panes } }}>`（概览 / 正文两个分支各一份）；导航列表 `style={S.nav_scroll}` + `parts` 内容样式 `S.nav_list` | `d1eac26c` |
| S-6 整窗按键与焦点 | 窗口根 `onKeyDownCapture={\|e\| windowKey(vm, e)} focusRequest={focusRequest(vm)}`，内容列 `focusRestore`；`ViewModel.windowKey(key, modifiers) bool` + `Gate.window_keys` + `Intent.window` | `28a30d33` |
| G21 绕法 | `OverviewItem` 去掉 `page`，行内派生读 `vm.pageIndex()` | `0f586202` |
| S-10 自检 | runner V-11 在 inset 下断言卡片不可聚焦、拖动带逐字可拖点 = 设计意图（4693，此前 0） | `3d69435d` |

### G18 – G21 实测

- **G18（受控输入）成立**：`onChange` 里同步写信号，编辑原地落地（光标、选区不变）；导航清空 = 外部写入，不回调 `onChange`；
  组字中清空推迟到组字结束（取消后应用、提交则用户输入经 `onChange` 再次成为搜索词）；主题发布后填充随 token 变。
  另外实测到旧搜索框的一个隐性行为（见新坑 25）。
- **G19（滚动偏移绑定）成立**：重挂后视口回到所绑槽的偏移；写入夹取并回报；滚动只写偏移信号，不牵动其它选择器。
  `scrollY={函数调用}` 会被包成 `derive(f32)`，传不了 `*Signal(f32)`（新坑 26）。
- **G20（捕获阶段按键与声明式焦点）成立**：无焦点时按键落到窗口内容根，模板根的捕获处理器照常收到（上游提醒的“模板根必须是窗口内容根”
  在生产 `aux_window` 路径成立：运行时把 mount 返回的根设为 `Cx.content_root`；无窗口测试要手工设）。卡片不再需要可聚焦。
  `focusRestore` 在旧正文的输入框上要宿主先 `abandonFocus` 才能带回选区（新坑 27）。
- **G21（结构先于内容）成立**：只派发、不重挂地切到行更少的分类，被删的行不再以新分类求值，留下的行跟随。

### 新坑（实测）

25. **旧搜索框的圆角在第一次聚焦后变成 4**：挂载后 `setStyle(.corner_radius, 14)` 写在节点上，输入框第一次获得焦点时边框状态重放，
    圆角回到 sm 尺寸的 4，此后一直是 4（背景与透明描边走内联层，保留）。截图 `*-search.png`、`*-dirty-overview.png` 依赖它。
    收回时按原样保留：view-model `search_focused`（搜索槽 `onEvent` 看冒泡上来的 `.focus`）+ `styleBy` 给 14 或不给。
    是否改回设计稿的 14 应单独判定（会改上述 4 张基线）。
26. **`scrollY={f(vm)}` 拿不到双向绑定**：属性表达式是函数调用就被包成 `derive(f32)`，返回 `*Signal(f32)` 编译失败。改成只读值 +
    `onScrollYChange`（split）：view-model 在回调里**同步**写该槽的信号与存档；槽在 `remountContent` / `attach` 时定下，
    派生只读这一个槽，避免导航后、重挂前旧视口去读新槽。
27. **旧正文的输入框被重挂时，焦点走“节点被摘”的路径**（`invalidateReferencesTo` → `clearFocus`），框架读不到选区：旧正文改写了
    输入框节点的事件上下文，Input 自己的 cleanup 认不出它、不会 `abandonFocus`。宿主在重挂前调 `Page.releaseFocus`：输入框
    `abandonFocus`（框架记下目标与选区，新页挂好后 `focusRestore` 放回），其它正文控件仍主动 blur（blur 要在页面回调释放前送达）。
    S-7 的面板正文改成 `.yix` 后这一步可以删。
28. **`{for}` 的锚点**：列表容器的 `children` 里有 `display: none` 的锚点节点，按子节点数数行会多算。
29. **view-model 不能引用 `ui.view`**（`check-arch` 的 `view_model-reactive-subset`）：`KeyPress` / `FocusRequest` 留在模板里转换，
    view-model 收 `key` / `modifiers`、返回是否接下；焦点请求用同形的 `FocusAsk`。
30. **测试夹具要像运行时一样设 `cx.content_root`**，否则无焦点时按键落到夹具根，捕获处理器收不到。

### 对上游写法示例的修正

- 搜索框：`testId` 写在 `W.Input` 元素上（旧 `settings.search` 在 `InputResult.node`，即 Input 根），不是 `parts.input_container`；
  `S.searchPill` 只写 `background: bg-active; border-color: transparent;`，圆角见新坑 25。`placeholder_color` 不必写（默认 `fg_secondary` = 旧 `fg_2`）。
  搜索词另设 `search_field` 信号而不直接用投影 `query`：关口拒绝（MCP 编辑中）时旧搜索框仍保留打出的字，`query` 会把字退回。
- 滚动区：`scrollY` 只能是只读值（新坑 26）；内容样式按概览 / 正文二选一，`parts` 里不能写读 view-model 的配方维度（G24），用两个分支。
- 整窗按键：`onKeyDown={|e| vm.windowEscape(e)}` 的冒泡写法**没有采用**——Escape 仍在捕获阶段，与旧实现同序（窗口先于内层控件，
  原地编辑 / 弹层 / 提示由宿主按层收起）。`focusId="settings.search" autoFocus` 没有采用：旧窗口打开时不聚焦搜索框。
  `focusRestore` 写在不随纪元重挂的内容列上（`settings.content` 本身随纪元重挂），没有新增 test_id。
- 留作后续的 `focusReturn`、焦点读侧信号：设置窗口用不到（数据清理回焦用 `focusRequest`；Escape 分层仍由宿主判断）。
  搜索框圆角的“聚焦过”用了搜索槽 `onEvent` 看冒泡的 `.focus` 事件——如果有读侧信号可以替代，但只为复刻一个旧缺陷，不建议为它加能力。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G24 | `parts` 里的表达式不按属性表达式处理 | `<W.Input parts={.{ .input_container = .{ .style = S.R.of(.{ .on = flag(vm) }) } }} />` → `expected type '*Vm', found 'Source(*Vm)'`（`parts` 里的 `vm` 是挂载期的源，配方维度值与函数实参都不提升）；同样的 `S.R.of(…)` 写在元素自己的 `style` 上可以 | `parts` 里的样式值与 `style` 属性同样处理（维度值引用源时生成 memo）。绕法：函数收 `anytype` 取出信号交给 `styleBy`（`nav.yix` 的 `searchRadius`），或按分支写两份元素 **已由上游修复**（zenit `6c25655d`，vendor @7652f819；`state=` / `a11y=` 同修）。样式位置上的整段调用仍不提升，下游写成带维度的配方；下游两处绕法已由 H-shell 去掉：`nav.yix` 的 `searchRadius`（连同“首次聚焦后圆角 14→4”的照搬行为与 `search_focused` 信号）删除，内容页“概览 / 正文”合成一个 `W.ScrollArea`（内容样式用带维度的配方 `S.PageBody`） |

### V-6 / V-11 结论更新

- **V-6**：`.yix` 切换分类后焦点不再落到卡片，而是无焦点（按键落到窗口根，快捷键照常）；同一页重挂（草稿变化）时焦点与选区回到
  同一字段（`focusRestore`，组件测试与 runner `typing-stays-focused` 场景）；其余场景（字段文本经草稿保留、组字中切换丢弃预编辑、
  搜索框清空、搜索框跨结果重挂保持焦点）不变。真实输入法仍**未实证**。
- **V-11**：卡片不可聚焦后，生产 `.custom_inset` 拖动带的逐字判定恢复为 4693 个可拖点（与“排除卡片后的设计意图”相同，此前 0）。
  仍是 runner 自检与源码推断，**真实拖动未实证**——手工清单第 2 步现在期望 `inset` 窗口也能拖。生产窗口**不切** `chrome = .custom`
  （原因见例外表 S-10）；上面“建议切”的改动清单保留，待用户判定。

---

## 面板正文 Yix 化的机制与写法（F-set-panes-A，3e 第一批）

基线：`revamp/set-panes-a`（自 `bf8baf8b` 切出）。改写：通知、SSH 与网络、文件传输、数据与日志四个分类。
代码：`model/pane_fields.zig`（字段表）、`view/panes/{registry,notify,ssh,transfer,data}.yix`、`view/components/rows.yix`、
`view/styles.yss`（“面板正文”一节）；测试 `tests/settings_panes_tests.zig`、`tests/settings_rows_tests.zig`（夹具 `rows_fixture.yix`）。

### 登记表：怎么加一个分类

1. **model**：在 `model/pane_fields.zig` 写该分类的 `struct`——每行一个条目（`toggle` / `input` / `select` / `info` / `action`，
   或手写 `Row`），再写面板（`pane(id, 分类下标, 标题, 说明, 摘要函数?, 搜索词, 行)`），最后把面板登记进 `pages[分类]`。
   文案、test_id、`focusId`、单位、“说明写在标签下”、搜索词都在条目里；面板的 `rows` 必须与视图里的行同序同集合
   （view-model 用它做搜索过滤、“最后一行”与“分类有没有命中”）。
2. **view**：新建 `view/panes/<分类>.yix`，根是 `<box testId="settings.<分类>" style={S.category_panes}>`，里面按顺序写
   `<R.Pane vm={vm} pane={…}>` 与行组件；然后在 `view/panes/registry.yix` 的 `Block` 的 `{if}` 链里加一行。
3. 不用动宿主：`Frame.hasLegacy()` 为假时，草稿变化不再重挂内容页（见下“纪元重挂”）。

### 行组件 API（`components/rows.yix` 文件头是权威版本）

```
Pane(vm: *m.ViewModel, pane: *const m.PaneSpec, children: View)
ToggleRow(vm, pane, row: m.Row)                 InputRow(vm, pane, row: m.Row)
SelectRow(vm, pane, row: m.Row, options: []const W.SelectOption)
DirectoryRow(vm, pane, row: m.Row)              InfoRow(vm, pane, row: m.Row)
ActionRow(vm, pane, row: m.Row, icon: ?ui.SvgAsset)
```

控件全部原生（`W.Switch` / `W.Input` / `W.Select` / `W.Button` / `W.Tooltip`，目录按钮是 `W.Pressable` + `.yss` 配方），
不覆盖几何、字体、颜色。test_id 落点：行根 `settings.row.<key>`；开关、按钮在控件根；输入框 `parts.input_container`，选择框
`parts.trigger`；校验提示 `settings.error.<key>`；“?” `settings.help.<key>`（提示面板 `.tooltip`）；标签下的说明
`settings.help.content.<key>`；面板 `<id>`、`<id>.header`、`<id>.summary`。

### 横切行为的写法

| 行为 | 写法 |
|---|---|
| 值 / 校验 / 禁用 | 选择器 `vm.fieldText(row)`（原文或格式化值，两份缓冲交替）、`vm.fieldProblem(row)`、`vm.fieldInvalid(row)`、`vm.fieldDisabled(row)`（保存中或 `Controller.fieldApplicable` 为假：自动重连 → 次数 → 间隔 / 缓存）；都读 `revision`，编辑一个字段只让读它的选择器重算 |
| 编辑 | 开关 / 选择 `Intent.editValue`，输入框 `Intent.editText`（`onChange` 与 `onSubmit`）；解析失败记成字段问题，不再发 `Effect.failed`（与旧 `Field.edit` 相同） |
| 选择器弹层 | 原生 `W.Select`（下拉开合是 view-model 的 `popup`）；“自定义 TERM 声明…”（`__custom`）是 `rows.CustomSelectRow` 里选择框下方的原生 `W.Popover` + 受控 `W.Input`（草稿归 view-model），下载目录发 `Intent.choose` → `Effect.pick_directory`（宿主直接弹系统目录面板）——set-modals 起不再经宿主的 `picker_scope`（S-13） |
| 字段帮助 | 原生 `W.Tooltip`（上方、450ms、宽 292）包原生 ghost 图标按钮；开合是 view-model 的 `popup`（悬停经 `onOpenChange`、点击与键盘聚焦经 `onClick` / `onFocus` 打开） |
| Escape 分层 | 窗口根捕获 Escape → 宿主 `windowEscape`：材质预览 → 旧正文 → **`vm.consumeEscape()`**（先收起 `popup`，再撤回正在编辑的输入框原文并清焦点；输入框经行根的 `onFocus` / `onBlur` 登记 `editing`） → 提供方 → 选择器 → 关窗 |
| 定位校验问题 | `locate_problem` 导航到子页面后 `requestFocus(row.ids.focus)`（`focus:field:settings.field.<key>`，输入框的 `focusId`） |
| 焦点恢复 | 输入框有同名 `focusId`；内容页重挂前 `Page.releaseFocus` 对 `.yix` 输入框同样 `abandonFocus`，`focusRestore` 放回（含选区） |
| 搜索 | 规则同旧：面板按搜索词匹配面板词，行再按标题 / 说明 / 标签 / key / 帮助匹配；搜索词命中分类名时整类不过滤。行与面板用 `visible`（不建 / 不建的区别：旧实现不创建未命中的行，新实现创建后隐藏） |
| 未保存标记 | 面板里旧实现就没有逐字段的“未保存”标记（只有 Save Bar），本包不加 |
| 宿主状态 | `HostStatus` 新增 `authorization_help`、`clear_logs` / `clear_all`（`ActionState`）、`data_paths`；选择器 `permission*`、`actionEnabled` / `actionReason`、`infoValue` / `infoShown` |

### 纪元重挂现在的触发条件

`SettingsHost.rebuildAll`（`.yix`）先 `vm.sync()`，然后 **`yixContentCurrent()` 为真时不换纪元**：内容页已挂好、页上没有旧正文
（`Frame.hasLegacy()`）、不是概览、位置与搜索词（哈希）都与挂载时相同。于是在四个已改写分类里，草稿变化、恢复默认、主题发布、
宿主状态变化（授权、清理进行中）、选择器提交都只重新投影。仍整页重挂的：导航（分类 / 子页面 / 历史）、搜索词变化、概览页、
任何含旧正文的页（包括与旧分类混排的搜索结果）。

### `.legacy` 外壳

`.legacy`（`settings_view_mode`）仍可编译、语义测试的 legacy 半边照跑：它的 `mountPage` 仍挂旧面板文件，所以
`panes/settings_{notify,ssh,transfer,data}.zig` 本包**没有删除**（S-15）。删除它们要么让 `.legacy` 也挂 `.yix` 面板（需要给 `mountPage`
造一个 view-model，等于重做 `.yix` 外壳的接线），要么提前删掉 `.legacy` 开关与只测旧面板的组件测试；建议后者，放进 3f 或下一个面板包。

### 新坑（实测）

31. **Builder 组件的普通值字段收不到行参数**：`<W.Input appendText={unit(row)} />` 在行组件里编译失败（`expected ?[]const u8, found Source([]const u8)`），
    同样的常量可以。登记 G25（S-14）。`W.Button` 的 `iconAsset` 是 `?SvgAsset`，参数要声明成可选（`icon: ?ui.SvgAsset`）才收得下。
32. **G24 在 `parts` 的 id 上也出现**：`parts={.{ .content = helpTipId(row) }}` 报 `expected Row, found Source(Row)`；绕法：组件体里
    `const tip = computed(helpTipId(row));` 再 `parts={.{ .content = tip }}`。`a11y={.{ .label = f(row) }}` 同理要先 `computed`。
33. **`W.Pressable` 用 `style`（配方），不是 `look`**；样式里写 `:disabled` 而元素没有 `state.disabled` 时编译期报错——用配方维度（`flag off`）。
34. **Tooltip 的“暖启动”按墙钟算**：上一个提示关闭后很快再悬停就不等延迟。比较两种实现的延迟时，挂载耗时不同会让结果不同
    （`.yix` 面板挂得更快，搜索后第二次悬停落在暖启动窗口里）；测试里先清 `cx.tooltip_state.last_close`。
35. **旧分类的搜索命中要挂载后才知道**：`LegacyBody` 挂载时写 view-model 的 `legacy_hits` 信号，`Block` 的 `visible` 与“没有匹配的设置”读它
    （挂载期写信号，读者随后跟随一次）。
36. **原生 `W.Switch` 的 `label` 会画在开关旁边**（不只是无障碍名）；行里已有标签时不传 `label`，名字经 `a11y`（`computed` 出整份 `?A11yProps`：`role = .switch_role`、`checked`、`disabled` 一起给，组件根的 `a11y` 是整体替换）。
37. **搜索规则里面板说明也参与行匹配**：搜“保活”会显示“连接”面板的全部行（说明“连接保活、超时与终端类型”命中），旧实现相同。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G25 | builder 组件（`W.Input` 等经 `reactive.props.coerce` 的 Props）普通值字段不收源 | `fn Row(u: []const u8) View { return <W.Input appendText={u} />; }` → `props.zig:197: expected type '?[]const u8', found 'Source([]const u8)'`；`appendText="秒"` 可以 | 普通值字段收到 `Source` 时挂载期 `peek`（与 `testId` / `focusId` 一致），或把 `append_text` 等展示性字段改成 `Source` **已由上游修复**（zenit `7a86d8e2`，vendor @d1419340；普通值字段收到同类型的源时在挂载时读一次、之后不跟随，类型不符报编译错；`a11y={f(row)}` 整体表达式也已提升。S-14 待下游收回） |
| G26 | 没有公开途径判断节点的某个样式字段由哪一层声明（inline 层 / 组件配方） | ZeroWork 的保留式换肤遍历按颜色把旧调色板角色重映射到新调色板；zenit 默认开关“开”色 `#4F5ED9` 等于 light 调色板的 accent，light 下挂载转发配置再切 `forest`，开关轨道被当成 ZeroWork 的 accent 填充写进 inline 层（轨道变错色、不再跟随 `checked`）。要只重映射“ZeroWork 自己写进 inline 层的背景”，只能读 `ui.view.styleHostStateForTest(node).inline_decl`（测试接口）。下游先按 `component_name` 名单跳过原生组件（`app_theme.nativeOwned`），容器内部节点与插槽内容仍分不开 | 公开只读查询，例如 `ui.view.inlineDeclares(node: *Node, comptime field: StyleField) bool`，或 `ui.view.inlineBackground(node: *Node) ?Color`（无样式宿主时返回 null / 读节点直写值）；或者给组件内部节点一个“属于哪个组件实例”的公开查询（如 `ui.view.ownerComponent(node) ?*ComponentInstance` 区分模板节点与插槽内容） |
| G30 | ~~原生控件的宽度不能随窗口尺寸跟随~~ → **用户判定不需要，关闭，不补上游**（紧凑窗口保持原生 180；168 是旧实现的像素微调，e2e 断言已改为 180） | 旧面板在视口宽 ≤ 900 时把输入框 / 选择框 / 目录按钮 / 路径值从 180 收到 `control_width_compact` 168（`settings_controls.Page.afterLayout`，逐帧 `setStyleInline`）。`.yix`：`W.Select` 的 `width` 是普通值 `f32`，`<W.Select width={vm.controlWidth()} />` 按 G25 的语义只在挂载时读一次，窗口缩放后不变；Yss 也没有按窗口 / 容器宽度的条件写法。复现：`node e2e/settings_other_v3_native.ts`（`compact field w 180 != 168`，先 `nav.toSub` 再 `resizeWindow(860,480)`） | (1) `W.Select` / `W.Input` 的 `width` 改为 `Source(f32)`（或 `Source(?f32)`）并随源重排；或 (2) Yss 增加按窗口宽度的条件（断点），控件宽度经 `look` / 原生尺寸变体表达。补上前两份脚本的紧凑宽度断言失败（F-set-panes-A-fix 未绕） |

## 快捷键行的编辑交互（F-set-panes-B，3e 第二批；人工验收反馈第 7 条）

旧实现：每个动作一行，键帽是手搓的盒子塞进一个被覆盖外观的 ghost `W.Button`；点击后宿主弹出录制对话框（`keybinding_picker`，
原生 `W.Modal` 但几何与配色全被覆盖），在对话框里按键 → “使用快捷键”确认才写进设置草稿；冲突与 Control / Tab 组合一律**拒绝**
（“已用于“复制”，请重新录制。” / “请使用 Command 组合，Control 与 Tab 保留给远端。”），只能换一个组合重录；“解除绑定”永远不可用
（运行时的 `Map` 没有“未绑定”值）。问题：行看起来不像能改（键帽是静态标签、没有编辑提示），改一次要过一个弹窗三步，冲突时用户不知道该怎么办。

新交互：**行内录制**，全部原生组件（`W.Pressable` 键帽区、`W.Kbd` 键帽（set-adopt 起；原为 `W.Tag`，G32）、`W.Tooltip`、`W.Button`、`W.Badge`）。

| 状态 | 进入 | 呈现 | 可用操作 |
|---|---|---|---|
| 静止 | 默认 | 动作名；右侧键帽区（每个修饰键 / 主键一个 outline `W.Tag`）+ 一支淡色铅笔图标；当前值 ≠ 已保存值时动作名旁一个“未保存” `W.Badge`；当前值 ≠ 默认值时行尾一个“恢复默认”图标按钮 | 点击键帽区、Tab 到键帽区后 Enter / Space → 录制；“恢复默认” |
| 悬停 / 聚焦 | 指针移入 / 键盘聚焦键帽区 | 键帽区底色变 `bg-hover`（键盘聚焦另有原生焦点环）；原生 Tooltip “点击修改快捷键” | 同静止 |
| 录制中 | 点击 / Enter / Space | 键帽区换成 accent 描边的录制态：已按住的修饰键（accent `W.Tag`）+ “按下新快捷键… Esc 取消”；Tooltip 换成同样的提示 | 按下含主键的组合 → 判定；Esc → 静止（草稿不变）；Tab → 静止并照常移焦；点别的行 → 那一行开始录制；整窗 ⌘W / ⌘, 不触发（作为组合交给这一行），整窗 Escape 只取消录制 |
| 无效 | 录制中按下不合规的组合 | 键帽区显示按下的组合（danger `W.Tag`），行下一行红字说明原因：缺 ⌘ / Control 保留给远端 / Tab 保留给远端 / 按键不可用 | 继续录制（直接再按一次）；Esc / Tab → 静止 |
| 冲突 | 录制中按下的组合已被其它动作占用；或“恢复默认”时默认值已被占用 | 键帽区显示按下的组合（warning `W.Tag`），行下一行：“⌘J 已用于“AI 运维助手”。交换后“AI 运维助手”改用 ⌘T。” + 原生按钮【交换】（secondary）【取消】（ghost） | 【交换】一步解决：本动作取新组合、对方取本动作原来的组合（运行时没有“未绑定”，所以不是“清除对方”）；【取消】/ Esc → 静止；键帽区仍有焦点时可直接再按一个组合 |
| 已修改 | 录制成功 / 交换 / 恢复默认 | 键帽区显示新组合；“未保存”标记出现；与默认值不同则出现“恢复默认” | 同静止；整类的“恢复默认…”仍在 Save Bar |

- 状态是 view-model 的一个信号（`key_edit`：哪一行、哪个阶段、按住的修饰键、按下的组合、冲突对象、原因），只有一行能处在非静止态；
  每行的选择器读它，按信号局部更新（不重挂行）。按键判定、冲突、交换、键帽文字是 `model/keybinding_edit.zig` 的纯函数。
- 草稿：录制成功 / 交换 / 单行恢复默认都经 `dispatch` → `Controller.editKeys`（整张表一次事务，同旧 `recordedKeysChanged`），
  不再有“确认”这一步——草稿本来就要 Save Bar 保存才落盘，弹窗里的“使用快捷键”是多余的一层。
- 按键：键帽区（`W.Pressable`）的 `onKeyDown` 在组件根的捕获槽，先于 Pressable 自己的 Enter / Space 激活；录制中接下所有键（Tab 除外，
  Tab 照常移焦并结束录制）。整窗的 `onKeyDownCapture` 在录制中 / 无效态放行（`ViewModel.windowKey`），冲突态失焦后 Escape 经整窗分层
  （`consumeEscape`）收起冲突提示。
- 固定行（最近使用的页签 ⌃⇥、采纳补全 →）：键帽区禁用，Tooltip “此快捷键不可修改”，动作名旁的锁图标说明“保留给应用，不可修改”（同旧）。
- 不做：解除绑定（运行时不支持，旧对话框里也是永远禁用的按钮）；录制中显示“已按住的修饰键”依赖平台送来修饰键的按下事件。

### 实现记录（F-set-panes-B）

- **行内录制做成了**（没有退回 `W.Modal`）：键帽区是原生 `W.Pressable`，组件元素上的 `onKeyDown` 落在它根节点的捕获槽，先于 Pressable
  自己的 Enter / Space 激活，录制中 `e.stop()` 接下按键；整窗 `onKeyDownCapture` 在录制中不触发整窗命令。
- 加一个分类仍按“登记表”三步：`pane_fields.keys` / `pane_fields.updates`、`panes/keys.yix` / `panes/updates.yix`、`registry.yix` 两行；
  宿主只为更新器状态加了 `HostStatus.update` 与每帧指纹比较（`SettingsHost.pollUpdateStatus`）。
- 行组件新增（`components/rows.yix`，已有组件未改）：`KeybindingRow(vm, pane, row)`、`ValueRow(vm, pane, row, value: Text)`、
  `LinkRow(vm, pane, row, icon)`。样式在 `panes/keys.yss`、`panes/updates.yss`（不碰外壳的 `styles.yss`）。

### 新坑（实测）

38. **打开着的原生 Tooltip 先吃掉 Escape**：`Cx.handleKeyDown` 在分发到树之前，Escape 先交给 `tooltip_state.dismiss` 收起提示并返回
    （`cx_input.zig`）。键帽区获得焦点时原生 Tooltip 会打开，录制中第一次 Esc 只关提示、不取消录制。绕法：键帽区的提示受控
    （`open = popup 且这一行静止`），非静止时不显示；行内已有“按下新快捷键… Esc 取消”。
39. **原生 `W.Tag` 的文字为空时卸下文字节点**（`{if (label.len != 0) <text>}`）：键帽数随录制变化时就成了结构变化（组件测试里同页节点
    指针不再全部保留）。绕法：不用的键帽位隐藏并给占位字（`ViewModel.keyCap`）。**set-adopt 起不再适用**：键帽改原生 `W.Kbd`（`keys` 跟随
    `ViewModel.keyCaps`），键帽是 Kbd 自己的按键列表，占位字与 `keyCap` / `keyCapShown` 删除。
40. **宿主元素的 `onFocus` / `onBlur` 只在它自己获得 / 失去焦点时触发**（`applyAttrs` 直接写 `on_focus` / `on_blur`，`FocusManager`
    只对旧 / 新焦点节点本身调用），不是 focus-within；组件元素（`W.Pressable` 等）上又不能写 `onFocus` / `onBlur`。所以“键帽区失焦即结束录制”
    写不出来（G31）。绕法：Tab 由键帽区的 `onKeyDown` 结束录制，Escape 由整窗捕获取消录制，点别的行 / 导航 / 搜索都会复位。
    **set-adopt（G31 上游已补）**：键帽区 `W.Pressable` 写 `onBlurWithin` 结束录制（Tab、指针点到别处都算），`keyDown` 里的 Tab 绕法删除；
    整窗捕获的 Escape 取消保留作兜底（静默失焦不触发 `onBlurWithin`）。固定动作的锁提示改用外层盒子的 `onFocusWithin` / `onBlurWithin`。
    `InputRow` 等其它行的同类问题（行根盒子的 `onFocus` / `onBlur`）在共享的 `components/rows.yix` 里，不归本包，留给后续包。
    **顺带发现（源码结论，未实证）**：第一批 `InputRow` 把 `onFocus` / `onBlur` 写在行根盒子上，焦点实际落在 `W.Input` 内部节点，行根很可能收不到，
    “Escape 撤回正在编辑的输入框”的登记（`Intent.fieldFocused`）在真实窗口里也许从未发生；它的组件测试是直接 dispatch `fieldFocused` 的。建议主 agent 安排实证。

## 外壳原生玻璃化（H-shell：人工验收反馈 1、3、5、11）

### zenit 原生玻璃组件清单（vendor 当前版本）与 Yix 可用性

| 组件 | 用途（源码语义） | Yix 形态 |
|---|---|---|
| `W.GlassBox` | 通用 liquid glass 面板（`NSGlassEffectView`）：`shape`（capsule / circle / rounded / concentric）、`cornerRadius`、`padding`、`bodyGap`、`glassStyle`（regular / clear / identity）、`tintColor`、`interactive` / `pressFeedback`、`material`（含 `.blur_only`）、`scrollEdge`（需 `*ScrollState`） | **有**：builder 带 `viewMount`，children 进 body，`parts` 可取 `.body` |
| `W.GlassGroup` / `W.GlassShape` | `GlassEffectContainer`：成员融合、morph、`union_id`、容器级 `scroll_edge` | 无：成员靠 `GlassShape(...).mountIn(group, …)` 命令式挂载 |
| `W.GlassToolbar`（`glass_toolbar`） | macOS 26 `NSToolbar`：同组按钮共用一颗 36pt 玻璃胶囊（`.buttons`）、分段（`.segmented`）、`flexible_space`；另有 `titlebarEdge`（标题栏下内容洗向窗口底色的实测渐变） | 无：`mount` 返回 `GlassToolbarResult`（没有 `viewParts`）；组是静态切片，`ToolbarButton` 没有禁用态 / 响应式字段（G27）；`titlebarEdge` 是普通函数（G28） |
| `W.GlassNavigationBar` / `W.GlassTabBar` / `W.GlassBottomToolbar` / `W.GlassButton`（`glass_bars`） | iOS 26 导航栏 / 标签栏 / 底部工具栏 / 玻璃按钮（默认 iOS idiom） | 无：`mount` 返回 `BarResult`（没有 `viewParts`） |
| `W.GlassSlider` / `W.GlassToggle`（`glass_controls`） | 原生滑块 / 开关的玻璃旋钮 | 无：`mount` 返回 Result 结构 |
| `background_extension.BackgroundExtension` | SwiftUI `backgroundExtensionEffect()`：内容镜像延伸 + 模糊 | 无：普通函数，收 `Builder` 回调 |

### znote 的对应写法（只读参照，`~/work/fe/znote`）

znote 不用 zenit 的玻璃组件，全部是直接写 `StyleExt.glass` 的手搓材质：`src/shell/chrome/glass.zig:13` `progressiveBlurEdge`（页头 76pt 渐进磨砂：`backdrop_blur = 180` + `blur_gradient` 顶部 30% 满强度后渐出，用在 `src/shell/home.zig:285`、`src/shell/chrome/compose.zig:91`）、`:36` `islandCard`（侧栏大岛：半透明白 + 描边 + 双层阴影 + `backdrop_blur 32`）、`:58` `pillCard`（页头后退 / 缩放 / 动作胶囊，`src/shell/chrome/header.zig:54/119/150`）。zenit 的 storybook `GlassChrome`（`vendor/zenit/examples/storybook/stories.zig` 约 L4964）注明它取代的正是这套手搓 chrome：控件放 `GlassToolbar` 胶囊组，标题栏与内容的分界交给 `titlebarEdge`。按“只用原生、不模仿”的规则，ZeroWork 不搬 znote 的 `StyleExt.glass` 写法，改用这两样原生能力的 Yix 可达形态。

### 设置外壳最终用法

- Settings Nav：`<W.GlassBox width={216} fill={.height} cornerRadius={14} padding={…10/8…} bodyGap={12} style={S.nav_glass}>`（set-adopt：G29 上游已补，原 `height={0}` + 根样式拉伸的绕法去掉）。
- 页头后退 / 前进：一颗 `<W.GlassToolbarGroup>` 工具栏胶囊里的两个 `<W.GlassToolbarButton>`（历史里没有这一步时用按钮自己的禁用态）；帮助：`<W.Tooltip>` 的触发器是只有一个 `W.GlassToolbarButton` 的胶囊（set-adopt：G27 上游已补，S-17 收回；原“`W.GlassBox` 胶囊 + ghost `W.Button`”近似写法删除）。工具栏按钮与 macOS 原生一样不进 Tab 顺序。
- 页头渐变：页头与原生 `<W.TitlebarEdge />` 绝对定位在内容列顶部，视口从页头下方开始（不伸到页头底下：页头在标题栏拖动带里，下面不能有滚动区 / 控件的命中目标），渐变延伸到视口上缘、内容滚近页头时被洗淡。set-adopt（G28 上游已补，S-16 收回）：删除 `view/titlebar_edge.zig` 适配；视口加 `scrollEdge={.{ .edge = .top, .style = .soft, .height = 28, .fade_width = 28 }}`——视口自己的 `.blur_only` 玻璃带（UIScrollEdgeEffect），静止时看不见，内容往上滚过视口上缘时在页头正下方渐进磨砂。评估：这就是反馈 3 要的“滚到页头下面才出现的渐进磨砂”在 S-10 约束下能做到的形态——带子只能贴在视口上缘（视口不能伸进标题栏拖动带），所以磨砂出现在页头下沿而不是页头底下；高 28 取标题栏渐变伸进视口的那一段（76 − 48），磨砂与洗白落在同一条带上（取值，不是实测；上游注明 macOS 26.4 工具栏下没有可观测的 scroll edge 效果，这是 zenit 的 UIScrollEdgeEffect 模型）。
- 回弹：内容视口与导航列表的 `W.ScrollArea` 用默认 RubberBand。
- 设置窗口的窗口背景 / 材质配置没有改：窗面仍是不透明的 `zw-window-surface`，玻璃取到的背景就是同窗口里已画的内容（`capture_source` 默认 `.window_backdrop`）。

### 新坑（实测）

38. **`W.GlassBox` 撑不满父容器的高度**：`height` 只有 px / fit；不给 `height` 时内部的 content / body 是 fit，根上写 `style={height: fill}` 只会让玻璃面变高，正文仍按内容收缩（导航底部的“本机说明”贴在列表下面）。给了 `height`（任意 px）时 content / body 才是 `grow`，再由根 `style` 把高度改成 `fill`（G29）。
39. **`W.Input` 的 `input_container` 不是可聚焦节点**：断言聚焦外观时取子树里第一个可聚焦节点。
40. **页头不能“浮”在滚动区之上**：第一版让视口占满整列、页头浮在上面，结果页头所在的标题栏拖动带底下是 `W.ScrollArea` 的命中目标——生产 `.custom_inset` 的拖动判定（`legacyWindowControlAt` 把指针 / 滚动目标都算控件）让页头空白处不再能拖窗口，preview runner 的 V-11 自检（`.custom` + windowRegion）报“拖动区内有交互控件”4002 点。改为视口从页头下方开始（`styles.yss` 的 `viewport` 上边距 48），渐变仍从列顶画到视口上缘；代价是内容不会真正滚到页头底下，只在接近页头时被洗淡。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G27 | `W.GlassToolbar` 没有 Yix 形态，按钮没有禁用态 — **上游已补、已采用**（set-adopt，`4ccc0ed9`） | `<W.GlassToolbar groups={&groups} />` → `GlassToolbarResult` 没有 `viewParts`（按 `view.zig` 的 `mountComponentWith` 静态判断会编译报错，未实际编译）；`ToolbarButton` 只有 `icon` / `width` / `on_click` / `label` / `test_id`，`groups` 是静态切片，后退 / 前进的“历史里没有这一步时禁用”无法表达 | `GlassToolbarResult.viewParts()`（root）；`ToolbarButton` 增加 `disabled: Source(bool)`（实测 macOS 26 禁用项的墨色与背板）与响应式 `icon` / `label`；或提供 Yix 组件 `<W.GlassToolbarGroup>` 收 `<W.GlassToolbarButton … />` 子元素。补上后把 `header.yix` 的“GlassBox 胶囊 + ghost Button”换成它 |
| G28 | 标题栏边缘渐变 / scroll-edge 在 Yix 里够不到 — **上游已补、已采用**（set-adopt，`4dc5b27b`、`9badf52d`） | `titlebarEdge(cx, props)` 是普通函数（没有 builder / `viewMount`）；`<W.GlassBox scrollEdge={.{ .scroll = ? }}>` 需要同级 `W.ScrollArea` 的 `*ScrollState`，Yix 的 `ref` 只在挂载后可用、组件参数在挂载时定型，取不到 | 提供 `W.TitlebarEdge` 组件（换主题时重取明暗）；`W.ScrollArea` 增加 `scrollEdge: ?{ edge, style(.soft/.hard), height }` 参数，由它自己挂一层绑定自身 `ScrollState` 的 `.blur_only` 玻璃（UIScrollEdgeEffect，znote 页头那种“滚到下面才出现的渐进磨砂”）。补上后删 `view/titlebar_edge.zig`（S-16） |
| G29 | `W.GlassBox` 不能按父容器拉伸高度 — **上游已补、已采用**（set-adopt，`eded65de`） | `<W.GlassBox style={S.fill}>…<W.ScrollArea style={S.flex1}/><box/>…</W.GlassBox>`：根变高，content / body 仍是 fit，`flex: 1` 的子项拿不到剩余空间 | `height` / `width` 支持 `fill`（或 `Sizing`），content / body 随根 `grow`；补上后去掉 `nav.yix` 的 `height={0}` |
| G31 | 没有焦点进出子树（focus-within）的事件；组件元素上不能写 `onFocus` / `onBlur` — **上游已补、已采用**（set-adopt，`3695ab95`） | `<box onBlur={f()}><W.Pressable … /></box>`：Tab / 点击让焦点离开 Pressable，`f` 不被调用；`<W.Pressable onBlur={f()} />` 编译期是未知属性 | 宿主元素加 `onFocusWithin` / `onBlurWithin`（或让 `onFocus` / `onBlur` 按 DOM 的 `focusin` / `focusout` 冒泡），并把它们列入组件元素的根节点保留名 |
| G32 | 没有键帽组件（Keycap / Kbd） — **上游已补、已采用**（set-adopt，`cbf6e797`） | 快捷键行要显示 “⌘ ⇧ K”：只有 `W.Tag`（outline、sm）最接近；`NotificationHintKeycap` 只在通知提示里用，不是独立组件 | 新增 `W.Kbd(keys: []const []const u8, size, tone)`：每键一个键帽、等宽最小宽度、浮雕底边、可选强调 / 危险色调（录制态 / 无效态） |
| G33 | `W.Button` 的图标只能放在文字前 — **上游已补、已采用**（set-adopt，`183a06ae`） | 链接按钮“GitHub / version-next / ZeroWork ↗”要求外链图标在文字后；`iconAsset` 只有前置 | `iconPosition: enum { leading, trailing }`（`link` 变体外链图标常用后置） |

## 保存状态机（H-save：人工验收反馈 4）

代码：`model/save_flow.zig`（纯函数：作用域表、离开判定、恢复默认判定、Save Bar 投影、确认流程的转移函数，带单元测试）、
`model/view_model.zig`（喂事件、执行动作、选择器）、`model/settings_controller.zig` `resetScope`、`view/save_bar.yix`（Save Bar、
“恢复默认…”行、确认对话框）、宿主 `host/settings_host.zig`（`Effect.saved` / `.save_failed` → 原生 Toast；`.legacy` 外壳跟随 `Effect.prompt`）。

### 作用域

作用域 = 右侧当前显示的子页（没有子页的分类 = 整个分类页）。`save_flow.fieldsAt(Where)` 按编译期表返回字段集（`schema.FieldSet`）：

| 位置 | 字段 |
|---|---|
| 有子页的分类的某个子页 | 目录 `catalog.Subpage.keys` 列出的字段（编译期核对：每个 schema 字段恰好落在一个子页面） |
| 没有子页的分类（快捷键 / 协议插件 / 关于与更新） | 该分类的全部字段；复合字段：快捷键表 → 快捷键，插件偏好 → 协议插件 |
| AI 辅助 › 服务提供方 / 技能与 MCP | 提供方表连同 `ai.default_provider`（增删提供方会改它；它同时也在“行为与权限”）/ 扩展 |
| 概览页、数据与日志 › 位置与凭据 / 导出与清理 | 空（没有可编辑字段：不显示“恢复默认…”） |
| 搜索结果 | 全部字段（搜索跨分类；进入 / 改变搜索不用确认，清空搜索回到原页时按原页的作用域判定） |
| 嵌在主窗口的旧页面（`drill_down = false`） | 整个分类 |

“有变化才可点”的解读：保存 / 撤销按“相对已保存的值有变化”（草稿有改动）；**恢复默认按“相对默认值有变化”**
（`differsFromDefaults`：作用域里有字段与 `config.resetDefaults()` 不同）。恢复默认只改作用域里的字段（`Controller.resetScope`：
`schema.merge(草稿, 默认值, 作用域)`，清掉这些字段的原文与问题，作用域含背景图片时放弃正在准备的背景），仍是草稿，保存后生效、可撤销。

不变量：草稿里的改动只属于当前作用域——用户发起的导航（分类、概览行、子页面、后退 / 前进、清空搜索）在 `dirty_fields`
有目标作用域之外的字段时先确认（`leaveNeedsConfirm`），关窗在有改动时先确认。跳到校验问题（`locate_problem`）与确认后的导航不再确认。

### 状态

由 Controller 派生（不另存）：`clean` / `dirty_valid` / `dirty_invalid`（校验无效，含背景图片未准备好）/ `saving` / `save_failed`。
view-model 另存 `Flow { prompt: none|close|leave|reset, after_save: none|close|leave }` 与挂起的导航 `pending_leave`。

Save Bar 投影（`save_flow.bar`）：

| 状态 | 出现 | 文字（墨色） | 保存 | 撤销 |
|---|---|---|---|---|
| clean | 否 | — | — | — |
| dirty_valid | 是 | 未保存 | 可点（外观 worker 忙 / 字体有问题时不可点） | 可点（worker 忙时不可点） |
| dirty_invalid | 是 | 有设置需要修正（危险） | 可点：不写盘，定位问题并发“无法保存设置”通知 | 可点 |
| saving | 是 | 正在保存…（按钮转圈） | 不可点 | 不可点 |
| save_failed | 是 | 保存失败，草稿已保留（危险） | 可点 | 可点 |

需要用户处理的状态的可见反馈：校验无效 → Save Bar 危险墨色 + 字段行内提示 + 保存时定位；保存失败 → Save Bar 危险墨色 + 原生错误 Toast
（原因）+ 原有的“偏好设置”操作失败通知；背景图片准备失败 → 外观页“图片准备失败 · 草稿保留”的行内状态（草稿干净时不再借 Save Bar 常驻显示）；
背景图片仍在准备 → 校验无效（“背景图片正在准备，请稍后保存。”）。保存成功 → Save Bar 消失 + 原生 Toast“设置已保存”（“保存关闭”不弹，窗口随即关闭）。

### 事件与转移（`save_flow.step`，表中“动作”由 view-model 执行）

| 当前 | 事件 | 下一个 | 动作 |
|---|---|---|---|
| prompt=none | ask_close（关窗且有改动，宿主 `toggle` → `askClose`） | close | 弹出 |
| prompt=none | ask_leave（导航会离开作用域外改动） | leave | 弹出；导航挂起 |
| prompt=none | ask_reset（点“恢复默认…”，仅 differsFromDefaults） | reset | 弹出 |
| prompt≠none | 任何 ask_* | 不变 | 忽略（模态） |
| close | 保存（“保存关闭” / 无效时“返回修正”） | after_save=close | 保存（close_after）；无效则定位问题 |
| close | 放弃 | none | 放弃草稿并关窗 |
| close / reset | 取消（按钮、Escape、标题栏关闭） | none | 收起；宿主撤回挂起的原生关窗 |
| leave | 保存 | after_save=leave | 保存 |
| leave | 放弃 | none | 宿主放弃草稿（`revert`）；仍有改动（宿主拒绝）则留下，否则执行挂起的导航 |
| leave | 继续编辑 | none | 收起；导航作废，搜索框回到当前搜索词 |
| reset | 恢复默认 | none | `resetScope`（关口 `Gate.reset`：外观 worker / 保存中拒绝） |
| 任意 | 与对话框不符的选择 | 不变 | 忽略 |
| after_save=leave / close | saved(ok) | after_save=none | 执行挂起的导航 / 关窗；不关窗时弹“设置已保存” |
| 任意 | saved(err) | after_save=none | 错误 Toast；Save Bar“保存失败” |
| 任意 | save_blocked（关口拒绝、草稿干净、校验无效） | after_save=none | 无 |

外部配置变化（另一窗口、状态栏换主题 `immediateTheme`、重新打开窗口）：沿用原规则——草稿干净时基于最新已存配置重建（`discardLatest`），
有改动时保留草稿，保存时只把改动的字段合并到最新配置（`schema.merge`），不产生作用域外的改动。

### 视图

- Save Bar：右下浮动的原生 `W.GlassBox` 胶囊（`shape=.capsule`，内边距 / 间距是组件参数），里面状态文字 + 原生 `W.Button` ghost“撤销”、primary“保存”（`size=.sm`，无覆盖）。删除 `save_fill`、`FooterLink`、`footer_ghost`、对勾与 `zw-primary-hover*` / `zw-primary-pressed*` token（`zw-primary` / `zw-primary-to` 仍给关于页的应用图标用）。
- “恢复默认…”：正文最后一行右对齐的原生 ghost `W.Button`（sm），作用域没有可编辑字段时不显示；不在 Save Bar 里（干净但非默认的页面也点得到）。
- 确认对话框：窗口级 `<W.Modal>`，默认遮罩、默认面板、默认标题栏，正文是说明 + 提示 + 原生按钮行（继续编辑 / 放弃更改 / 保存或保存关闭或返回修正；恢复默认确认是取消 / 恢复默认）。set-adopt（G36 / G37 上游已补）：常驻挂载、`open` 跟随 view-model，收起时有原生退出动画（退出途中正文沿用最后打开的那一种，`ViewModel.dialogKind`）；关着的对话框不在 Tab 顺序里；“继续编辑 / 取消”的 `autoFocus` 保留（有意把焦点给安全选项，每次打开都聚焦），不再是绕法。
- Toast：set-adopt（G38 上游已补，S-19 收回）起是窗口模板里的原生 `<W.NotificationHost post=… position={.bottom_center} />`（挂在确认对话框同一个锚点盒子里）；请求来自 view-model 的 `toast` 信号（`ToastAsk{ seq, text, tone }`，模板换成 `W.NotificationPost`，hint 的 `mark` = success / error），宿主不再持有 Notifier。

### 人工验收看到的“弹窗时搜索框有焦点描边、面板半透明”

- 面板半透明：旧宿主的命令式 `W.Modal` 传了 `.background = app_theme.current().overlay`（遮罩色，半透明）当面板底色，且旧截图在原生 scale-fade 动画中途取帧。现在面板是 Modal 默认底色（组件测试断言与无覆盖的参照 Modal 相同、alpha 255）；采集脚本等动画结束再截图。
- 搜索框焦点：原生 Modal 的 `auto_focus` 在 `pushScope` 时从当时的焦点顺序里取第一个，首次打开（刚挂载、焦点顺序尚未重收集）时对话框里的按钮还不在顺序里，焦点留在原处（搜索框）——缺口 G37。现在由“继续编辑”的 `autoFocus` 声明式聚焦，组件测试与 `e2e/h_save_capture.ts`（`focused_in_confirmation`）实证焦点在对话框里。

### 新坑（实测）

41. **portal 组件不能当组件根**：`<W.Modal>` 挂到窗口浮层根，`viewParts().root` 为 null，直接作为组件根渲染报 `ViewEmptyRoot`；外面包一个不占位的 `<box>`（`confirm_anchor`）。
42. **关着的 `W.Modal` 仍在 Tab 顺序里**：关闭时只把遮罩缩成 0×0、不可命中，`focusStep` 只跳过 `display:none`；常驻挂载时从无焦点按 Tab 会落进看不见的对话框（缺口 G36）。改为 `{if}` 只在打开时挂载，代价是收起没有原生退出动画。
43. **窗口根的 `focusRequest` 只在自己的子树里找目标**：portal 出去的对话框按钮收不到；对话框里的初始焦点用按钮自己的 `autoFocus`。
44. **Tab 离开 `W.Input` 后它的聚焦描边不撤**（lead 复核 `review/light-b-dirty.png` 时发现：“KeepAlive 间隔”与“连接超时”同时带描边）。查明：
    采集脚本改完 KeepAlive 后按 Tab 进下一个框，前一个框的 `:focus` 描边留着；用指针点到别的框则正常撤掉。不是“已修改字段”的标记
    （设置面板没有逐字段的未保存标记，见上文“横切行为的写法”），也不是 ZeroWork 的 `zenit_ext/focus_fill`（它只画底色、不碰描边；
    关掉主题发布、不装 focus_fill 的纯 zenit 环境同样复现）。归 zenit，缺口 G39；本包不在下游绕。
### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G34 | `W.Modal` 的遮罩颜色在挂载时固定（lead 预留编号，H-save 代登记） | `vendor/zenit/src/ui/components/modal/mod.zig` 的 `.barrier = .{ .color = p.overlay_color orelse t.tokens.color.overlay }` 在挂载时取一次主题值；Modal 常驻挂载后换主题，遮罩仍是旧主题的颜色 | 遮罩跟随主题 token（按 `overlay` token 解析，主题发布时重取）。**状态：上游修复中** |
| G36 | 关闭状态的 `W.Modal` 内容仍在 Tab 顺序里 — **上游已补、已采用**（set-adopt，`56bb2e4e`、`9336978f`） | 常驻挂载 `<W.Modal open={false}>…<W.Button/></W.Modal>`，焦点清空后按 Tab：焦点落到对话框里的按钮（`settings_window_yix_tests` 的 S-6 用例实测） | 关闭时给遮罩 `display:none`（或在 `focusStep` 里跳过不可命中 / 0 尺寸的祖先），打开时恢复 |
| G37 | `W.Modal` 首次打开时 `auto_focus` 落空 — **上游已补、已采用**（set-adopt，`56bb2e4e`、`9336978f`） | 挂载即打开（或命令式挂载后立刻 `open.set(true)`）：`pushScope` 时 `scopedFocusOrder()` 为空，焦点留在原处（人工验收截图：搜索框带描边） | `auto_focus` 推迟到下一次焦点顺序收集之后（或在 `pushScope` 时先对遮罩子树做一次 `replaceDefaultOrderSubtree`） |
| G38 | `W.Notifier` 没有 Yix 形态 — **上游已补、已采用**（set-adopt，`85923922`） | 只有命令式 `Notifier.init(scope, cx, options)` + `hint(...)`；视图层没法声明“这个窗口有一个通知栈”，宿主要持有指针 | 提供 `<W.Notifier ref=… />` 或由窗口级服务自动提供（`cx.notifier()`），view-model 发 Effect、宿主只调 `hint` |
| G39 | Tab 移走焦点后，`W.Input` 的 `:focus` 描边不撤（指针点走正常） | 无 ZeroWork 主题 / focus_fill 的 headless 环境（`kit.headless(.{ .publish_theme = false })`）：挂两个 `ui.widgets.Input(.{ .width = 180 })`，点第一个（描边由 `#3f3f46` 变 `#8c98ee`），`cx.handleKeyDown(.tab, .{})`：焦点到第二个，两个的描边都是 `#8c98ee`；改用 `handleClick` 点第二个则第一个回到 `#3f3f46`。生产窗口实证：`ZeroWork-evidence/h-save/review/light-b-dirty.png` | 键盘焦点遍历（`FocusManager.focusStep` → `setFocus`）与指针改焦点走同一套 blur 通知，让 ControlShell 的 `:focus` 状态在 Tab 离开时撤回；补上后 `review/*-b-dirty.png` 只剩当前框带描边 |

## 外观与主题面板（F-set-appearance，3e：S-7 拆出外观、修 S-11）

基线：`revamp/set-appearance`（自 `f7eaaa23` 切出）。代码：`model/pane_fields.zig` 的 `appearance`、`view/panes/appearance.{yix,yss}`、
`view/material_preview_bar.{yix,yss}`（主窗口的全窗口材质预览条）、`view/components/material_preview.zig`（行内材质预览的适配，S-18）；
view-model 的“外观与主题”一节；宿主 `SettingsHost.appearanceStatus` / `appearanceEffect`；测试 `tests/settings_appearance_tests.zig`（夹具 `appearance_fixture.yix`）。

### 机制（与前两批相同的登记表，外加三样）

- **宿主状态单独一个端口**：`Ports.appearance → AppearanceStatus`（主题库指针、已保存的主题 / 背景、字体校验结果与单元格宽度、背景选择框路径、
  运行中轮播的当前图片、材质预览是否打开、缩略图纹理 id / 尺寸、worker 忙）。不并进 `HostStatus`：主题卡片等选择器读得频繁，不必每次都算数据页路径与更新器状态。
  宿主在这些状态变化的地方本来就 `pending_rebuild` → `rebuildAll` → `vm.sync()`；内容页没有旧正文，`yixContentCurrent` 为真，只重新投影、不换纪元。
- **动作**：`Intent.appearance(AppearanceIntent)`。草稿编辑（开关、选择、滑块、输入框原文 / 提交、主题卡片、对齐、移除背景、自定义字体）由 view-model 直接写 Controller，
  随后发 `Effect.appearance(.changed)`（宿主做旧 `draft_values_changed` 的事：重新校验字体、按需准备背景、刷新材质预览）；
  资源操作（选择背景、删除主题、全窗口预览、恢复已保存背景、提交时校验字体）发 `Effect.appearance(…)`，宿主转给原来的 `appearanceCommand`。
  导入主题复用 `Command.import_theme`。worker 忙或保存中时 view-model 拒绝编辑（同旧 `appearance_view.disabled`）。
- **数据色**：主题卡片的色板、ANSI 色板、终端预览、工作区缩略预览画的是**那个主题自己的颜色**（数据，不是界面 token），写在 `appearance.yss` 的
  `styleBy` / `tintBy` 函数里（按 `ThemeCard` / `PreviewText` / `MiniPreview` 取色）；界面色仍只用 token。
- **原生组件的数据选项**：字体族（系统已安装的等宽字体，窗口 scope 内枚举一次，`FontList`）与字重（按字体族缓存 CoreText 查询）的选项由 view-model 给数据，
  视图在 `.yix` 顶层的两份交替缓冲里转成 `W.SelectOption`（view-model 不能引用 `ui.widgets`）；主题卡片的 test_id（`settings.theme.<id>`，主题 id 是数据）
  的字符串归窗口 scope（`ThemeIds`）。挂载期定型的原生参数（`W.Select` 的 `leadingIcon`、`W.Slider` 的范围）随数据变化时，用只有一行、key 随数据变的 `{for}` 整行重挂。

### 行为对照（与旧 `appearance_view` 的差异，均为有意）

| 项 | 旧 | 新 |
|---|---|---|
| 草稿变化 | 宿主整页重建（S-11：开关没有滑动） | 按信号局部更新；同一个开关原地滑动（组件测试 `expectLocalToggle` + `switch_initial_state_native.ts` 改回 `expectSlide`） |
| 主题卡片的选中标记 | 选中时名称旁一个对勾图标（自绘） | 名称旁一个原生 `W.Radio`（选中实心、未选空心）；卡片本身是 `W.Pressable`（自定义内容：色板 + 名称） |
| 应用图标 | `W.RadioGroup` 被改成行高 40、去按钮底、手涂圆点颜色 | 原生 `W.RadioGroup` 默认外观 |
| 图片对齐 | `W.Popover` 里 9 个手搓 ghost 按钮（圆点图标）；触发器是手搓按钮 | `W.Popover` 里 3 × 3 的 `W.Pressable` + 原生 `W.Radio`；触发器是原生 secondary `W.Button`，尾随下拉箭头 `iconPosition={.trailing}`（set-adopt，G33 上游已补） |
| 轮播方式 / 切换间隔 / 图片适配 / 字重 | `W.Popover` + 手搓菜单行 | 原生 `W.Select`（选项 test_id `settings.option.<key>.<值>`、面板 `settings.chooser.<key>` 保留） |
| 字体族 | `W.Select`，触发器 / 面板经 `fieldControl` / `tuneSelect` / `panel_style` 覆盖 | 原生 `W.Select` 默认外观（280 宽、可搜索、虚拟列表、来源图标） |
| 输入框 | `styleInput` + `tuneInput` + `S.field` 覆盖、`paintInputValidation` | 原生 `W.Input`（`invalid` / `appendText` / `width` 参数），行下校验提示 |
| 字段“?” | `controls.inlineHint`（Tooltip 覆盖背景 / 字色 / 字号、按钮 `base_style`） | 原生 `W.Tooltip` + 原生 ghost xs 图标按钮（同 `rows.yix`） |
| 行间分隔线 | `watchDividers` 逐帧补 | `S.SettingRow` 的发丝线（设计 `w3r3t`，同其它面板） |
| 背景成对字段 | after-layout 钩子按宽度切换并排 / 堆叠（≥ 560 并排） | 一直并排（两列各占一半）：没有按容器宽度的条件写法（G30 已判定不补） |
| 主题条初始位置 | after-layout 后把选中卡片的**右缘**对齐视口右缘 | 挂载时 `scrollX` 取选中卡片的**左缘**（框架夹到 [0, 最大]）；之后照旧由用户滚动。右缘对齐写不出来：要视口宽度，`W.ScrollArea` 的 `scrollX` 只收偏移、没有“把某段对齐到末端”的声明式写法（`scrollRectIntoViewX(… .end)` 要 `*ScrollState`，Yix 拿不到），登记 G42 |
| 行内材质预览 / 材质预览条 | 旧命令式 | 预览图层是宿主的材质图层（S-18 适配）；预览条改 `.yix`（每次重建按当时状态给参数） |
| 删除当前主题的提示 | 标签与原因相同时不挂 Tooltip | 总是挂原生 Tooltip（文字相同） |
| 主题库（筛选 / 收藏 / 网格）、“主题预览”卡 | 旧文件里的死代码：`appearance_view.zig`（基线 `f7eaaa23`）的 `ThemeGrid`（L450，筛选 L466–478、搜索 L480、收藏 L565）与 `dismissedTheme`（L381，“重新打开主题库” L392、“主题预览”卡 L394–395）在全仓库没有任何调用点；唯一入口 `mountContent`（L199–208，经 `panes/settings.zig:2` ← `settings_content_view.zig:430`）只挂 `themeSection`（L213，主题条 + 当前主题行 + ANSI）等六个面板。`.open_library` / `.close_library` / `.favorite` 三种 `Click` 只在这两个函数里创建，所以 `theme_library.open` 在 V3 外壳下只有测试会写（`settings_content_tests.zig:131/748`），宿主只读它（`settings_host.zig:751` 关闭时清零、`:1604/:1733` 记滚动槽） | 不移植（任何外壳路径都挂不到）。**set-adopt：删除**（用户 2026-11-13 判定：以代码功能为准，产品里没有入口就当不存在；设计稿的主题库不实现），见下文“set-adopt” |

### 新坑（实测）

45. **`Controller.editKey` 也写原文**（`raw_fields[i].input = "{d}"`）：不能按“有没有原文”决定输入框显示原文还是格式化值，否则滑块拖动后透明度显示
    `42.300003`、Escape 后显示 `0`。外观页用 view-model 的 `typed_field`（正在逐字编辑的那个字段）决定：只有它显示原文，滑块 / 选择 / 有效提交 / Escape 之后显示格式化值
    （同旧 `Field.text` 只在编辑时跟随输入）。`InputRow`（前两批）没有滑块，不受影响。
46. **`W.Slider` 的 `test_id` 参数在 Yix 里够不到**：组件元素上的 `testId` 是根节点保留名，Slider 自己也声明了 `test_id` 参数 → 编译期报
    “the component also declares a parameter .test_id …”。绕法：`settings.slider.<key>` 写在包住滑块的盒子上（矩形与滑块区域相同）。登记 G35。
    **set-adopt（G35 上游已补）**：`testId` 直接写在 `W.Slider` 上（落在轨道上，同旧命令式外观页），绕法删除。
47. **view-model 不能产出 `W.SelectOption` / `W.MenuItem`**（`view_model-reactive-subset` 禁 `ui.widgets`），而选项又是数据（已安装字体、当前字体支持的字重）：
    视图在 `.yix` 顶层用两份交替的缓冲转换（Select 按内容 / 地址判断换选项）。右键菜单只有有限几种文案，写成静态表按状态选。
48. **`{for}` 行里的 test_id 是挂载期取值的字符串，主题 id 是数据**：字符串要有稳定的存储（`ThemeIds`，归窗口 scope）；`{for}` 默认 key 是 `item.id`，
    `ThemeCard.id` 指向同一份存储，选中变化只写行数据、卡片原地更新。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G35 | `W.Slider` 的 `test_id`（写在轨道上）在 Yix 里设不了 — **上游已补、已采用**（set-adopt，`3d72fa5e`） | `<W.Slider testId="x" … />` → `view.zig:2678` 编译期报 Slider 也声明了 `.test_id`；不写 `testId` 又没有别的名字能传它 | Slider 的参数改名（如 `trackTestId`），或像 Input 的 `parts.input_container` 一样经 `parts={.{ .track = id }}` 暴露轨道节点 |
| G42 | `W.ScrollArea` 没有声明式的“把某一段滚到视口末端 / 可见”的写法 | 主题条要在挂载后让选中卡片的右缘对齐视口右缘：`scrollX` 只收偏移（需要视口宽度，挂载时不知道），`scroll_area.scrollRectIntoViewX(state, content, left, width, .end)` 要 `*ScrollState`，Yix 的组件元素拿不到 | `W.ScrollArea` 增加 `revealX={.{ .left, .width, .align = .end }}`（布局后执行一次、之后不再跟随），或子元素上的 `scrollIntoView` 属性 |

## 协议插件两级导航（F-set-plugins：人工验收反馈第 10 条前半）

代码：`model/plugin_pane.zig`（分组、搜索、文案，纯函数）、`model/view_model.zig`“协议插件”一节（`plugin*` 选择器、`DrillItem`）、
`view/panes/plugins.{yix,yss}`、`view/components/rows.yix` 的 `DrillRow`；测试 `tests/plugin_settings_yix_tests.zig`。

### 动态子页（对现有两级导航的最小扩展）

现有机制的子页是静态的（`catalog.Subpage` + `settings_history.subpage_counts`）。插件是运行时数据，扩展如下：

- `settings_history.isDynamic(page)`（只有协议插件，第 5 类）：`validSubpage` 对它只做上限检查（`dynamic_subpage_capacity = 64`），
  静态表里它的子页数仍是 0（没有概览；`catalog` 编译期核对）。
- `Location{ .page = 5 }` 是列表页，`Location{ .page = 5, .sub = i }` 是注册表里第 `i` 个插件的详情页；`Controller.show` 按注册表裁决
  （下标越界回到列表页），历史、后退 / 前进、清空搜索回原页都沿用原有代码路径。
- 页头标题：详情页是插件名（`titleOf` 新分支）。滚动：同其它分类（每个分类一个槽，换位置时清零）。
- 搜索：列表页的过滤规则同旧 `entryMatches`（名称、来源、“协议 插件”；命中分类名时整类不过滤）；`pageShownInResults` 对第 5 类改看
  `pluginHits`（不再靠旧正文挂载时报告）。点搜索结果里的行 = `Intent.openAt(详情页)`，清空搜索。
- 保存作用域（`save_flow.fieldsAt`）：列表页为空（没有“恢复默认…”）；详情页是复合字段“插件偏好”。复合字段不分插件——
  在 A 的详情页改了偏好再去 B 的详情页不会确认，“恢复默认…”会把所有插件的偏好一起恢复；没有偏好字段的插件详情页不显示“恢复默认…”
  （`resetShown` 新分支）。要按插件细分需要把插件偏好拆成每插件一个字段集，未做（见报告）。
- 编辑：`Intent.plugin_preference`（`setPluginPreference(插件下标, 字段下标, 值)`）→ `Controller.setPluginPreference`；被拒绝的原因记在
  view-model，行下提示（同旧实现显示错误名）。

### `DrillRow`（两级导航的列表行，通用）

```
DrillRow(vm: *m.ViewModel, item: m.DrillItem)
m.DrillItem = { key, row_id, title_id, summary_id, trail_id, icon (ui.icons 名), title, summary, trail, last, target: m.Intent }
```

原生 `W.Pressable` 根（`row_id`），30 方块图标底、标题 13 / 摘要 11.5（gap 1）、尾注 11.5（空串不显示）、chevron；行内 padding [9, 0]、gap 8，
与图标底 gap 12；除 `last` 外底部发丝线。点击发 `target`，保存中不可点。AI 辅助 › 服务提供方等列表页可直接复用
（`rows.yix` 里已有 `LinkRow`（链接按钮行），所以名字用 `DrillRow`）。

### 新坑（实测）

49. **组件参数的字段不能存进组件体的局部常量**：`const field = item.field;` 报 “reactive reads in component locals require computed(...)”；
    改成把字段拆成独立参数（`PrefRow(vm, index, field, last)`）。

## 原生浮层不透明（H-opaque-popups）

现象：开着背景图片 / 全局透明度时，设置窗口里原生 `W.Select` 的下拉、主窗口里原生 `W.Menu`（窗格“…”）、原生 Modal 面板都半透明，
底下的开关、输入框、壁纸格子透出来（`ZeroWork-evidence/h-opaque-popups/before/*-material-*.png`）。默认配置（T=0）下 `bg_primary` 恰好是 255，所以平时看不出来。

原因与修法：`widgetTokensFrom` 把 zenit 的语义表面 token 直接映射成带材质 alpha 的调色板表面（`bg_primary = c.surface_1` 等），
而 zenit 原生组件把 `bg_primary / bg_secondary / bg_tertiary` 当不透明表面来画浮层与控件底。现在这五个语义表面
（`bg_base / bg_primary / bg_secondary / bg_tertiary / bg_inset`）发布为同一 RGB 的 `withAlpha(255)`；ZeroWork 自己“透出壁纸”的表面
一直直接读 `current().surface_* / overlay`、`layerBackground` 或 `zw_island_*`，不受影响。逐项清点见 `NATIVE_AUDIT.md` 清单 2.3.1。
回归测试：`theme_layer_tests.zig` 的 “native floating panels stay opaque at every material transparency”（全部内置调色板 × T∈{0,30,70,100} × 有无背景图，
Popover / Menu / Select 面板 / Tooltip / Modal 面板底色 alpha 255，同时断言主窗口材质表面仍按 T 透明）。
修前截图在基线 32dc9d9f 上采过（`ZeroWork-evidence/h-opaque-popups/before/`）；修后截图按 2026-11-13 的“批末统一回归”规则未采，由批末回归用 `e2e/h_opaque_capture.ts`（明 / 暗 × 默认 / `--material`）补采。

### 新坑（实测）

50. **语义 token 不是“应用表面”**：zenit 的 `bg_primary` 同时是浮层面板底、控件底、Card 底；下游若想让某块应用表面透出材质，要用自己的
    `zw_*` 或直接读 `current()`，不能借语义 token 传 alpha——否则所有原生浮层一起变透明，而且 T=0 时看不出来（`bg_secondary` 在 T=0 也只有 alpha 71）。
    验收这类问题必须开着背景图片和非零透明度截图（`e2e/h_opaque_capture.ts --material`）。

## 命令帮助卡（h-helpcard：NATIVE_AUDIT B4，用户判定 D-5）

代码：`features/terminal/view/command_help.{yix,yss}`（视图）、`app/main_window.zig`（建 `help_open` 信号、`ui.view.render` 挂到终端区）、
`features/shell/host/nav_host.zig`（`help_open: ?*ui.Signal(bool)`：`@help` 置真、Esc 分支与“有模态打开”判断读它）；
测试 `features/terminal/tests/command_help_tests.zig`（test-ui，过滤串 `command help`）。旧 `view/command_help_view.zig` 删除，
门面导出名 `command_help_view` 保留、改指向生成的 `_command_help.yix.zig`。

- 外观：原生 `W.Modal` 默认（遮罩 = 主题 overlay token，面板 = `bg-primary` 与默认圆角 / 描边 / 阴影，原生标题栏与关闭按钮），宽 580（旧卡片宽度）、
  其余参数全默认。正文：指令目录在原生 `W.ScrollArea` 里（17 行 × 28，面板约 588 高，默认 600 上限内不滚动），下面两行脚注与一个原生“关闭”按钮。
- 内容与触发条件不变：标题“❓ 内置指令速查”、目录（`builtin_dispatch.helpEntries()`）、两行脚注；只在 `@help` 没有终端输出目标时打开。
  旧卡片头部的“Esc 关闭”提示由原生关闭按钮与脚注“关闭”按钮取代。
- 测试证据：遮罩 / 面板外观与同宽无覆盖的参照 Modal 逐项相同；Esc、标题栏关闭、脚注关闭、点遮罩都关闭且焦点回到打开前的节点（终端替身）。

### 真实窗口取证（批末）

这条路径在当前产品里触发不到：`main_window` 给 `command_bridge` 设了 `on_command_from`，终端里输入的内置指令都经
`onLocalCommandFrom`，它总是先设 `workspace.command_output` 再调 `onLocalCommand`，所以 `.help` 总走“写进终端输出”的分支；
AI 的 `host.run_builtin` 也直接写终端文档；`actions.zig` 的 `open_command_help` / `command.help` 在 `src/` 里没有按名字处理它的执行分支（`git grep open_command_help` 只命中定义）。
只有调用方不带 `on_command_from` 时（目前没有）才会到 `help_open.set(true)`。所以批末无法用正常操作截图，可选替代证据：

1. **组件测试**（已有，主要证据）：`zig build test-ui -Dui-test-filter="command help"`。
2. **测试模式路由截图**（建议，需另开小包）：在 `multiwindow_test_routes` / 自动化测试路由里加一个仅 `-Dtest-mode=true` 构建可用的动作，
   直接 `nav_host.help_open.set(true)`，e2e 用它打开后截图（明 / 暗 × 默认 / `--material`），并与任一原生 Modal（如“清理数据”确认）对照面板与遮罩。
   本包没有加这个路由（会改宿主的测试接线，超出本包范围），也没有写 e2e。
3. 若产品上认为这条路径已是死代码，可另行判定是否删除（要删用户可见功能，需用户决定；本包未删）。

### 新坑（实测）

51. **只读 Modal 打开后焦点落空**：原生标题栏的关闭按钮（`modal.yix` 的 `close_button`）是带 `onClick` 的 box，不可聚焦；正文里没有可聚焦节点时，
    `pushScope` 的自动聚焦找不到目标，焦点留在遮罩外的终端上——Esc 走终端（不经 Modal，Modal 收不到），键盘输入仍进被遮住的终端。
    绕法：正文放一个原生 `W.Button`（`autoFocus`），本包是脚注的“关闭”。登记 G43。
52. **组件参数传 signal 要写成 `Model(bool)`**：写成 `open: *ui.Signal(bool)` 时组件内是 `ui.Source(*Signal(bool))`，转给 `W.Modal open` 编译期报
    “expected a source of bool”。`Model(bool)` 参数在组件内只剩读端，转给 Modal 时要配 `onOpenChange={|o| open = o}` 才会把关闭写回调用方的 signal。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G43 | `W.Modal` 标题栏关闭按钮不可聚焦，只读 Modal 打开后自动聚焦落空（与已修的 G37 不同：G37 是有可聚焦内容时首次打开落空） | `W.Modal(.{ .title = "t", .open = sig })`，正文只有文字；打开前焦点在外部节点上 → 打开后 `getFocused()` 仍是外部节点，Esc 不关闭 | 关闭按钮改原生可聚焦按钮（进 Tab 顺序、Enter / Space 触发），或自动聚焦无目标时聚焦面板本身，让 Esc 仍经过 Modal |
| G44 | `W.Modal` 的高度上限不随窗口高度收缩 | 视口 1200×420，正文约 540 高的 Modal（默认 `max_height` 600）→ 面板 588 高，上下都超出窗口，标题栏关闭按钮在窗口外（主窗口最小高度 480） | 面板高度上限取 `min(max_height, 视口高 − 边距)`，正文按现有 `height: grow` 收缩（ScrollArea 正文即可滚动） |

## AI 辅助面板（F-set-ai：人工验收反馈 10 后半，`GV8pb` / `e2ys05`）

代码：`model/ai_pane.zig`（视图状态、动作 `Intent.ai`、选择器、编译期 test_id 表）、`view/panes/{ai,ai_providers,ai_dialogs,ai_extensions}.yix` + `ai.yss`、
宿主 `host/ai_settings_host.zig`（`Effect.ai` → 后台任务，`HostStatus.ai` 回流）；测试 `tests/ai_provider_settings_tests.zig`（语义，经真实 `.yix` 窗口）、`tests/ai_settings_yix_tests.zig`。

### 两级：服务提供方列表 → 提供方详情（动态第三级）

- 位置：`settings_history.Location` 追加字段 `ai_provider: ?u8`（只在 `page` = AI 辅助、`sub` = 服务提供方时有意义）；`Controller.ai_provider_detail` 存它，
  `Controller.location()` / `aiProviderDetail()` 校验下标（提供方被删、下标越界 → 视为列表页）；`History.push` 改为整值比较（同一位置不重复记步）。
  进入详情是一次普通导航（`Intent.ai(.open_provider)` → `navigate(.open)`），页头后退 / 前进、换纪元重挂、滚动归零都照旧；页头标题是提供方名称。
  搜索不在详情页进行（进入搜索时清掉，清空搜索回到列表）。
- 与插件包的对应：插件包用 `settings_history.isDynamic` / `dynamic_page`（page = 5、`sub` = 注册表下标）表达“列表 → 详情”；本包没有占用 `sub`，
  而是在 `sub` 之下再加一级（服务提供方本身已是 AI 辅助的一个静态子页）。两者不同名、语义不重叠（插件：动态子页；AI：静态子页下的动态详情），合并时互不覆盖；
  共同改动只有 `History.push` 的比较（本包：`std.meta.eql(now, location)`）。
- 列表行用本地的 `W.Pressable` 行（`ai_providers.yix` 的 `ProviderRow`：头像 + 名称 / 协议与模型数 + 默认 / 状态 + 箭头）。插件包的 `R.DrillRow` 已合入，但它的前导是 30 方块底 + `ui.icons` 图标、尾注只有一段文字；`GV8pb` 的提供方行是圆形文字头像（G46）+ 原生 `W.Tag`“默认” + “未启用”，两处都放不进 `DrillItem`，所以没有换（等 G46 的 Avatar 补上后可以把 `DrillRow` 的前导做成插槽再统一）。
- rebase 到 F-set-plugins 之后的合并点：`Controller.show` 先按插件注册表裁决 `sub`、再记 `ai_provider_detail`；`titleOf` 插件详情分支在前、提供方详情分支在后；两者互不相交（第 5 类 / 第 4 类）。

### 保存作用域

详情页与列表页是同一个作用域（`save_flow.fieldsAt` 只看 page / sub：提供方表 + `ai.default_provider`），所以列表 ↔ 详情、详情 ↔ 详情不弹“未保存的设置”，
草稿里的提供方改动可以跨多个提供方累积，保存一次提交。**“恢复默认…”只在列表页显示**（`ViewModel.resetShown`：位置带 `ai_provider` 时不显示）：
它的作用域是整张提供方表，在某个提供方的详情页上出现会被理解成“恢复这一个”，实际却清空全部提供方；列表页保留 H-save 的原行为（待用户判定项不变）。

### 后台任务归宿主

旧视图在自己的 after-layout 钩子里持有模型发现服务、模型测试与扩展任务线程，页面卸载即取消。现在：view-model 发 `Effect.ai`（`ai_pane.Job`：获取清单 / 取消、测试模型 / 取消、
选择并导入技能、拖入导入、读取 SKILL.md、测试 / 网页登录 / 退出授权 MCP、取消任务、显示 / 收起详情），宿主 `AiJobs.run` 执行，`poll` 每帧收尾（有结果 `vm.sync()`，进行中 33ms 排帧），
`status()` 投影成 `HostStatus.ai`。离开页面不再取消（结果仍按连接签名 / 草稿 id 判定是否作废），关闭设置窗口 `stop()` 取消全部。

### 新坑（实测）

53. **view-model 不能引用 `ui.widgets`**（同坑 47，外观页先遇到）（check-arch `ident:view_model-reactive-subset`）：`W.SelectOption` / `W.MenuItem` 由视图转换。view-model 给纯数据（`ai_pane.Choice`），
    `.yix` 文件里用文件级 `var` 双缓冲换成 `W.SelectOption`（同一设置窗口只有一个实例）。
54. **组件参数的 `options` 是普通值**：`R.SelectRow` 的选项在挂载时取一次。“默认服务提供方”的选项依赖草稿里的提供方（在另一个子页里改），换页时整页重挂，所以够用；
    同一页内选项会变的场景要改成 `Source`。
55. **`W.Input` 的 `inputType` 是普通值**：显示 / 隐藏 API Key 只能 `{if}` 换一个输入框（输入框重挂，焦点不保留；登记 G47）。
56. **`W.Modal` 的正文不滚动**：G40 补上后 `width` / `max_height` / `height` 都能跟随 source，但正文超过 `max_height` 时只裁切、不出滚动条。模型编辑器的表单放进原生 `W.ScrollArea`（最高 280），紧凑窗口（480 高）里页脚按钮仍在窗口内。这是组合写法（原生 ScrollArea 放进原生 Modal），不是覆盖，不另登记缺口。
    对话框只在打开时挂载（`{if}`）的理由也变了：G36 / G37 已补，常驻挂载不会再让 Tab 落进关着的对话框、首次打开也能自动聚焦；但 `W.Modal` 的 `title` 是挂载期取值，“添加模型 / 编辑模型”“删除服务提供方 / 删除模型”的标题随打开方式不同，所以仍按打开挂载（代价：收起时没有原生退出动画，同 `save_bar.yix`）。
57. **`W.Input` 的 `focusId` 落在子树里第一个可聚焦节点**（不是 `input_container`）：e2e / 组件测试判断“聚焦在这个输入框”要看焦点是否在 `parts.input_container` 子树里。
58. **comptime 拼 id 用 `++`，不要用 `comptimePrint`**：32 × 32 个模型 id 用 `comptimePrint` 超过 400k 回溯分支；先编译期生成 0–255 的数字串再 `++`。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G46 | 没有头像组件（Avatar） | 设计稿 `GV8pb` 的提供方行用 `W:y0dYR`（圆形底 + 文字 / 图标）；`ui.widgets` 没有对应组件，本包用 `.yss` 圆形盒 + 文字近似（`ai.yss` 的 `ai_avatar`） | 新增 `W.Avatar(label / icon / src, size, tone)`；补上后换掉 `ai_avatar` |
| G47 | `W.Input` 的 `input_type` 不能随源切换 | `<W.Input inputType={if (shown) .text else .password} />` 只在挂载时取值；切换要 `{if}` 换节点（焦点、选区丢失） | `input_type: Source(InputType)`（或独立的 `revealed: Source(bool)`），切换时只改显示 |
| G48 | 可搜索选择框不能提交自由文字（Combobox 自定义值） | `W.Select searchable` / `W.ComboBox` 都只能提交清单里的选项；“从清单选择或手动输入模型 ID”只能拆成 Select + Input 两个控件 | `W.ComboBox` 增加 `allow_custom: bool`（回车提交输入的文字，`on_change` 给出原文） |

G40（Modal 尺寸参数）已由上游补上（vendor @bc57f042），本包不再需要绕；Modal 正文滚动见坑 56；窗口高度方向见 h-helpcard 登记的 G44（Modal 高度上限不随窗口收缩），补上后表单的 280 上限可以改成跟随窗口。

编号说明：rebase 到 F-set-appearance（新坑 45–48）、F-set-plugins（49）、H-opaque-popups（50）、h-helpcard（51、52）之后，本包新坑由 45–50 顺延为 53–58。G46–G48 核对过集成分支与在途分支，未被占用（G43–G45 空着，未使用）。

### 行间分隔线（反馈 6）

提供方列表行、模型行、技能 / MCP 条目行都在行内盒子底部画 1 px `border` 发丝线（同 `styles.yss` 的 `SettingRow`），最后一行不画。行的 `last` 是挂载期参数，`{for}` 的 key 编码了“是否最后一行”（`ai_pane.rowKey`），增删一行时末行换人会重挂那一行。

## 设置窗口的模态 / 浮层（set-modals：S-12、S-13，外加背景缩略图缺陷）

基线：`revamp/set-modals`（自 `f4282769` 切出）。代码：`model/data_cleanup.zig`（清理流程状态机 + 文案投影，单元测试）、view-model 的
“清除全部数据”与“原地编辑”两节、`view/data_cleanup.{yix,yss}`、`rows.CustomSelectRow`、宿主 `dataCleanupEvent` / `dataCleanupChoice` /
`Effect.pick_directory`、`shell/model/background_texture.zig`；测试 `tests/settings_data_cleanup_tests.zig`、`settings_panes_tests`（自定义 TERM）、
`settings_appearance_tests`（缩略图）。

### 清除全部数据（S-12）

| 当前 | 事件 | 下一个 | 动作（`Effect.data_cleanup`） |
|---|---|---|---|
| 任意 | show(阻塞原因)（宿主打开时；`performDataCleanup` 动手前复查失败撤回 owner 时） | confirm | 无 |
| confirm | blocked(原因)（宿主每帧复查） | confirm | 无 |
| confirm | confirm（未阻塞） | 不变 | confirm → 宿主再查一次，通过则接手并回流 working，否则回流 blocked |
| 任意打开 | working / failed(原因, 可否重试) | working / failed | 无 |
| confirm / failed | cancel（按钮、Escape、标题栏关闭） | closed | dismiss → 宿主恢复滚动与焦点；清除已开始时退出应用 |
| failed | confirm（可重试且未阻塞） | 不变 | retry |
| working | cancel / confirm | 不变 | 无（不可取消） |

原任务书写的“倒计时、勾选”在代码里不存在（旧 `application_data_cleanup_view` 只有确认 / 阻塞 / 进行中 / 失败四态），没有新增。
对话框打开时整窗快捷键放行给它（`windowKey`），设置窗口关闭时确认态收起（进行中 / 失败态保留，宿主仍在收尾）。

### 新坑（实测；rebase 到 h-helpcard / H-opaque-popups / F-set-ai 之后编号顺延为 59–61；缺口 G45 核对过集成分支未被占用）

59. **背景纹理是窗口本地的**：`app.renderer.image_renderer.loadTexture` 进的是这个窗口自己的纹理表（id 不带共享位）；设置窗口是另一个原生窗口、
    另一套渲染器，同一个 id 在那里 `resolveTextureSlot` 得空——`<image>`、材质图层都画不出东西，也不报错。跨窗口要显示的纹理必须进
    `App.sharedImageStore()`（运行时 `shared_gpu = true` 时存在；Linux 退回本地表）。headless 组件测试只有一个 Cx、没有渲染器，复现不了，只能用
    真实窗口取像素（`e2e/settings_thumbnail_native.ts`，未运行）。
60. **Yix 里 `W.Popover` 的 `trigger` 是两样东西**：元素值（`trigger={<W.Button/>}`）是触发器插槽，字面量（`trigger={.manual}`）是触发模式，
    一个元素上只能写一个；也没有 `anchor` 的 Yix 写法。要让“选择框选中某项后”在选择框下方弹出受控浮层，写法是把选择框与一个
    **没有触发器内容**的 `trigger={.manual}` Popover 排成一列（`S.custom_anchor`）：Popover 的空触发器盒子落在选择框左下角，浮层按
    `bottom_start` 定位、原生翻转 / 平移。登记 G45。
61. **headless 里点原生 `W.Select` 的选项要先等下拉面板进场**：打开后同一帧点选项不命中（面板还不可命中），`frames(8)` 后再点。

### zenit 缺口（新增，只登记）

| 编号 | 缺口 | 最小复现 | 建议 |
|---|---|---|---|
| G45 | Yix 里 `W.Popover` 不能同时给触发器内容与触发模式，也不能指定锚点元素 | `<W.Popover trigger={.manual} open={…}>` 想锚在旁边的 `<W.Select>` 上：`trigger={<W.Select/>}` 会把 Select 包进 click 触发器（点 Select 同时切换浮层），`trigger={.manual}` 又没有插槽内容；`PopoverProps.anchor` 只有 Zig 写法（`*Node` / `VirtualAnchor`） | 触发模式改名（如 `triggerMode`）或插槽改名（`triggerContent`），或给 Popover 一个 Yix 可写的锚点（`anchorId="settings.field.term"` 按 test_id / focus_id 解析） |

## set-adopt：采用上游补齐的能力（vendor @bc57f042），清理主题库死代码

上游 G27–G29、G31–G33、G35–G38 补上后，设置窗口里对应的例外与绕法逐个收回（每项单独提交，行为 / 视觉变化与纯重构分开）：

| 项 | 上游 | 改法 | 性质 |
|---|---|---|---|
| S-16 | G28 | `<W.TitlebarEdge />` 直接写在 `page.yix`，删除 `view/titlebar_edge.zig`（`4dc5b27b`）；视口 `scrollEdge`（`9badf52d`，评估见“设置外壳最终用法”） | 重构；视觉：滚动后页头下方出现渐进磨砂 |
| S-17 | G27、G29 | 页头 `W.GlassToolbarGroup` / `W.GlassToolbarButton`（`4ccc0ed9`）；导航 `fill={.height}`（`eded65de`） | 视觉：36pt 工具栏胶囊、38 宽按钮、工具栏调色板；行为：工具栏按钮不进 Tab 顺序 |
| S-19 | G38 | `<W.NotificationHost>` + view-model `toast` 信号（`85923922`） | 重构（文字 / 位置不变） |
| 键帽 | G32 | `W.Kbd`（`keys` = `ViewModel.keyCaps`，`tone` 随录制态）（`cbf6e797`） | 视觉：Kbd 键帽外观 |
| 录制失焦 | G31 | 键帽区 `onBlurWithin` 结束录制；锁提示 `onFocusWithin`（`3695ab95`） | 行为：点别处也结束录制；键盘聚焦锁按钮开提示 |
| 尾随图标 | G33 | 发布来源外链图标、图片对齐下拉箭头 `iconPosition={.trailing}`（`183a06ae`） | 视觉 |
| Slider testId | G35 | `testId` 写回 `W.Slider`（`3d72fa5e`） | 重构（test_id 落在轨道上） |
| 确认对话框 | G36、G37 | 常驻挂载，去掉 `{if}` 与 `animateInitialOpen`（`56bb2e4e`、`9336978f`） | 行为：收起有原生退出动画 |

### 主题库死代码（`4e93ef5e`）

逐个 `git grep` 证明没有生产调用点后删除：`appearance_view.zig` 的 `ThemeGrid`、`FilterClick`、`dismissedTheme`、`thumbnail`，`Click` 的
`.open_library` / `.close_library` / `.favorite`；`appearance_styles.zig` 只为它们服务的 `thumbnail` / `dismissedTheme` / `tile*` 与几何常量；
`appearance_ui_context.Command.favorite`、picker 的 `.favorite` 分支、worker 的 `startFavorite` / `.favorite` 任务 / 收藏文件路径；
`theme_registry.zig` 的收藏持久化（`favorite` / `loadFavorites` / `Record.favorite` / `Counts.favorites`）、`Filter` / `matches`、
`LibraryState` 的 `query` / `filter` / `setQuery`；`e2e/theme_library.ts`（它操作的网格与收藏按钮在任何外壳里都挂不出来）；对应的组件测试用例与断言；
test_id 9 条（`settings.theme.{dismissed,empty,grid,library.open,preview,search}` 与前缀 `settings.theme.{favorite,filter,selected}.`）。
用户已有的 `themes/favorites.json` 不再读取（无副作用）。设计稿的主题库（搜索 / 筛选 / 收藏）不实现。

**没有删、上报 lead 的部分**：`theme_library.open` 有一个用户可达的写入点——状态栏“全局主题”弹层的“管理主题”按钮（`status.theme.manage`）
→ `AppNavHost.manageGlobalThemes`（`src/features/shell/host/nav_host.zig`）把它置真、把 `appearance_context.library_dismissed` 置假，再打开设置
到“外观与主题 › 主题”。这个入口在产品里可达，但它打开的只是普通的外观页（主题库网格从不挂载），`open` 唯一的可见效果是选了另一个滚动槽
（`ScrollSlot.theme_library`）。按“发现用户可达入口就不删、停下上报”的要求，`theme_library.open`、它的滚动槽、`library_dismissed`、
`SettingsHost.mounted_theme_library_open` 与相关测试保留，待 lead / 用户判定（建议：入口保留，`manageGlobalThemes` 只导航、不再写 `open`，
随后删掉 `open` / 滚动槽 / `library_dismissed`；`nav_host.zig` 不在本包范围）。

**robustness 包收尾（#19，按上面的建议执行）**：`manageGlobalThemes` 只导航到“外观与主题 › 主题”，不再写任何主题库状态；
`LibraryState.open` / `scroll`、`ScrollSlot.theme_library`（槽数改为普通 9 + 搜索 9）、`appearance_context.library_dismissed`、
`SettingsHost.mounted_theme_library_open` 已删除，相关测试改为断言只导航、只挂 V3 主题条。`status.theme.manage` 入口与 test_id 不变。

## 窗口通知栈（native-notify）

每个应用窗口两个原生 `<W.NotificationHost>`（`src/features/notifications/view/toast_stack.yix`；notify-two-hosts，用户判定）：右上角卡片栈（全局提醒、命令失败提示）与中下方标准 Toast（本地回执，zenit 默认位置）。view-model `model/view_model.zig` 分 `cards` / `toasts` 两条通道发请求（与 `NotificationPost` 同形，每条通道双缓冲持有字符串）、收事件；宿主胶水 `host/notification_presenter.zig` 每帧把协调器给本窗口的提醒投影进卡片通道，并分别算两个栈停靠区的遮挡。全局提醒用固定原生 id 就地转换；本地回执与命令失败提示各用一段 id。一个窗口挂两个 NotificationHost 不需要上游改动（每个 Notifier 自有浮层层、悬停 / 焦点暂停、抑制）。

### zenit 缺口（上游已补、已采用）

| 编号 | 缺口 | 上游 | 采用 |
|---|---|---|---|
| G49 | 卡片没有可展开的详情（旧实现：展开按钮 + 有界滚动的详情，失败默认展开） | `Notification.detail` / `detail_expanded`，原生展开按钮 + 160 高有界 ScrollArea；用户展开时计时暂停（`ecf844cf`，`f1400657`：默认展开不挡计时） | 全局提醒的详情；命令失败提示的输出预览 |
| G50 | 卡片最多两个动作（协调器事实最多三个） | `notification.max_actions = 3`（`d47121b5`） | 全局提醒 |
| G51 | 键盘焦点在卡片里时不暂停（旧实现：焦点暂停） | `Notifier.holdsTimers` 含焦点（`00dbc96b`） | 全部卡片 |
| G52 | 栈不能整体隐藏而不关闭（旧实现：提醒角被浮层盖住时隐藏并暂停，操作失败例外） | `Notifier.setSuppressed`、`NotificationHostProps.suppressed`（`ab41e139`） | `ViewModel.setCardsCovered` / `setToastsCovered`（两栈各自） |
| G53 | 卡片 / 提示的部件没有 test_id | `Notification.test_ids` / `Hint.test_ids`（root / title / body / detail / detail_frame / detail_toggle / footer / life_bar / close / action），`NotificationHostProps.test_id`（`adfc9d3e`、`851b5593`） | 旧 test_id 原样保留 |
| G54 | 带展开详情的卡片在矮窗口里超出窗口，动作按钮出屏 | `Notifier.fitDetails`：详情框最高 160、最低 48，按栈区域收缩（`9394142e`） | 全局提醒、命令失败提示 |

另修两处原生缺陷：卡片正文 / 详情里的长串（路径、哈希）撑宽文字列被裁掉（`9fb04885`），动作按钮长标签把按钮行推出卡片（`54935c3e`）。

## 连接失败视图与跳板引导（r3-connections：design-r3 稿 1、稿 4）

- 失败视图：纯函数投影 `progress/model/failure_view.zig`（`Input` → `Projection`，单测覆盖四种原因）+ 状态持有者
  `progress/view/failure_controller.zig`（一个 `Signal(Projection)`）+ 模板 `connection_failure.yix`。首次失败时才挂载
  （多数连接不会失败；也让进度卡片 Debug 挂载留在 3 MiB 线程栈预算内）。
- 跳板引导：`wizard/view/jump_guide_view.zig`（信号与动作）+ `jump_guide.yix` 三个组件，由 RemoteEditor 经 connections 门面挂载。
  “新建跳板主机”复用已有的嵌套编辑器（`EditorHost.openChildFor`，新 intent `create_jump`，`subject` 带父草稿的目标名）。

### 新坑（实测）

62. **发布给模板的字符串不能在下一次发布时释放。** 用“双缓冲 arena、每次发布换一块”的写法会崩：`Signal.set` 先拿旧值做深比较
    （`eqlValue` 解引用旧切片），`{for}` 的协调与 `{vm.x()}` 的 memo 也在之后惰性地拿上一个值比较，可能隔了不止一次发布。
    绕法：发布前把所有字符串与行数组驻留（interning）到视图生命周期的 arena 里（`FailureView.publish`），投影里再带一个递增的
    `generation` 字段，让 `Signal.set` 在第一个字段就判定不同、不去比较旧字符串。每次尝试的不同字符串很少，驻留量很小。
63. **文本节点的样式里不能写布局字段。** `<text style={...}>` 的样式只认文字字段（`flex-shrink`、`width` 等会编译报错
    “a text style has no field”）；布局写在 `box={...}`。行内撑满剩余宽度用 `width: grow`（`flex: 1` 在这里不生效）。
64. **`W.BadgeStatus` 没有从 `W` 直接导出**，要写 `W.badge.BadgeStatus`。
65. **嵌套编辑器宿主晚于编辑器到达。** 向导窗口挂好后才挂 `plugin_editor_host`，此时首个协议编辑器已经挂载，拿不到
    `EditorHost`；`Wizard.attachEditorHost` 负责补给已挂载的编辑器并登记当前草稿版本。

