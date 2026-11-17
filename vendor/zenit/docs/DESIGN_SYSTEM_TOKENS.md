# Zenit Design System Tokens v1

状态：v1 生成器、UI provider 绑定、统一引用、typography 和 examples 迁移已实现。日期：2026-10-04。实际命令、接口和剩余边界见 [TOOLING.md](design-system/TOOLING.md)。

本方案面向现有 `ui.css / ui.cva / ui.sva / styles.zig / Yix`。JSON 负责声明设计材料，Zig 负责组件、计算和状态选择。配套的 [theme.example.json](design-system/theme.example.json) 是完整语法示例，[theme.schema.json](design-system/theme.schema.json) 提供编辑器结构校验；引用解析、循环检查等仍由生成器完成。

示例展示声明和消费规则，数值不是现有默认主题的替代品；真实迁移需按第 11 节逐值保留当前外观。

## 1. 决策与职责

| 层 | 职责 | 可依赖 |
|---|---|---|
| `tokens` | 基础颜色、尺度、尺寸、时长及复合材料 | 其他基础 token |
| `semantic` | 用途命名、补充值及有类型的材料组合 | 基础或其他 semantic token |
| Zig 样式 / recipe | 选择材料、布局、变体、交互状态、业务状态 | 两层材料及普通 Zig 代码 |

两层材料共用类型、引用和主题解析规则。semantic 可省略，也可以直接定义具体值。声明时保留两层，用于组织材料和校验依赖；消费时合成一个 TOKENS，两层地位相同，不设优先级。禁止基础 token 反向依赖 semantic。

框架约定类别的含义和合法值结构；应用决定 token 名称，不再限定字号叫 `xxxl` 或间距叫 `_4`。新增渲染值种类由框架显式注册，不根据字符串内容猜测类型。

JSON 不描述组件树、事件、recipe variants、hover/selected 等节点状态，也不执行计算表达式。设计系统可以命名一个 `accent_hover` 颜色，但把它绑定到 hover 是组件样式的职责。

## 2. 文件结构

```json
{
  "$version": 1,
  "tokens": {
    "font_size": { "body": 14, "xLargeBlaBla": 32 },
    "color": { "ink": "#181818", "paper": "#ffffff" }
  },
  "semantic": {
    "font_size": { "title": "{tokens.font_size.xLargeBlaBla}" },
    "color": {
      "surface": { "$light": "{tokens.color.paper}", "$dark": "{tokens.color.ink}" }
    }
  }
}
```

顶层只有以下字段；未知字段报错：

| 字段 | 必需 | 含义 |
|---|---|---|
| `$version` | 是 | 文件语法版本，v1 为整数 `1` |
| `$schema` | 否 | 编辑器使用的 JSON Schema 路径/URI；构建器不联网获取它 |
| `tokens` | 是 | 基础材料，可为空对象 |
| `semantic` | 否 | semantic 材料，默认空 |
| `$modes` | 否 | 自定义主题模式的名称、明暗属性和回退关系 |

输入使用严格 UTF-8 JSON。重复键、注释、尾逗号均报错。文件内不引入 import/extends/deep-merge 配置语言；多文件组合只有一种：生成器按命令行顺序叠加主题层（底层 + overlay，覆盖须逐 token 显式 `$override`，见 10.1）。共享设计系统可以作为 Zig 包提供生成模块。

### 2.1 名称和路径

token/分组名称匹配 `[A-Za-z0-9_][A-Za-z0-9_-]*`，保留大小写。支持 `xLargeBlaBla`、`500`、`extra-large`，不悄悄改名。点是路径分隔符，不能出现在单个名称中；`$` 前缀保留给语法。需要支持其他字符时通过格式版本扩展。

标量类别可嵌套分组，例如 `tokens.color.blue.500`。生成 Zig 时使用必要的 `@"..."` 转义，不把点/横线替换成下划线，也不使用数组序号作为对外稳定 ID。

v1 的 `shadow / typography` 是固定形状的复合值类别，类别下直接放具名 token，不支持在这两个类别内再嵌套分组。这样 `shadow.card` 的对象始终是阴影值，不需要猜测它是否是一个分组。标量色阶仍可任意分组。

v1 不提供“分组同时也是值”的 `DEFAULT` 特例；使用 `surface.default` 和 `surface.muted` 等显式路径即可。可用的名称不受框架默认 scale 限制。

## 3. 值语法

每个 token 使用以下三种形式之一：

```json
14
```

```json
"{tokens.font_size.body}"
```

```json
{ "$light": "#ffffff", "$dark": "#181818" }
```

有描述信息时可以使用可选长形式；普通 token 无需包装：

```json
{ "$value": 14, "$description": "正文的默认字号" }
```

`$value` 内可以是直接值、引用或主题对象。长形式只允许 `$value/$description`，不能与分组或主题键混写。复合值也可以使用长形式。

### 3.1 类别与单位

| 类别 | 具体值 / Zig 值类型 | v1 校验 |
|---|---|---|
| `color` | `Color` | `#RGB/#RGBA/#RRGGBB/#RRGGBBAA`，sRGB，alpha 位于末尾 |
| `space` | `f32`，逻辑像素 | 有限、非负 |
| `radius` | `f32`，逻辑像素 | 有限、非负 |
| `font_size` | `f32`，逻辑像素 | 有限、正数 |
| `font_weight` | `u16` | 整数 1–1000 |
| `line_height` | `f32`，字号倍数 | 有限、正数 |
| `border_width` | `f32`，逻辑像素 | 有限、非负 |
| `size` | `f32`，逻辑像素 | 有限、非负 |
| `opacity` | `f32` | 0–1 |
| `duration` | `f32`，秒 | 有限、非负，沿用现有单位 |
| `breakpoint` | `f32`，窗口逻辑宽度阈值 | 有限、非负；仅提供材料 |
| `shadow` | `Shadow` | 下述固定形状 |
| `typography` | `TypographyPatch` | 下述部分排版值 |

数字按类别转换并检查目标类型可表示范围，不能把整数 `14` 和小数 `14.5` 推导为不同的字号类型。所有模式使用相同类型。

转换为目标类型后再次检查范围：例如极小的正字号不能下溢为零。font_weight 按数学整数校验，`400` 和 `400.0` 都表示整数 400，与 JSON Schema 一致。

第一版不解析 CSS 的 `calc/rem/clamp/rgba()` 字符串，不提供负间距生成、任意数组含义、渐变、字体资源加载、多层阴影等额外语言。已有渲染能力可继续通过 Zig 使用。未来为一个新类别增加值结构，不改变其他类别的解释。

### 3.2 复合材料

阴影：

```json
{
  "color": "{semantic.color.shadow}",
  "blur": 16,
  "offset_y": 4
}
```

`color` 必需；`blur/spread/offset_x/offset_y` 默认 `0`。blur 非负，spread/offset 可为负数；值必须有限。内部 color 可引用颜色 token，长度字段可引用 `space/size` 或直接数字。生成器显式写出全部字段，不继承当前 Zig `Shadow` 的非零默认 blur/offset。未支持字段报错。

排版聚合：

```json
{
  "font_size": "{semantic.font_size.title}",
  "font_weight": "{tokens.font_weight.bold}",
  "line_height": 1.2
}
```

`font_size/font_weight/line_height` 至少一个存在，其他字段保持未声明，不填框架默认值。输出 `TypographyPatch`，在样式使用处展开。它不会带入颜色、布局或组件状态。字体家族接入需要处理现有 `u16` 字体注册 ID，另列后续能力，不能把任意字体字符串假装成已可渲染的 ID。

组件的 size / variant 组合由 cva / sva 声明；theme 只提供这些组合所引用的基础或语义材料。生成器没有 `control` 类别，也不认识组件的尺寸枚举。

复合对象内部不嵌套 `$light/$dark`；需要变化时引用有主题值的单值 token，或在整个复合 token 外写主题对象。主题分支提供独立的复合值，省略字段使用该类别的固定默认值，不继承另一分支的字段。

## 4. 主题模式

### 4.1 默认行为

`light` 和 `dark` 内置。直接值对所有模式通用，并作为 light 默认；引用则在当前请求模式下求值。

- 主题对象必须有 `$light`，它是当前语法中的默认分支。
- 没有 `$dark` 时，dark 回退到 `$light`。
- 只有 `$dark` 没有 `$light` 报错，不生成可缺项的主题类型。
- `$light` 不自动推导 dark，也不根据色值判断明暗。
- 内部表示叫 `default + overrides`；不能把未来的所有条件硬编码成 `is_dark`。

模式元数据与值声明分离，自定义模式只声明一次：

```json
{
  "$modes": {
    "high_contrast": { "scheme": "dark", "fallback": "dark" }
  }
}
```

随后任何 token 可增加 `$high_contrast`。自定义模式的 `scheme` 和 `fallback` 均显式给出；fallback 必须存在且无环。内置 light 无 fallback，dark 回退 light；不能在 `$modes` 中重定义它们。

自定义模式名沿用 token 名称规则；`version/schema/modes/value/description` 为语法保留名称，不可用作模式名。

按 token 选择：当前模式分支 → 沿模式 fallback 查找 → light 默认。直接值无需复制为多个主题分支。未知 `$dakr` 报错，不能自动注册为新模式。

### 4.2 引用的主题行为

```text
button_bg = 引用 accent
accent = { light: blue500, dark: blue300 }
```

`button_bg` 即使没有 `$dark`，在 dark 下也必须得到 blue300。选择引用表达式所在的回退分支，不会把引用目标强制切回该分支的模式；目标仍按最初请求的模式解析。

类型校验覆盖所有分支；循环检测在每个已声明模式的实际引用图上完成。不能仅用所有模式边的并集判环，否则会错误拒绝“light 下 A→B、dark 下 B→A，但各自有常量终点”的合法定义。

### 4.3 响应式边界与未来条件

`breakpoint.compact = 640` 只定义阈值。卡片在宽度低于 640 时是否减小 padding，由卡片样式决定；semantic 不替所有组件预先做这个决定。

组件通过 Signal/Memo 得到当前 size 或是否 compact，传给 `cva/sva` variant；连续映射使用 `view.styleBy`。视口宽度使用逻辑像素；窗口尺寸是输入，不能从组件刚计算出的自身尺寸反向影响同一次求值，避免布局反馈环。

v1 的 `$light/$dark/$custom_mode` 只表示互斥主题模式。后续如需增加 breakpoint、缩放或用户偏好等条件，必须注册条件来源、作用域、优先级、组合及失效通知；未知条件在 v1 直接报错。组件局部响应式选择无需等待 JSON 条件扩展。

全局共享材料确实具有环境适配合同后，才为该材料增加条件值；“允许条件”不意味着所有响应式逻辑都要搬进 token。

## 5. 引用与类型规则

引用只能是整个字符串 `{tokens.category.path}` 或 `{semantic.category.path}`，不支持字符串插值、计算或跨模式寻址。路径区分大小写，禁止不带 namespace 的相对引用，便于定位来源和移动文件。

整 token 引用必须属于同一类别：`font_size` 不能因为最终都是 `f32` 就引用 duration 或 space。复合字段的可引用类别在其字段定义中固定。所有目标必须存在，基础层不能引用 semantic。不允许引用分组、主题键或复合 token 的内部字段；需要共享内部值时，将其声明为独立 token。

消费名称由 `类别 + 类别内路径` 唯一确定，去掉声明来源的 tokens/semantic 前缀。例如 `tokens.color.blue.500` 生成 `TOKENS.color.blue.@"500"`，`semantic.color.surface` 生成 `TOKENS.color.surface`。

同一类别下，两层不能声明相同路径；即使值相同，也报重复定义并指向两个声明位置，不静默覆盖或去重。不同类别可使用同名 token。两层同路径的分组可以合并，但一个 token 路径不能同时成为分组，例如基础层的 `color.action` 与 semantic 的 `color.action.hover` 冲突。

JSON 引用仍保留 tokens/semantic 前缀，用于依赖校验和来源追踪；Zig 消费接口不暴露这个区分。生成次序不影响引用结果；输出稳定排序，token ID 为本次构建内部细节，不能持久化或跨构建传输。

## 6. 生成的 Zig 接口

### 6.1 两种数据：引用与当前值

生成物同时提供：

- `refs`：两层合并后的有类别引用常量，用于静态样式定义；应用统一命名为 `TOKENS`。
- `Values.tokens`：两层合并后、当前模式下已解析的数值/颜色/复合值，用于样式函数；结构与 refs 对应。
- `Token(category)`：该类别所有合法相对路径构成的枚举，不带 tokens/semantic 前缀。
- `Mode`：`.light/.dark` 和已声明自定义模式的枚举。
- `modes`：每个模式的不可变完整 `Values` 实例。
- 元数据：名称、类别、源文件 JSON Pointer、原始引用、模式下的解析路径；可独立导出供工具使用。

目标用法：

```zig
const ui = @import("ui");
const TOKENS = ui.theme.refs;

pub const card = ui.css(.{
    .background = TOKENS.color.surface,
    .padding = TOKENS.space.content_gap,
    .corner_radius = TOKENS.radius.card,
});

pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{
        .color = t.tokens.color.text,
        .font_size = t.tokens.font_size.title,
        .font_weight = t.tokens.font_weight.bold,
    };
}
```

`TOKENS.color.surface` 是 `Token(.color)` 的引用，不是在定义 card 时已读取的某个颜色。只有应用样式时才从当前 Values 取值。使用方不需要知道它来自基础层还是 semantic；把 token 从基础层移到 semantic 且保持类别和路径不变时，消费代码无需修改，JSON 内的来源引用仍需更新并通过依赖校验。

所有渲染材料最后落到框架具体值类型，不在绘制循环里解析 JSON 或查字符串。

### 6.2 枚举简写

保留 `.font_size = .xLargeBlaBla`。按属性类别在合并后的 token 集合中查找**完整相对路径**，不存在则编译报错。重复路径在生成阶段已经拒绝，无需使用处选择基础或 semantic。

嵌套路径可写 `.background = .@"blue.500"`。Zig 枚举不接受带 tokens/semantic 来源前缀的路径；`TOKENS.color.blue.@"500"` 提供更适合补全、避免拼字符串的主要入口。

渲染枚举如 `.fill/.fit/.center` 仍由对应样式字段解释。新增 token 类别不能随意接管这类枚举。font_weight 的名称改由应用 scale 提供，默认 preset 保留现有常用名称；透明色可显式写 `ui.Color.TRANSPARENT`，不以隐藏的内置 token 抢占应用名称。

动态选择一个已生成 Token 枚举值可在样式函数/styleBy 内解析；它不会因为是枚举就自动变成 Signal。运行时任意新名称需要重新生成，本方案不承诺动态增加 schema。

类别存在不等于每个样式字段都自动支持该类别。v1 的消费映射如下；错误类别必须编译失败，不能因底层都是 f32 而隐式转换：

| 消费位置 | 接受类别 |
|---|---|
| background/color/边框颜色 | color |
| padding/margin/gap 及其分量 | space |
| corner_radius/边框圆角 | radius |
| font_size/font_weight/line_height | 对应同名类别 |
| border_width 及其分量、opacity、shadow | 对应同名类别 |
| width/height 等 Sizing 字段 | size ref 或裸 token 枚举转为 px；原有 fill/fit/percent 语法保留 |
| typography | typography，按下一节展开 |
| duration/breakpoint | 通过当前 Values 在 Zig 动画、条件判断中消费 |

Sizing 字段已支持裸 token 枚举与显式 size ref。`.fill/.fit` 优先解释为布局语法；应用同名 token 用 `TOKENS.size.fill` / `TOKENS.size.fit` 明确引用。表中类别已接入共享解析器。

### 6.3 排版聚合的消费

目标 `ui.css(.{ .typography = TOKENS.typography.heading, .color = TOKENS.color.text })`：先展开 TypographyPatch，再应用同一对象中显式声明的文本字段，显式值覆盖聚合值，与字段书写顺序无关。

展开只设置聚合实际声明的字段，不能构造带默认字段的完整 TextStyle 来覆盖前一层。`.typography` 用在不接受文本属性的目标上编译报错。

`sva` 支持文本 slot：视图里 `.of(args).label` 可直接交给 `view.text`，手动解析用 `.Slot(.label).resolveText(variants, base, t)`（`src/ui/css.zig`）。文本 slot 不接受条件层（`_hover` 等，文字状态用 variant 表达），也不参与 `derived`（derived 只供盒几何）。这是样式系统自身的能力，不由 token 生成器改变。

## 7. css / cva / sva / 旧 recipe / Yix 接入

所有入口使用同一份 schema 和 token resolver，生成的基础/semantic 引用在 base、variants、compound 和普通 css 内具有相同意义。

```zig
const Card = ui.sva(.{
    .slots = .{ .root, .content },
    .base = .{
        .root = .{ .background = TOKENS.color.surface, .corner_radius = TOKENS.radius.card },
        .content = .{ .gap = TOKENS.space.content_gap },
    },
    .variants = .{ .density = .{
        .compact = .{ .root = .{ .padding = TOKENS.space.space100 } },
        .comfortable = .{ .root = .{ .padding = TOKENS.space.loose } },
    } },
    .defaults = .{ .density = .comfortable },
});
// 调用方决定 density 是否来自窗口、容器、用户选择或固定值。
const parts = Card.of(.{ .density = density_source });
```

当前 sva 合并顺序 `base < variants < derived < compound` 保留；外部 style tuple 按原有顺序叠加。derived 仍接收当前 tokens，不把 JSON 解析或条件注册塞进 derived。颜色仍通过现有条件/paint 路径处理。

token 条件先选定具体值；组件 `_hover/_active/_focus/_disabled/...` 继续由交互状态系统选择样式。token 声明不注册节点事件。各模块共享同一 recipe 语义，不增加“配置式 recipe”这一套第二 API。

旧 `ui.recipe` 具名函数路径也要接收同一个 `ThemeTokens` 别名，不能出现新 css 跟随应用主题而旧控件仍读取另一份主题的情况。Yix 继续透传 style/parts 给 Zig，不另做 token 扫描或样式提取器。

## 8. 内置 recipe 的 semantic 依赖

内置 recipe 和应用 recipe 一样，直接读取统一的 `TOKENS` / `Values.tokens`。内置 recipe 使用约定的 semantic token 名称，应用提供这些名称即可；基础 token 名称完全由应用决定。

例如，内置文字样式使用 `font_size.lg`，应用基础字号可以叫 `bodyCopy`：

```json
{
  "$version": 1,
  "tokens": { "font_size": { "bodyCopy": 14 } },
  "semantic": { "font_size": { "lg": "{tokens.font_size.bodyCopy}" } }
}
```

这只是现有 token 引用语法。没有 `bindings` 字段、`Values.system`、旧字段镜像或自动同名映射；缺失 token 唯一的回退是下面的组件角色默认别名。recipe 直接引用一个不存在的 token 会编译失败；应用需要提供实际使用的 recipe 所依赖的 semantic 名称。默认文字样式同样有明确的 `color.fg_primary` / `font_size.lg` 依赖。

### 8.0 组件角色 token

内置控件的配色读组件角色 token，而不是直接读 `accent` 等通用语义名：按钮 `button_primary_*` / `button_secondary_*` / `button_danger_*`，Checkbox / Radio `checkbox_*`，Switch `switch_*`，Slider `range_*`，Progress `progress_*`，以及焦点填充 `bg_focus`。完整清单及默认别名目标见 `src/tokens/roles.zig`。`default.json` 与 `examples/theme.json` 显式声明每个角色，值是别名，生成后的平铺值与角色出现前 recipe 读到的值逐字节相同。

生成期别名会展开成平铺值：运行期复制 `ui.theme.light` 改 `tokens.color.accent` 不会传给 `checkbox_checked_bg` 等角色；要改某个控件配色，直接写对应角色字段（例如 `t.tokens.color.checkbox_fg`）后 `cx.setTheme`。

主题 JSON 若缺少某个角色（任一拼写 `a_b` / `a-b` 均算已声明），解析器按 `roles.zig` 把它补成 `semantic` 层对目标 token 的别名（如 `semantic.color.checkbox_fg = {semantic.color.fg_inverse}`）；目标也不存在时不补。这样角色出现前写好的完整主题照常编译、外观不变，生成的 `Values` 也总带这些字段。补齐在解析器里做（生成器、dev preview、yix-lsp 共用），而不是在消费端（`ui.tokenRef` 或手写 Zig 读字段）做回退：后者需要每个读点各自记得回退，并且运行期 `Values` 字段会因主题而异。

除这张角色表外，解析器只负责固定 JSON 语法和类型规则，不认识 Button、Input 等组件，也不验证组件 token 名称。两层在消费时地位相同；组件依赖可以直接满足于基础材料，也可以通过 semantic 聚合、补充或引用自定义基础名称。不要为了满足名称约定把整个基础尺度搬进 semantic。全套示例所需的名称见 [examples/theme.json](../examples/theme.json)。

应用选择默认设计系统时使用框架的 `default.json`；选择自定义 provider 时，完全使用应用声明，不偷偷合并默认材料。ControlShell 的 xs/sm/md/lg 是组件自己的 size 变体（`src/ui/components/control_shell/styles.yss` 的插槽配方 `SizeRecipe`，编译为 `ui.sva`，跨维度几何是参数化样式 `geometry`）；`ui.widgets.ControlSize` 与 `ui.widgets.control_shell.metrics(t, size)` 都属于组件层。主题不存组件尺寸矩阵：默认 JSON 只提供被 recipe 引用的材料（如 `semantic.size.control_xs/sm/md/lg` = 20/24/32/40、`semantic.size.row` = 28、`tokens.radius.control` = 6），档位如何组合 padding、字号、圆角由 recipe 决定。

### 示例的分类规则

- `tokens` 放可复用的基础尺度：`space.space50 = 2`、`space.space100 = 4`、`space.space200 = 8`，以及字号、字重、圆角、尺寸、时长和阴影。数字后缀表示尺度档位，100 对应 4 个逻辑像素。默认 `src/tokens/default.json` 的基础层还包括调色板色阶 `color.app_gray / neutral / blue / green / amber / red / violet / teal.<档位>`、角色圆角 `radius.control / panel / island / dialog / focus`（6 / 8 / 10 / 12 / 8）、`border_width.focus` 与 elevation 阴影 `shadow.xs / sm / md / lg`（y 偏移 / 模糊 1/2、2/8、6/20、12/40，三种模式各有颜色）；semantic 颜色（`accent`、`bg_primary`、各状态的 `*_tag_bg/border`、`*_alert_bg/border`、`*_pressed`、`button_base_*` / `button_pressed_bg`、`disabled_bg` 等）按模式引用这些色阶。
- `semantic` 放用途：前景/背景/状态色、内容字号、标题排版聚合。允许引用材料，也允许直接补充值；不为每个语义值制造无意义的同值基础别名。
- `size = .sm/.md/.lg` 如何组合字号、padding、radius、icon，由组件 recipe 声明。光学校正可以留在 recipe，不为一次性偏移扩大全局 token 表。
- 两层共享 `TOKENS`，同类别完整路径不能重复；基础材料不能反向引用 semantic。

### 8.1 Zig 模块与类型身份

一个 ui 模块实例绑定一份 provider，保留 `Cx` 非泛型使用方式。生成 provider 仅导入独立 `zenit_style_values` 模块，UI 与生成器共用这一模块里的 Color、Shadow、TypographyPatch 和 ColorScheme 类型。不存在组件角色合同模块或 generated theme → ui 循环。

build helper 传递规范值模块的同一个实例；同一 UI 实例绑定不同 provider 会构建失败。独立应用使用独立构建图。同一 schema 的不同模式通过 `cx.setTheme` 切换。

## 9. 更新、生命周期与性能

v1 模式值在生成期全部解析，输出为不可变、静态生命周期实例。应用通过目标接口 `cx.setTheme(&ui.theme.modes.dark)` 切换，默认模式选择由应用启动代码负责，不由 token 文件决定系统偏好策略。

尽量复用当前 theme signal/on_theme 链，但统一以下保证：

- 引用和语义间接引用都被识别为依赖 tokens；不能仅检查枚举字面量或是否直接写了 `$dark`。
- 完整切换一次性发布同一模式的所有值；主题依赖样式在下一次呈现前更新一致。节点树重放不是对任意同步回调都不可观察的事务，不承诺中途读取所有节点均已完成更新。
- 通过 ui.view 或 styled builder 声明的样式被重放；用户手动读具体值构造的普通快照仍是快照。
- paint_state 的颜色/透明度与几何属性分别走现有正确写入路径；颜色变化不以写 Style 字段代替。
- 条件撤销恢复正确基线，重新应用 recipe 不重建业务节点或丢失交互状态。
- 挂载的独立 overlay/portal 需要同样的模式通知；不能只依赖遍历 cx.root 而遗漏它们。
- 不在 before_render 中轮询 token，不因为 token 依赖永久关闭渲染缓存。

第一版允许所有主题依赖样式随模式切换重算，先保证正确性。精确到单 token 的依赖订阅属于后续优化，不能宣称生成枚举就自动实现了零更新成本。

窗口条件作为组件输入提供独立 Signal/Memo。v1 不把 resize 转换成全局主题切换，也不自动给所有间距/字号发布新值。后续局部模式作用域需要处理嵌套覆盖、portal 所属作用域与清理，单独验收后开放。

## 10. 生成流程与工具

目标 CLI：

```text
zenit-tokens check theme.json
zenit-tokens generate theme.json --out theme.gen.zig
zenit-tokens explain theme.json semantic.color.surface --mode dark
```

仓库已以 `zig build tokens -- ...` 暴露同一 CLI，安装后的可执行文件名为 `zenit-tokens`。生成器是 host 工具，可为跨编译的 target 输出 Zig 源文件。

处理顺序：

1. 严格 JSON 解析，保留字节范围和 JSON Pointer，拒绝重复键。
2. 验证版本、类别、名称、值结构和自定义模式。
3. 收集全部 token 身份与类别，不依赖声明顺序；合并消费路径，拒绝重复定义与 token/分组冲突。
4. 校验所有分支的引用存在性、方向与类型。
5. 按模式选分支、检测实际依赖环、解析全部 token 值。
6. 确定性生成 Values、引用常量、类别枚举、模式实例及元数据。
7. 编译实际生成物，验证模块身份及 UI 消费路径。

生成失败不覆盖上一次成功产物；通过临时文件原子替换。构建图的 host run step 声明输入和输出，普通应用构建自动依赖生成步骤，无需手动维护两份声明。JSON 文件、生成器版本和规范值类型版本都参与缓存键。

生成物进入构建缓存，应用源码只 import 注册好的模块。发布共享设计系统包时可提供版本化生成模块；必须注明 token 格式/组件规范值类型版本。删除或重命名公共 token 是 API break。新增无冲突路径不改变已有消费名称；重复路径在生成时拒绝，不能通过新增 semantic 覆盖基础值。公共库可使用明确的 TOKENS 引用或声明角色合同。

错误信息示例：

```text
theme.json:24:17 /semantic/font_size/title
expected font_size reference, found duration: tokens.duration.fast
```

`check` 至少覆盖语法、值范围、引用、模式；JSON Schema 只能做结构校验。编辑器根据 schema 给固定字段提示，应用 token 的完整引用补全和跳转由后续工具读取生成元数据提供，不声称标准 JSON Schema 能完成跨字段引用推导。

安全与资源边界：初始输入上限 8 MiB、嵌套深度 64（根容器深度为 1）、token 数 65536（两层合计）、模式数 64（包含内置 light/dark）；超限报告输入位置，不崩溃。生成器不访问网络、不执行输入中的代码、不读取 `$schema` 指向的内容。分配失败返回错误并释放已分配资源。

空标量分组允许存在，但不产生 token，不能作为引用目标。包装器只允许在 token 最外层出现；`$value` 不再包含包装器，模式分支只接受直接值或引用。

### 10.1 应用主题分层

应用以 zenit 默认主题为底、只追加或覆盖少量 token 时，不复制 `default.json`（复制会随 zenit 更新漂移），而是叠加层：

```text
zenit-tokens generate default.json app.tokens.json [more.tokens.json ...] --out theme.gen.zig
zenit-tokens check    default.json app.tokens.json
zenit-tokens explain  default.json app.tokens.json semantic.color.zw_island_ground --mode dark
```

- 第一个文件是底层，其后按顺序合并；每层是一份完整语法的主题文件（`$version: 1`），只有底层必须有 `tokens`，overlay 可以只写 `semantic` 或 `$modes`。
- overlay 声明下层没有的路径时直接加入，分组跨层合并（overlay 可向底层的 `color.blue` 分组加档位）。新增的 semantic 名称和内置名称一样成为 `Values` 字段、`refs` 常量和 `.yss` / `ui.css` 名称：`semantic.color.zw_island_ground` 在 Zig 中是 `cx.tokens.tokens.color.zw_island_ground`，在 `.yss` 中写 `zw-island-ground`。
- 覆盖下层已声明的路径必须逐 token 显式标注，否则报错，并列出两处声明（`文件#JSON Pointer`）：

  ```json
  {"$version": 1, "semantic": {"color": {
    "accent": {"$override": true, "$value": {"$light": "#a23010", "$dark": "#e07050"}}
  }}}
  ```

  `$override` 只能为 `true`；它必须真的覆盖了下层的同一路径，且留在同一层级（`semantic.color.accent` 不能被 `tokens.color.accent` 覆盖），否则报错。覆盖后整个合并结果重新解析，下层引用该 token 的别名（包括组件角色 token，如 `switch_track_on`）一并跟随。
- `$modes` 同理：新增模式直接加入；与下层同名的模式需在该模式对象里写 `"$override": true`。
- token / 分组冲突、同层重复与单文件规则相同。诊断的偏移和 JSON Pointer 指向出错的那个文件；生成元数据的 `pointer` 在多层时写成 `文件#/json/pointer`（单文件保持 `/json/pointer`，生成结果逐字节不变）。`explain` 按 token 最终来源的文件追踪分支与引用。
- 构建接入：`zenit.generateThemeLayers(b, dep, &.{ zenit.defaultThemePath(dep), b.path("src/ui/theme/app.tokens.json") }, .{ .target = target, .optimize = optimize })`，结果交给 `wireThemeProvider` / `attachWithOptions(.theme_provider)`。单层时等价 `generateTheme`。
- 边界：dev preview 的主题热重载（`ui/theme_reload.zig`）仍只解析一个 JSON 文件；分层主题改动走重新构建。

## 11. 迁移顺序

| 阶段 | 工作 | 交付门槛 |
|---|---|---|
| A：独立生成器 | JSON/模式/引用/类型/元数据，规范值模块与默认 preset | 生成 Zig 可编译；错误定位、确定性输出、OOM 测试通过 |
| B：类型与解析接入 | provider 构建绑定、统一 TOKENS 引用与具体值、类别枚举、旧具名函数接口统一 | 自定义字号名可在 css/cva/sva 使用；错误类别编译失败 |
| C：组件与更新 | 内置 recipe 的直接 semantic 依赖、所有主题消费路径、overlay 通知、TypographyPatch | light/dark/custom mode 切换正确；保留 hover/variant；聚合不覆盖未声明字段 |
| D：真实迁移 | 当前三套主题、counter、Storybook 样式和组件调用点 | 解析后的全部旧 token 数值等价；四态截图精确一致；相关测试与 Storybook e2e 通过 |
| E：按需求扩展 | 局部主题、字体资源、窗口 source 辅助接口、其他值类别 | 每项有真实组件用例和独立性能/行为验收，不提前扩大 JSON 语言 |

默认 preset 从现有 theme.zig 的真实值迁移，不能根据颜色相同就随意引入语义别名。例如现有 high_contrast 的 button_primary_bg 与 accent 不同，不能把 light/dark 的偶然一致推广到所有模式。

枚举简写只查询应用实际生成的 token，不保留旧名称别名。迁移可以重命名和重新分类，但必须保持解析后的视觉值；官方间距尺度采用 space50/space100/space200。本文不改变已有 style literal ratchet 政策。

## 12. 必须验收的行为

- 自定义 `xLargeBlaBla` 和默认系统无关；不存在的 `.xxxl` 正确报错。
- `tokens = {}`、缺省 semantic、空类别可生成和构建；空类别的值类型由类别合同确定，不能通过读取“第一个 token 字段”推导。
- 两层相同类别/路径的重复定义、token 与分组路径冲突在生成时拒绝；分组可合并，不同类别可同名。
- refs 与 Values.tokens 均为统一结构；合法调整声明层级但保持类别/路径时，消费代码不变，无需区分基础与 semantic。
- 引用链、复合字段引用、直接 semantic 补充值都正确；不存在、反向依赖、跨类别和循环均定位到输入。
- 只有目标有 dark 分支的间接引用仍随主题变化；模式专属合法依赖不会被联合图误判为环。
- dark 缺省、自定义 fallback、未知条件、缺 light、条件和值混写、重复 JSON 键均符合语义。
- 数字单位和范围、颜色 alpha 顺序、未声明排版字段、复合分支默认值有固定回归用例。
- 同一引用用于 css、cva 的各层、sva 各 slot、具名函数、旧 recipe 和 Yix，解析结果一致。
- variant 来自 Signal，切换模式时 variant/hover 保持；恢复条件后无陈旧样式残留。
- 组件自己按窗口选择 variant 时，compound 继续按当前 variant 工作；独立组件可采用不同适配策略。
- 两个不同 token provider 的外部消费项目分别构建；共享规范类型实例，避免 module identity 错误。
- 不生成 system 字段或任何旧角色回退；内置 recipe 的缺失 semantic token 编译失败。
- source metadata 可关闭而不改变渲染结果；生成内容不随 JSON 对象顺序、机器路径或时间戳变化。

## 13. Panda 借鉴与取舍

采用材料/语义/recipe 分层、slot 共用变体、类别校验、引用和生成接口。保留 Zig 样式函数与响应式值，避免引入源码扫描式样式提取、本地/配置式 recipe 两套生成语义以及任意 CSS 选择器解释器。

Panda 的条件样式允许组件自行决定响应式行为；semantic 条件是能力而非必需架构。这里同样优先保留使用处选择。

参考：

- [Panda Tokens](https://panda-css.com/docs/theming/tokens)
- [Panda Slot Recipe](https://panda-css.com/docs/recipes/slot-recipes)
- [Panda Responsive variants](https://panda-css.com/docs/recipes/responsive-variants)
- [Panda Dynamic styling](https://panda-css.com/docs/styling/dynamic-styling)
- [Panda composite token regression tests](https://github.com/chakra-ui/panda/blob/802eb61ba7955f00a755401ff2ddbfac39a7c385/crates/pandacss_tokens/tests/from_config.rs#L387)

当前接入位置：`src/ui/css.zig` 的 ScaleType/token/usesTokens，`src/ui/view.zig` 的样式计划与文本合并，`src/ui/core.zig` 的 theme signal/setTheme，`src/ui/recipe.zig` 的旧 recipe，`build.zig` 的模块实例绑定。本文是这些后续实现的共同合同。
