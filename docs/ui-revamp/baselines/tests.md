# 测试计数基线（P0，V-10）

用于 P1 起各阶段“用例数不减少、测试名不变”的复核。依据 `docs/ui-revamp/ARCHITECTURE_PLAN.md` §6.2 P0 第 4 条、§9.2 V-10。

## 基线对应的源码

- 源码 commit：`7034789d`（`build(yix): 扩大 Yix 孪生检查范围到 src 与 tools/mockups…`）。
  T0-B 的提交只新增 `tools/arch/**`、`docs/ui-revamp/baselines/**` 并在 `build.zig` / `build.zig.zon` 里加 `check-arch` 接线，
  不改 `src/**`，所以本基线同样适用于 T0-B 合并后的提交。
- 环境：Zig 0.17.0，macOS（Apple Silicon），全部命令在无网络沙箱包装 `zw-nonet.sh` 内执行。
- 日期：2026-11-11。

## 命令

```sh
zig build test    -j2 --summary all     # 耗时约 4 分 50 秒
zig build test-ui -j2 --summary all     # 耗时约 8 分 30 秒
```

## 结果

| 步骤 | 聚合根 | 运行期总数 | 通过 | 跳过 | 失败 | 静态 `test` 块（count-tests 上界） |
|---|---|---:|---:|---:|---:|---:|
| `test` | `src/root.zig` | 2,536 | 2,524 | 11 | 1 | 2,560（具名 2,525 + 匿名 35；闭包 677 个文件） |
| `test-ui` | `src/transfer_panel_tests.zig` | 2,756 | 2,734 | 19 | 3 | 2,780（具名 2,736 + 匿名 44；闭包 806 个文件） |

`test` 步骤另外依赖 3 个原生 mock 回归（`credentials-native-mock`、`password-reveal-native-mock`、`data-scope-lock-tests`），
均为 `success`，它们不是 Zig `test` 块，不计入上表。

其他聚合根的静态上界（未在本轮运行，仅供参考）：

```
count-tests：沿相对 @import 闭包统计 `test` 块（静态上界，见 README）
  根文件                                   文件数   具名   decltest  匿名   合计
  src/root.zig                                677   2525         0    35   2560
  src/transfer_panel_tests.zig                806   2736         0    44   2780
  src/appearance_tests.zig                    536   1638         0    20   1658
  src/bmc_tests.zig                           548   1935         0    20   1955
  src/update_tests.zig                        523   1560         0    19   1579
  src/plugin_fixture_tests.zig                518   1553         0    19   1572
  src/appearance_font_tests.zig                 4     11         0     1     12
```

（`test-bmc`、`test-update`、`test-plugin-fixture` 在 `build.zig` 里带内置过滤串 `"BMC "`、`"update "`/`"settings page map"`、`"fixture "`，
静态上界与实际运行数差距会很大，只能用于同口径前后对比。）

### 原始统计行

`zig build test -j2 --summary all`：

```
2524 passed; 11 skipped; 1 failed.
test
+- run unit and contract tests failure
error: process exited with code 1
failed command: ./.zig-cache/o/6d0c17496339d8db8528b6cad831020e/unit-tests

Build Summary: 23/25 steps succeeded (1 failed)
```

`zig build test-ui -j2 --summary all`：

```
2734 passed; 19 skipped; 3 failed.
test-ui
+- run transfer-panel and layout tests failure
error: process exited with code 1
failed command: ./.zig-cache/o/e39f83a4433bda4b122939798cbe9107/ui-tests

Build Summary: 17/19 steps succeeded (1 failed)
```

每个用例另有一行 `序号/总数 名称...OK|SKIP|FAIL`，例如 `2536/2536 ai.mcp_oauth.test.v0.4 extensions OAuth token cache supports more than sixteen servers...OK`。

## 失败清单

### 已知、与本轮无关（只记录，不修）

1. `fetch_url` 系统代理：需要网络，被无网络沙箱拦截。`test` 与 `test-ui` 都包含它。

   ```
   799/2536 ai.fetch_url_transport_tests.test.fetch_url std.http production route fetches through the configured system proxy...fetch result code=not_allowed stage=2 status=0 sent=false
   FAIL (TestUnexpectedResult)
   ~/.local/share/zig/0.17.0/lib/std/testing.zig:584:14: 0x10073f583 in expect (test)
       if (!ok) return error.TestUnexpectedResult;
                ^
   src/ai/fetch_url_transport_tests.zig:93:5: 0x1015dcb8b in test.fetch_url std.http production route fetches through the configured system proxy (test)
       try std.testing.expect(result.code == .ok and result.request_sent and result.http_status == 200);
   ```

   （`test-ui` 中为 `501/2756`，同一断言。）

2. `connection_host` “keeps a failed original owner…”：在原 HEAD 上就失败。只在 `test-ui` 中。

   ```
   2229/2756 connection_host_tests.test.connection host keeps a failed original owner while a foreign challenge waits and transfers only after explicit close...FAIL (TestUnexpectedResult)
   ~/.local/share/zig/0.17.0/lib/std/testing.zig:584:14: 0x1030c1ed7 in expect (test)
       if (!ok) return error.TestUnexpectedResult;
                ^
   src/connection_host_tests.zig:481:5: 0x105affbbb in test.connection host keeps a failed original owner while a foreign challenge waits and transfers only after explicit close (test)
       try std.testing.expect(f.host.authentication.isVisible());
   ```

### 新发现：疑似时序不稳定（不在上述两条之内）

3. `test-ui` 全量运行时失败，单独过滤重跑一次通过：

   ```
   2375/2756 ai_local_tools_tests.test.real group active child observes outer request stop while worker is blocked in execute...FAIL (ApprovalMissing)
   src/ai_local_tools_tests.zig:1033:54: 0x10585ecdf in test.real group active child observes outer request stop while worker is blocked in execute (test)
       const approval = bridge.pendingApproval() orelse return error.ApprovalMissing;
   ```

   重跑：`zig build test-ui -j2 --summary all -Dui-test-filter="real group active child observes outer request stop"` →
   `25/39 ai_local_tools_tests.test.real group active child observes outer request stop while worker is blocked in execute...OK`、`All 39 tests passed.`
   该测试驱动真实 worker 线程（“worker is blocked in execute”），全量运行时与其他测试并发、负载高，推测为时序竞争。
   本包未改任何 `src`，不修；建议另开问题跟踪。复核时若它再次失败，按“已知不稳定”对待，但须单独重跑确认通过。

### 跳过的用例（均为需要真实 VM / 网络 / 外部环境的可选用例）

`test` 11 个：`ai.plugin_gateway_live_tests` 2、`transfer.sftp_engine` 2、`ai.lifecycle_runtime_tests` 1、`sftp_directory_recovery_tests` 1、
`file_transfer_fault_native_tests` 2、`file_transfer_active_fin_native_tests` 1、`ai_attached_service_tests` 1、`ui.ai_lifecycle_controller` 1。

`test-ui` 19 个：上面前 5 个，加 `shared_transfer_native_tests` 3、`wizard_test_progress_tests` 1、`sftp_resume_native_tests` 4、
`transfer_engine_mux_tests` 1、`file_transfer_runtime_tests` 1、`file_workspace_controller_tests` 1、`sftp_adapter_tests` 1、
`file_authentication_tests` 1、`file_transfer_host_tests` 1。

## V-10 结论

**`--summary all` 本身不成立；替代口径成立。**

- `test`、`test-ui` 两个步骤都不是 `b.addRunArtifact(<test compile>)`，而是把测试二进制复制进 `WriteFiles`（旁边放
  `zw_ipc.so` 等共享库）后用 `std.Build.Step.Run.create` + `addFileArg` 运行。构建器因此不走测试协议，
  `--summary all` 的步骤树里只有 `run unit and contract tests failure` / `success`，**没有** `N pass, M skip (T total)`。
  （对照：走 `addRunArtifact` 的 `test-arch` 会显示 `run test 24 pass (24 total)`。）
- 测试二进制在非协议模式下由默认 test runner 自己输出计数，stdout/stderr 继承到终端：
  - 每个用例一行：`序号/总数 名称...OK|SKIP|FAIL`，总数即该步骤的用例总数；
  - 末尾一行：全部通过时为 `All N tests passed.`，否则（有跳过或失败）为 `N passed; M skipped; K failed.`（`lib/compiler/test_runner.zig:327-331`）。
  这些输出在有失败时同样完整，可靠地给出总数 / 通过 / 跳过 / 失败。
- 后备口径：`zig build check-arch -Darch-args="count-tests <根文件>…"` 静态统计聚合闭包内的 `test` 块，是上界
  （本次 `test` 2,560 vs 实际 2,536，`test-ui` 2,780 vs 2,756，差 24 个），不需要运行测试。

## 之后各阶段怎样复核“用例数不减少”

1. 每个改动测试归属或搬迁测试文件的包（P1 搬迁、P2 拆 `main.zig`、P3/P5 改测试），合并前在沙箱内运行：

   ```sh
   zig build test    -j2 2>&1 | tee test.log    | grep -E '^[0-9]+ passed;|^All [0-9]+ tests passed'
   zig build test-ui -j2 2>&1 | tee test-ui.log | grep -E '^[0-9]+ passed;|^All [0-9]+ tests passed'
   zig build check-arch -Darch-args="count-tests src/root.zig src/transfer_panel_tests.zig"
   ```

   （P1 之后 `test-ui` 的聚合根改为 `src/tests_ui.zig`，`count-tests` 的参数随之调整。）
2. 判据：
   - 运行期总数 = 通过 + 跳过 + 失败，**不小于**本基线（`test` 2,536、`test-ui` 2,756），除非提交说明逐条列出删除的测试及理由；
   - 失败只能是本文“失败清单”里列出的条目；
   - 静态上界不小于本基线（`test` 2,560、`test-ui` 2,780）；运行期总数与静态上界的差值变化超过 ±5 时要查明原因
     （常见原因：被聚合的文件不再被引用，测试静默掉出二进制）。
3. 测试名不变：`-Dtest-filter` / `-Dui-test-filter` 依赖测试名。可以把两次运行的 `序号/总数 名称...` 行去掉序号、排序后 diff：

   ```sh
   sed -E 's#^[0-9]+/[0-9]+ ##; s#\.\.\.(OK|SKIP|FAIL).*##' test.log | grep -E '\.test(\.|_)' | sort > names.txt
   ```

   名称前缀是测试所在文件的模块路径（如 `ai.fetch_url_transport_tests.test.…`、`ui.overlay_anchor.test.…`），
   **搬迁文件会改变这部分前缀**；比对时只比较 `.test.` 之后的测试名本身，前缀变化按 move-map 核对。
4. 更新本文：每个阶段结束时追加一节“阶段 Pn 复核”，记录 commit、两步骤的统计行与静态上界。

## 阶段 P0 复核（P0 结束时的有效基线）

S1 合入并把 `src/shared/testing/ui_kit.zig` 接到 `test-ui` 聚合根之后，`test-ui` 多出 7 个用例（6 个 `ui_kit ` 具名用例 + 1 个匿名聚合块）。
**P1 起以本节的数字为准。** 数据来自 V1 合并前在其工作树内的全量运行（树内容与集成分支合并提交一致，tree `479e994a`）。

| 步骤 | 运行期总数 | 通过 | 跳过 | 失败 | 静态上界（count-tests） |
|---|---:|---:|---:|---:|---:|
| `test` | 2,536 | 2,524 | 11 | 1 | 2,560 |
| `test-ui` | 2,763 | 2,742 | 19 | 2 | 2,787 |

- 统计行原文：`2524 passed; 11 skipped; 1 failed.`、`2742 passed; 19 skipped; 2 failed.`
- 失败只有“失败清单”中已知的两条：`fetch_url` 系统代理（`test` 799/2536；`test-ui` 同一断言）与
  `connection_host` “keeps a failed original owner…”（`test-ui` 2226/2763）。
- 上文第 3 条疑似不稳定的 `ai_local_tools_tests`“real group active child observes outer request stop…”在 S1、V1 两次合并前的全量运行中都通过，
  三次全量运行里失败一次，继续按“已知不稳定”对待。

## 阶段 P1 复核

P1 目录搬迁（13 个 `refactor(move)` 提交，`0a37995d`…`d60d8579`）、补构建步骤（`74717f2c`）与 `ThemePublication` 拆分（`b9b275fe`）之后，
在 `b9b275fe` 上于无网络沙箱内全量运行（Zig 0.17.0，2026-11-12）。搬迁过程中另在 `settings`（`9dcae628`）与 `ai`（`d3a22334`）
两个提交之后各跑过一次全量 `test` / `test-ui`，结果与本节相同。

聚合根改名：`test-ui` 的聚合根由 `src/transfer_panel_tests.zig` 改为 `src/tests_ui.zig`；另有 `src/tests_appearance.zig`、
`src/tests_font.zig`、`src/tests_bmc.zig`、`src/tests_update.zig`、`src/tests_plugin_fixture.zig`（原 `appearance_tests`、
`appearance_font_tests`、`bmc_tests`、`update_tests`、`plugin_fixture_tests`）。步骤名、`-Dtest-filter` / `-Dui-test-filter` 与内置过滤串不变。

| 步骤 | 聚合根 | 运行期总数 | 通过 | 跳过 | 失败 | 静态上界（count-tests） |
|---|---|---:|---:|---:|---:|---:|
| `test` | `src/root.zig` | 2,536 | 2,524 | 11 | 1 | 2,560 |
| `test-ui` | `src/tests_ui.zig` | 2,763 | 2,742 | 19 | 2 | 2,787 |
| `test-appearance` | `src/tests_appearance.zig` | 1,621 | 1,615 | 5 | 1 | 1,658 |
| `test-bmc` | `src/tests_bmc.zig` | 426 | 426 | 0 | 0 | 1,955 |
| `test-update` | `src/tests_update.zig` | 8 | 8 | 0 | 0 | 1,579 |
| `test-plugin-fixture` | `src/tests_plugin_fixture.zig` | 24 | 24 | 0 | 0 | 1,572 |
| `test-local` | `src/tests_local.zig`（5 个二进制） | 28 / 1,570 / 1,595 / 1,549 / 1,537 | — | 0 / 5 / 5 / 5 / 5 | 0 / 1 / 1 / 2 / 1 | — |

- 统计行原文：`test` `2524 passed; 11 skipped; 1 failed.`；`test-ui` `2742 passed; 19 skipped; 2 failed.`；
  `test-appearance` `1615 passed; 5 skipped; 1 failed.`；`test-bmc` / `test-update` / `test-plugin-fixture` 为 `426/426`、`8/8`、`24/24 tests passed`
  （build summary，用独立 `--cache-dir` 强制重跑取得）；`test-local` 为 `28/28`、`1564 passed; 5 skipped; 1 failed.`、
  `1589 passed; 5 skipped; 1 failed.`、`1542 passed; 5 skipped; 2 failed.`、`1531 passed; 5 skipped; 1 failed.`。
- 静态上界与 P0 逐项相同（`src/root.zig` 2,560、`test-ui` 根 2,787）；各根的闭包文件数比 P0 多 1（新增 `src/shared/ui/theme/theme_publication.zig`）。
- 失败清单：
  - `fetch_url` 系统代理（已知，无网络沙箱所致）：`test`、`test-ui`、`test-appearance` 与 `test-local` 的 4 个大二进制各 1 条；
  - `connection_host` “keeps a failed original owner…”（已知，`test-ui`，测试名前缀现为 `features.connections.progress.tests.connection_host_tests`）；
  - 新的疑似时序不稳定：`test-local` 的 terminal-execution-tests 中
    `features.terminal.tests.terminal_execution_tests.test.production Local command history preserves approved AI and manual repeats across archive reopen`
    报 `ExecutionIntegrationTimeout`（驱动真实 PTY）；用 `-Dlocal-test-filter="preserves approved AI and manual repeats across archive reopen"`
    单独重跑通过（`All 12 tests passed.`）。P1 只改路径字面量，按“已知不稳定”对待，建议另开问题跟踪。
  - `ai_local_tools_tests` “real group active child observes outer request stop…” 本阶段三次全量运行均通过。
- `test-font`（`src/tests_font.zig`）的 `bundled terminal faces resolve exact family and supported weight…`（`expected 4, found 5`）
  在搬迁前的提交上即失败（本机字体环境），P1 前后一致。
- 测试名比对（本文第 3 条方法，只比较 `.test.` 之后的名字，匿名块按个数）：`test` 2,536 个、`test-ui` 2,763 个名字与 P0 完全相同；
  前缀随 move-map 变化（如 `connection_host_tests.test.…` → `features.connections.progress.tests.connection_host_tests.test.…`）。
- 新增步骤（P1 补，不计入上表）：`test-builtin-records` 16/16、`test-applog` 24/24；`test-compaction-e2e` 需要
  `e2e/ai_context_compaction.py` 起的回环模型服务，单独运行时 8 个用例 2 过 6 失败（无服务可连）。
