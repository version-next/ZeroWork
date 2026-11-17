//! 设置窗口的焦点标识（`focusId`，S-6）：运行期语义，与 test_id 分开命名、分开登记。
//! 值带 `focus:` 前缀，不与 test_id 的写法混淆；改名只影响焦点行为，不影响自动化。
//! 本文件不依赖 zenit `ui`。

/// “清除全部数据”按钮：数据清理确认取消后焦点回到它。
pub const data_clear_all = "focus:data.clear_all";
/// “清除会话记录”按钮：记录清理结束后焦点回到它。
pub const data_clear_logs = "focus:data.clear_logs";
/// 面板里的输入框：`前缀 + 字段 test_id`（名字沿用旧正文时期，不改名）。内容页按纪元重挂后，
/// `focusRestore` 按同名目标把焦点与选区放回同一字段（原宿主的 `captureFocus` / `restoreFocus`）。
pub const legacy_field_prefix = "focus:field:";
/// 确认对话框（H-save）的“继续编辑 / 取消”：对话框打开时焦点落在这里（按钮 `autoFocus`；原生 `W.Modal` 的自动聚焦
/// 在首次打开时取不到对话框里的按钮，缺口 G37）。落在“不改任何东西”的按钮上：误按回车不会保存或放弃。
pub const confirmation_cancel = "focus:settings.confirmation.cancel";
