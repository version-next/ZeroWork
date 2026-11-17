# tools/arch — 架构护栏（check-arch）

依据 `docs/ui-revamp/ARCHITECTURE_PLAN.md` §4.1–4.3（分层与 import 规则）、§6.3（test_id 稳定性）。
纯 Zig 实现，编译目标为 host，不依赖 zenit 或仓库里的任何模块。

| 文件 | 作用 |
|---|---|
| `check_arch.zig` | 入口、子命令、基线比对、统计 |
| `rules.zig` | `rules.zon` 的数据模型、段级 glob、分层判定、矩阵判定 |
| `scan.zig` | 基于 `std.zig.Tokenizer` 的扫描：`@import`、标识符序列、`test` 块、路径归一 |
| `test_ids.zig` | test_id 提取与 e2e 交叉引用 |
| `rules.zon` | 全部规则数据（路径 → 层、模块 → 层、矩阵、标识符规则、test_id 上下文） |
| `baseline.txt` | import / 标识符违规基线 |
| `test_ids.baseline.txt` | 源码定义的 test_id 基线 |
| `test_ids.e2e_used.txt` | 被 e2e 使用的 test_id（不可改） |
| `test_ids.e2e_dangling.txt` | e2e 悬空 test_id 的欠账基线（只能缩短） |
| `test_ids.e2e_ignore.txt` | e2e 里形似 test_id、但不按悬空处理的字符串（每条写明理由） |

## 用法

```sh
zig build check-arch                 # = check_arch all：import 检查 + test_id 检查（先跑 test-arch）
zig build test-arch                  # 只跑工具自身的单测
zig build check-arch -Darch-args="imports"
zig build check-arch -Darch-args="imports --prune"
zig build check-arch -Darch-args="test-ids --verbose"
zig build check-arch -Darch-args="count-tests src/root.zig src/tests_ui.zig"
zig build check-arch -Darch-args="list-imports src/features/workspace/view/workspace.zig"
```

`-Darch-args` 按空格切分后原样传给工具（路径不能含空格）。build 步骤把 cwd 设为仓库根，
默认路径都相对仓库根。

| 子命令 | 说明 |
|---|---|
| `all`（默认） | `imports` + `test-ids`；任一失败则退出码 1 |
| `imports` | 分层 / 跨 feature / 标识符检查，对比 `baseline.txt`；`--prune` 删除已消失的条目；`--update-baseline` 重写基线 |
| `test-ids` | 提取源码 test_id，校验基线里的每一条仍存在；校验 e2e 脚本没有新增悬空 test_id（见「e2e 悬空引用」）；`--prune` 从欠账基线删掉已修好的条目；`--update-baseline` 重写 `test_ids.baseline.txt`、`test_ids.e2e_used.txt` 与欠账基线 |
| `count-tests ROOT…` | 沿相对 `@import` 闭包静态统计 `test` 块（V-10 的后备口径） |
| `list-imports FILE…` | 打印分词器提取到的每一处 `@import`（调试、V-9 核对） |

公共选项：`--rules`、`--baseline`、`--ids-baseline`、`--e2e-used`、`--verbose`。
退出码：0 通过；1 有新增违规或基线 id 丢失；2 用法错误或规则文件错误（含“某层没有 allow 条目”）。

接线：P0、P1 只是独立步骤。P2 起主程序 `exe` 与各测试编译步骤（`test`、`test-bmc`、`test-local`、`test-appearance`、
`test-ui`、插件夹具测试）与 `check-yix` 并列依赖 `check_arch_gate`——一份固定参数（默认 `all`）、先跑 `test-arch` 的独立运行，
所以新增违规或基线 id 丢失会让构建失败；`-Darch-args` 只影响顶层 `check-arch` 步骤（不会在普通构建里重写基线）。
无改动时额外耗时约 0.3 秒（工具运行；`test-arch` 命中缓存）。

## 检查做了什么

1. 遍历 `rules.zon` 的 `roots`（`src`）下扩展名在 `extensions`（`.zig`、`.yix`）里的文件，
   跳过 `skip`（生成物 `_*.yix.zig`、`_*.yss.zig`）。
2. 用 `std.zig.Tokenizer` 分词，找 `@import ( "字面量"`。注释与字符串里的 `@import` 不会被误认。
   以 `.zig` / `.zon` / `.yix` / `.yss` 结尾的是文件，相对来源文件所在目录归一成仓库路径；其余是具名模块。
3. 来源与目标按 `layers` 定层（第一个匹配的条目生效）；具名模块按 `modules` 定层。
   定不了层的记为 `unclassified-source` / `unclassified-target` / `unclassified-module` 违规，保证规则表完整。
4. 判定（每条 import 至多一条违规）：
   - 矩阵：来源层的 `allow` 列表里没有目标层 → `layer:<来源层>-><目标层>`。
     测试代码（`test_files` 命中的文件，或非测试文件里 `test` 块内的 import）额外允许 `test_allow` 中的层
     （本 feature 任意层、`shared_testing`、`core`、`platform` 等；§4.2 对测试放宽）。
   - 跨 feature：目标带 feature 且与来源的 feature 不同，目标层又不在 `cross_feature_allowed`（门面）里 → `cross-feature`。
     `cross_feature_exempt`（入口、聚合根）不受此限。测试代码同样受此限（§4.2：仍不能 import 其他 feature 的内部文件）。
5. 标识符规则：`idents` 中 `files` 命中、不在该条 `skip` 里的非测试文件里，搜索禁用 token 序列（`ui.Node` = 标识符 `ui`、`.`、
   标识符 `Node`），`test` 块内不检查。规则名 `ident:<name>`，目标是被禁用的序列。两个可选项：
   - `reads_only = true`：序列后紧跟赋值 `=` 的不算（只拦“读”，不拦“写”）；
   - `per_function = true`：目标写成 `序列 @ 所在函数名`，基线按函数记——同一文件里另一个函数新写的同类代码不会被已有条目吞掉。
   `no-test-id-read` / `no-test-id-rewrite`（usage-b5f-ai-testid）用这两项：生产代码不得读节点的 test_id（按 id 查节点、
   按 id 决定样式或行为），也不得在挂载后改名（`test_id_owned`）；给节点命名（`… .meta.test_id = …`）不算。预览、验收程序、
   `shared/testing`、test-mode 路由（`*_test_routes.zig`）与测试夹具在 `skip` 里。现存的读法进基线（AI 目录为 0），只能缩短。
6. 术语表护栏（`terms`，docs/ui-revamp/GLOSSARY.md）：`terms.files` 命中、不在 `terms.skip` 里的非测试文件中，
   用户可见字符串出现 `terms.forbid` 的禁用词即违规，规则名 `term:<禁用词>`，目标是应改用的说法。`.zig` 只看非测试代码的
   字符串字面量（注释、标识符、`test` 块不算）；`.yix` 模板文字不是 Zig 字面量，按行扫描并跳过 `//` 注释行。
   `terms.allow` 是带理由的白名单（文件 glob + 禁用词）。与 import 违规共用 `baseline.txt`，同样只能缩短。
7. 违规 key = `规则 来源文件 → 目标`（不含行号）。与 `baseline.txt` 比对：基线外的 key 视为新增 → 打印 key 与每处 `文件:行号`，退出码 1；
   基线里有、源码里已消失的 key 只提示，不失败。
8. 末尾打印按规则类别、按规则、按来源层汇总的违规条数（按基线条目计）。

## rules.zon 格式

```zig
.{
    .roots = .{"src"},
    .extensions = .{ ".zig", ".yix" },
    .skip = .{ "**/_*.yix.zig", "**/_*.yss.zig" },
    .test_files = .{ "**/*_tests.zig", "src/**/tests/**" },
    .modules = .{ .{ .name = "ui", .layer = "zenit_ui" }, … },
    .layers = .{ .{ .pattern = "src/features/{feature}/**/model/**", .layer = "model" }, … },
    .allow = .{ .{ .from = "view", .to = .{ "std", "zenit_ui", "model", … } }, … },
    .test_allow = .{ … },
    .cross_feature_allowed = .{"facade"},
    .cross_feature_exempt = .{ "entry", "shared_ui_tests" },
    .idents = .{ .{ .name = "view-no-io", .files = .{…}, .forbid = .{ "std.Thread", … } }, … },
    .test_ids = .{ .contexts = .{…}, .exclude_suffixes = .{…}, .e2e_dirs = .{"e2e"}, .e2e_extensions = .{ ".ts", ".mts" } },
}
```

glob 按 `/` 分段匹配：`*` 段内通配；`**` 匹配零个或多个整段；`{feature}` 匹配一个整段，
并把“从开头到该段”的路径记为 feature 键（如 `src/features/settings`、`src/plugins/bmc_ikvm`）。
子域（`features/connections/wizard/…`）的 feature 仍是 `connections`。

工具启动时自检：`layers`、`modules`、`allow.to`、`test_allow` 里出现的每个层名都必须有自己的 `allow` 条目，
否则退出码 2（防止拼错层名导致静默放行或静默拒绝）。

### 层

| 层 | 布局（§5.1，P1 搬迁后） | 过渡（插件尚未分层，P5 删除） |
|---|---|---|
| `entry` | `src/{main,root,preview,acceptance}.zig`、`src/tests_*.zig`（含 `tests_local.zig`） | — |
| `runner` | `features/<f>/**/preview/**`、`features/<f>/**/tests/acceptance/**`、`plugins/<p>/**/{preview,acceptance}/**`、`src/<core 或 platform>/**/acceptance/**`：由 `src/preview.zig` / `src/acceptance.zig` 选中的程序入口，可用 build 注入模块与 platform，仍受跨 feature 限制 | — |
| `shared_ui_tests` | `src/shared/ui/{tests,preview}/**`：跨 feature 的主题/材质/按钮测试与预览（move-map 裁决原则 3），在 `cross_feature_exempt` 里 | — |
| `app` | `src/app/**` | — |
| `facade` | `features/<f>/mod.zig`、`features/<f>/<sub>/mod.zig`、`plugins/<p>/mod.zig` | `plugins/<p>/{non_ui,plugin}.zig` |
| `model` / `view_model` / `view` / `host` / `tests` | `features/<f>/**/{model,view,host,tests}/**`（`model/view_model.zig` 单列）；`plugins/<p>/**/tests/**` 也是 `tests` | — |
| `shared_base` / `shared_ui` / `shared_testing` | `src/shared/{base,ui,testing}/**` | — |
| `platform` | `src/platform/**` | — |
| `core` | `src/{proto,vt,transfer,local,host,ai,config,update}/**`（D1 = A），含其下的 `tests/`（测试代码放宽） | — |
| `legacy_plugin` | — | `plugins/<p>/**` 中未分层的文件（带 feature） |
| `plugin_registry` | — | `src/plugins/*.zig`（`linked_plugins`、`application_plugins`） |

目标层（仅作 import 目标）：`std`（含 `builtin`、`root`）、`zenit_ui`（`ui`、`icon_ir`）、`zenit_app`、
`native_gen`（translate-c 生成的 `generated_*`）、`build_options`（`application_options`、多路复用根的选择项 `root_select` 等 build 注入的模块）。

矩阵要点：
- `core` 不得 import `zenit_ui`、`zenit_app`、`legacy_plugin`、`plugin_registry`、`shared_testing`（`test` 块除外）与任何 feature 层。
- `legacy_plugin` 权限同 host，但不得依赖 features 的内部文件（只能经门面）；插件之间只能经门面。
- `tests` 与 `runner` 可以 import 本插件的 `legacy_plugin` 文件（插件自己的测试与预览；跨插件、跨 feature 仍报 `cross-feature`），P5 插件分层后删除。
- 测试代码（测试文件与 `test` 块）额外允许 `test_allow`：本 feature 任意层、`shared_testing`、`core`、`platform`、`zenit_app`、`native_gen`。
- `platform` 只能 import std、`native_gen`、`build_options`、platform、shared_base。

### P1 删除过渡条目（已完成）

P1 最后一个搬迁提交（root-core）已删除 `src/ui/**`、`src/config/settings_*` 等界面文件、`src/*_tests.zig`、`src/*.zig`、
`src/testing/**` 的过渡条目，以及 `legacy_ui`、`legacy_shared_ui`、`legacy_tests` 三个层名；`cross_feature_exempt` 去掉了 `legacy_tests`。
搬迁过程中每个 `refactor(move)` 提交都用 `-Darch-args="imports --update-baseline"` 重建了基线，并在提交说明里写明条数与按规则的增减
（P0 的 122 条 → P1 结束时的条数见 `docs/ui-revamp/baselines/tests.md` 与阶段报告）。

剩下的过渡条目只服务于插件（`src/plugins/*.zig` → `plugin_registry`、`plugins/<p>/{non_ui,plugin}.zig` → 门面、其余 → `legacy_plugin`，
以及 `idents` 里的 `src/plugins/*/view_model.zig`）。P5 把插件按 model/view/host 分层后删除这些条目，并从 `allow` 中移除
`legacy_plugin`、`plugin_registry`；`rules.zig` 的 “layers/matrix: plugins transitional layout (P5)” 两个测试随之删除或改写。
## 基线维护（只能缩短）

- 首次生成：`-Darch-args="imports --update-baseline"`、`-Darch-args="test-ids --update-baseline"`。
- 修掉违规后：`-Darch-args="imports --prune"`，只删除已消失的条目，绝不加入新条目。
- **日常不得用 `--update-baseline` 或手工编辑来吞新增违规。** 新增违规的正确处理是改 import；
  确属规则不合理的，改 `rules.zon` 并在提交说明里写明理由，由 T 泳道合并。
- 例外（整体重建）只在 P1 搬迁改路径、或规则表有意调整时进行，并在同一提交里说明条数变化。
- 基线文件格式：`#` 开头为注释，空行忽略；其余每行一条，排序、去重，不含行号。

## test_id 基线

### 提取规则

候选字面量：Zig 字符串字面量（`.yix` 同样分词）内容为点分小写 id —— 至少两段，段字符 `[a-z0-9_-]`，首段以字母开头。
- 含 `{` 的格式串（`"ai.session.row.{d}"`、`"ai.session.{s}.{d}"`）取 `{` 之前的部分，必须以 `.` 结尾，记作前缀 `prefix:ai.session.row.`；
  `"group.broadcast.member.{d}.select"` 只记前缀 `prefix:group.broadcast.member.`（后缀丢失）。
- 以 `.` 结尾的字面量（`"settings.key.row."` 传给 `stableId`、`"legacy.auth." ++ @tagName(k)`）记作前缀。
- 以 `exclude_suffixes`（`.zig`、`.json`、`.png` …）结尾的不算。

两遍：
1. **确定定义点**：`rules.zon` `test_ids.contexts`（`test_id`、`testId`、`stableId`，以及共享面板头部 / 关闭按钮 / `W.Empty` 的部件 id 参数 `headerTestId`、`closeTestId`、`descriptionTestId` 等）标识符之后、同一表达式内的候选字面量
   （到深度 0 的 `;` / `,`、括号闭合、或非 `.{` 的语句块 `{` 为止；`fn stableId(…)` 声明本身跳过）。覆盖：
   `x.meta.ownership.meta.test_id = "…"`、`.{ .test_id = "…" }`、`test_id = try std.fmt.bufPrint(&b, "…{d}", …)`、
   `std.fmt.comptimePrint`、`allocPrint`、`"…" ++ …`、`stableId(scope, "settings.field.", key)`、Yix 的 `testId="…"`。
   由此得到“一级前缀集合”（如 `ai`、`settings`、`wizard`）。
2. **松散收集**：非测试代码里任何候选字面量，只要一级前缀在集合中就收入。覆盖经数组、元组、参数间接传入的 id
   （`.{ "ai.stop", "停止" }` 后面 `test_id = item[0]`、`control_hint.mount(…, .{ .id = "…" })` 等）。

测试代码（`test_files` 命中的文件，以及 `test` 块）里的字面量**不收**：其中大多是断言用的具体化动态 id
（如 `"ai.session.row.3"`）或测试夹具自造的 id，收进来会把测试实现细节冻结为“公开接口”。数量会打印出来（当前 949 个）。
取舍理由：基线要回答“源码定义了哪些 id”；源码侧已按“宁多勿漏”放宽（第二遍），测试侧引用的 id 若是真实 id，
本来就能在源码侧找到定义。

### 已知漏报 / 误报

- 漏报：完全由运行期数据组成、没有任何字面量前缀的 id（例如 `record.testId()` 返回的缓冲区内容，其前缀在别处 `bufPrint`
  时已作为前缀收录，但若前缀本身来自变量就收不到）；只以后缀字面量出现的部分（`stableId(scope, field.key, ".timing")` 的 `.timing`）。
- 漏报：一级前缀从未出现在确定定义点里的 id（第二遍只认已知一级前缀）。
- 误报：一级前缀恰好与 id 相同的非 id 字符串（例如一级前缀同为 `ai`、`settings` 的配置键或日志键）会被收入。只会让基线多出条目，
  代价是这些字面量删改时也要同步基线，可接受。
- 前缀粒度：`prefix:ai.`、`prefix:wizard.` 这类宽前缀来自 `"ai." ++ …` 这种写法，只能保证前缀仍存在。

### 校验

- `check_arch test-ids`：重新提取，基线里的每一条仍在当前提取结果中，否则失败并列出缺失项（被 e2e 使用的另行标注）。
  源码新增的 id 只打印数量（`--verbose` 打印明细），不失败。
- 确需删除或改名（本工作流内原则上不改名，D12）：在同一提交里修改 `test_ids.baseline.txt` 并写明理由。

### e2e 交叉引用

- 扫描 `e2e/*.ts`、`e2e/*.mts`（`test_ids.e2e_dirs` / `e2e_extensions`，含子目录）中 `'…'`、`"…"`、`` `…` `` 字符串，
  跳过 `//` 与 `/* */` 注释；模板串截到第一个 `${` 当作前缀。`e2e/*.py` 等其他脚本当前不扫描（可加进 `e2e_extensions`）。
- 求交：e2e 字符串与源码静态 id 完全相等 → 记该 id；否则若以某个源码前缀开头 → 只记**最长**的那个前缀。
- 结果写进单独文件 `test_ids.e2e_used.txt`（而不是在基线里加标记，便于 diff 与人工审阅）：这些 id / 前缀不可改名、不可删除。
  `test-ids` 检查时，基线缺失项若同时在 e2e 清单里，会额外标注。e2e 新引用的源码 id 只打印数量，重新生成时并入。

### e2e 悬空引用

`test-ids`（因此 `check-arch`、应用与全部测试的构建）还反过来查：e2e 脚本里引用的 test_id 在源码里是否还存在。
界面改版删掉或改名一个 id 之后，脚本里的旧 id 不会让任何编译失败，只会在跑到那一步时超时——这项检查让它在构建时就报错。

- 候选：与上面相同的 e2e 字符串扫描，取形似 id（或模板串 / 以 `.` 结尾的前缀）且**一级前缀属于源码 test_id**（`sidebar`、
  `settings`、`ai` …）的字符串；别的命名空间（配置键、主机名、文件名）不管。
- 判定“还在”：与源码静态 id 相等；或以某个**至少两段**的运行期前缀开头（`settings.field.`）；或匹配某个格式串通配
  （源码 `"wizard.{s}.error"` → `wizard.*.error`）。也认“按上述规则存在的 id ++ 源码里的某个后缀字面量”：部件 id 常这样拼出来
  （`scopedId(scope, id, ".popover")`、`id ++ ".header"`），如 `bmc.boot` ++ `.popover`。单段前缀（`ai.`、`wizard.`，多半来自 `startsWith` 判断或过宽的拼接）
  不能证明任何具体 id 存在，不作数。e2e 里的前缀候选（`` `sidebar.host.${i}` ``）只要求源码里有以它开头的 id / 前缀 / 通配。
- 其余即“悬空”，按 `脚本 → id` 记。不在 `test_ids.e2e_dangling.txt` 里的悬空引用是**新增**，检查失败（退出码 1）。
- `test_ids.e2e_dangling.txt` 是欠账基线，只能缩短：脚本改成断言当前真实契约后运行
  `zig build check-arch -Darch-args="test-ids --prune"`。目标是清零：回归清单
  （`e2e/regression/manifest.json`）里 `runnable` 的脚本应当先清，留到最后的只能是当前无法运行、因而无法验证改法的脚本
  （需要真实远端 / 私有凭据 / 人工在场等，清单里有对应的排除理由）。
- `test_ids.e2e_ignore.txt`：脚本有意引用的、源码里不存在的字符串——断言某个 id **已经不存在**（回归用例），或根本不是
  test_id（如 `local.zerowork.*` 临时 bundle id）。每行一个，前面用 `#` 注释写明理由。其中某条不再悬空（源码里又有了，
  或没有脚本再引用）时检查失败并提示删除，避免清单腐烂。
- 不扫描 `e2e/*.py`（与交叉引用相同）。

## 测试计数（count-tests）

从给定根文件出发，沿**相对路径**的 `.zig` import 闭包统计 `test` 块：具名（`test "…"`）、decltest（`test name`）、匿名（`test {}`）。
这是**上界**：Zig 只收集被语义分析到的文件里的测试，顶层 `const x = @import(…)` 若从未被引用，该文件的测试不会进测试二进制；
具名模块（`ui`、`zenit_app`）不跟进；`-Dtest-filter` / 步骤内置过滤（如 `test-bmc` 的 `"BMC "`）不考虑。
用作“用例数不减少”的辅助判据，主判据是测试二进制自己打印的计数，见 `docs/ui-revamp/baselines/tests.md`。

## V-9：`.yix` 能否用 `std.zig.Tokenizer` 提取 `@import`

**结论：成立。** `.yix` 的文件头与组件体是 Zig 语法，`@import` 只出现在 Zig 部分；模板标签、属性与文本只会产生
无关 token。模板文本里的撇号 / 不成对引号会让分词器在当行产生 invalid token，`//` 会把当行剩余部分当注释，
两者都在换行处恢复，不影响其他行的 `@import`。

验证：
- 工具单测（`scan.zig`，3 个）：`examples/yix_counter/counter.yix` 全文；`src/ui/components/alert/alert.yix` 的文件头原文
  加上人为构造的对抗性模板文本（撇号、引号、URL 里的 `//`）；`tests/yix/review_reactive.yix` 的单行组件写法与模板属性里的 `@import`。
- 一次性比对：`list-imports` 扫 `vendor/zenit/**/*.yix` 全部 40 个文件，提取 101 处，与
  `grep -oE '@import\("[^"]*"\)'` 的结果逐条（文件 + 目标）完全一致；文件中 `@import(` 出现次数也是 101。

不需要改扫生成的孪生文件。局限：若将来有人在模板文本的同一行先写不成对的 `"` 再写 `@import`，该处会漏报（Zig 部分不会这样写）。

## 已知局限

- 只认字面量 `@import("…")`；`@import` 的参数若是 comptime 计算的字符串则不检查（仓库里没有）。
- 标识符规则按 token 序列匹配，不做名字解析：`const U = ui; U.Node` 这类别名绕得过去；`std.Io.Dir` 之类经别名
  （`const Dir = std.Io.Dir;` 后再用 `Dir`）只在别名定义处命中一次。
- `features/<f>/` 下不在 `model/view/host/tests` 里、也不是 `mod.zig` / `preview.zig` 的文件会报 `unclassified-source`，属有意为之。
- 标识符规则按路径生效：`view-no-io` 作用于 features/plugins 下的 `view/`，`view_model-reactive-subset` 作用于 `model/view_model.zig` 与过渡的 `src/plugins/*/view_model.zig`。
