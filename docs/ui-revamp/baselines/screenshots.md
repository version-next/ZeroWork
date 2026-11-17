# 截图基线索引（P0，“迁移前”）

对应方案 §6.2 P0 第 6 条。截图不入库，存放在仓库外的证据目录；本文件只记录来源、复现方法与比对方式。

## 基本信息

| 项 | 值 |
|---|---|
| 证据目录 | `~/work/ZeroWork-evidence/p0-baseline/` |
| 源码 commit | `7034789d`（相对 `4281edb4` 只改了 `build.zig` 的 yix 扫描范围，运行时代码一致） |
| 构建命令 | `zig build -Dtest-mode=true -j2 --prefix /private/tmp/zw-p0-baseline-build` |
| 可执行文件 SHA-256 | `6e49b17c726b684e893d5a160ca79aca3b609d7262e9a41294129fc5789e139a`（`binary.sha256`） |
| 截图清单与哈希 | 证据目录下的 `SHA256SUMS`（61 张 PNG） |
| 运行环境 | 全部命令包在无网络 sandbox（`zw-nonet.sh`）内；隔离的临时 `ZEROWORK_DATA_DIR`；`[updates] auto_check=false` |
| 可重复性 | 同一二进制重跑一次（设置 light、主窗口），截图与基线**逐字节一致**（0 处差异） |

## 内容

| 子目录 | 脚本 | 结果 | 截图 |
|---|---|---|---|
| `settings_revamp-light/` | `node e2e/settings_revamp_native.ts <binary> <out> light` | passed，13 项检查 | 29 张：9 个分类的概览、各子页面、`search`、`dirty-overview`；另有 `report-light.json`、`app.log` |
| `settings_revamp-dark/` | 同上，`dark` | passed，13 项检查 | 29 张，同上；`report-dark.json` |
| `workspace/` | `node e2e/workspace.ts --binary <binary> --out <out> --fixture-dir <fixture>` | passed | 3 张：`default`（1440×900）、`compact`（860×480）、`minimum-clamped`；各带 `*.tree.json`、`*.queries.json`；`harness-report.json` |

说明：

- `workspace.ts` 自身不写配置，`auto_check=false` 通过 `--fixture-dir` 提供：fixture 目录里只有一个 `config.toml`，内容为
  `[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n`。`settings_revamp_native.ts` 自己写入了这一项。
- 主窗口基线是空数据目录下的默认状态（无已保存主机、无会话）。带会话、AI、传输、文件等 feature 的代表状态截图不在本轮范围，
  在各 feature 迁移波次开始前按 PENCIL_MAP 的节点补齐（方案 §6.3 第 5 条的 `e2e/revamp/` 快照脚本）。
- 截图来自 Metal 呈现表面，不含 AppKit 原生交通灯（见 `e2e/README.md`）。

## 之后各阶段怎样比对

1. 用同样的命令在待验收的 commit 上构建 test-mode 二进制（`--prefix` 指向仓库外目录）。
2. 用同样的参数把两个脚本跑到新的证据目录（如 `ZeroWork-evidence/p1-after/`）。
3. 在新目录里执行 `shasum -a 256 -c <基线目录>/SHA256SUMS`（相对路径一致），或逐文件 `cmp`。
   全部一致即“截图逐像素一致”；有差异的逐张列出并说明。

## 已知的必然差异

`settings_revamp-{light,dark}/*-updates.png`（“关于与更新”页）会显示构建信息 `<分支>@<commit> · <构建时间>`，
任何新构建都与基线不同。比对时这两张单独看：除这一行文字外应无差异。其余 59 张要求逐字节一致。

## P0 退出复核

在集成分支 `9880a5be`（P0 全部合并之后）重新构建 test-mode 二进制，把同样的三次 e2e 跑到
`~/work/ZeroWork-evidence/p0-exit/`：三次都 passed；`shasum -a 256 -c` 对基线 `SHA256SUMS` 的结果是
59 张一致，2 张不一致，即上面说的两张 `*-updates.png`（只有构建信息一行不同）。
