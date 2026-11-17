//! 主窗口 AI 助手宿主 AiHost、标题栏 AI 点击辅助与 mountAssistantConversation（P2 自 src/main.zig 原样拆出；P5 再按回合、附件、审批、停靠、会话列表、关闭确认细拆）。

const Confirm = @import("../../../shared/ui/confirm/confirm.zig");
const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const launcher_model = @import("../pane/model/ai_launcher.zig");
const float_model = @import("../../../ai/float_model.zig");
const surface_migration = @import("../../../shared/ui/surface/surface_migration.zig");
/// Card / status snapshots only read content; the geometry inputs are placeholders.
const content_snapshot_region: float_model.Rect = .{ .x = 0, .y = 0, .width = 1200, .height = 800 };
const content_snapshot_origin: float_model.Origin = .{ .corner = .bottom_right, .anchor = .{ .x = 1128, .y = 732, .width = 48, .height = 48 }, .content = content_snapshot_region };
const ws = @import("../../workspace/view/workspace.zig");
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const AiController = @import("../../../ai/float_view.zig").Controller;
const AiManager = @import("../../../ai/turn_manager.zig").Manager;
const ai_provider = @import("../../../ai/provider.zig");
const AiClient = @import("../../../ai/provider_client.zig").Client;
const NativeContext = @import("../../../ai/provider_transport.zig").NativeContext;
const ai_provider_config = @import("../../../ai/provider_config.zig");
const ai_attachments = @import("../../../ai/local_text_attachments.zig");
const ai_attachment_request = @import("../../../ai/local_text_request.zig");
const AiAttachmentReader = @import("../../../host/ai_local_file_snapshot.zig").Reader;
const ai_images = @import("../../../ai/image_attachments.zig");
const AiImageReader = @import("../../../host/ai_image_snapshot.zig").Reader;
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const application_host_mod = @import("../../shell/host/application_host.zig");
const file_application_mod = @import("../../files/host/file_application_host.zig");
const process_state = @import("../../../app/process_state.zig");
const ChildDialog = @import("child_dialog.zig").ChildDialog;
const ProcessWindows = @import("../../../app/process_windows.zig").ProcessWindows;
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;
const wallClockMsTransfer = @import("../../transfer/host/transfer_host.zig").wallClockMsTransfer;

const RetainedExecution = struct {
    receipt: @import("../../../ai/host_execution.zig").Retained,
    admission: @import("../tools/host/ai_execution_backend.zig").Admission,
};
/// Bounded: the oldest retained receipts are dropped first.
const retained_execution_limit = 64;

pub const AiHost = struct {
    const PendingAiCompletion = struct {
        context: @import("../../../ai/host_tools.zig").Context,
        owner: @import("../../../host/identity.zig").ContentOwner,
        operation: u64,
        turn: u64,
        completion: @import("../../../host/notification_host.zig").AiCompletion,
        detail: [1400]u8 = @splat(0),
        detail_len: usize = 0,
    };

    pub const TerminalIntent = struct {
        tab: @import("../../../host/identity.zig").TabId,
        source: @import("../../../host/identity.zig").SessionHandle,
        assistant_owner: ai_attachments.Owner,
        selection: ?@import("../../../host/terminal_service.zig").Selection,
        legacy_selection: ?struct { range: @import("../../../vt/engine.zig").Selection, source_version: u64 } = null,
        members: [@import("../../../ai/tool_scope.zig").max_targets]@import("../../../host/identity.zig").SessionHandle = undefined,
        member_count: usize = 0,
    };
    const CloseWindowRequest = struct {
        ticket: @import("../pane/view/ai_close_confirmation_view.zig").Ticket,
        runtime_id: u64,
        owner: @import("../../../ai/tool_scope.zig").Owner,
        task_id: ?@import("../../../host/identity.zig").TaskId,
    };
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    scope: ?*ui.Scope = null,
    history_submissions: std.AutoHashMapUnmanaged(@import("../../../host/identity.zig").ExecutionId, void) = .empty,
    /// The AI chat card on the window's floating card layer (shared/ui/float_card): move, resize,
    /// maximize, fold to tab, open from the launcher and the Z12 presentation are generic; the AI
    /// keeps its content, the launcher anchor and whether the panel is open.
    card: ?*@import("../../../shared/ui/float_card/float_layer.zig").Card = null,
    /// The next presentation change is an explicit open / close (launcher, ⌘J, @ai, the panel's own
    /// controls): it folds into / unfolds from the launcher even if the owner was synced on the way.
    presentation_explicit: bool = false,
    /// syncOwner moved the panel to another owner's presentation (a tab switch) since the last update.
    presentation_switched: bool = false,
    /// e2e probe of the transition (`ai.panel.motion`): frame rect, phase and anchor name.
    motion_probe: ?*@import("../pane/view/ai_panel_motion_view.zig").View = null,
    /// Per-tab floating AI launcher (Pencil XqqLV); one view follows the current tab.
    launcher: ?*@import("../pane/view/ai_launcher_view.zig").View = null,
    /// "Opening the panel clears it" bookkeeping, per bound owner (tab).
    launcher_seen: std.AutoHashMapUnmanaged(u64, launcher_model.Seen) = .empty,
    launcher_pinger: launcher_model.Pinger = .{},
    /// The corner every tab's launcher rests in (ui.ai_launcher_corner).
    launcher_corner: launcher_model.Corner = .bottom_right,
    launcher_drag: ?struct { start: launcher_model.Rect, rect: launcher_model.Rect } = null,
    welcome_logo_texture: ?u32 = null,
    sessions_view: ?*@import("../sessions/view/ai_sessions_view.zig").View = null,
    pending_view: ?*@import("../approvals/view/ai_pending_view.zig").View = null,
    /// The queue editor's state (which queued message is being edited, its text, the fold): kept
    /// here for the main panel so it outlives the content view.
    pending_edit: ?*@import("../approvals/view/ai_pending_view.zig").Edit = null,
    pending_action: ?struct { ticket: @import("../approvals/view/ai_pending_view.zig").Ticket, action: @import("../approvals/view/ai_pending_view.zig").Action, text: ?[]u8 } = null,
    send_hint: ?*ui.Signal([]const u8) = null,
    followup_hash: ?u64 = null,
    compaction_agent: ?@import("../../../host/identity.zig").AgentId = null,
    lifecycle_command: ?@import("../../../ai/conversation_commands.zig").Command = null,
    lifecycle_confirmed: bool = false,
    lifecycle_sequence: u64 = 0,
    conversation_action: ?struct { id: u64, action: @import("../sessions/view/ai_sessions_view.zig").Action, owner: ?ai_attachments.Owner, current: ?u64 } = null,
    list_limit: usize = 50,
    history_hash: ?u64 = null,

    close_confirmation_view: ?*@import("../pane/view/ai_close_confirmation_view.zig").View = null,
    close_confirmation: ?CloseWindowRequest = null,
    close_window_requested: ?CloseWindowRequest = null,
    close_confirmation_sequence: u64 = 0,
    display_conversation: ?u64 = null,
    display_content_revision: u64 = 0,
    request_conversation: ?u64 = null,
    select_requested: ?u64 = null,
    delete_requested: ?u64 = null,
    new_requested: bool = false,
    list_requested: bool = false,

    controller: AiController,
    manager: AiManager,
    provider: ai_provider.Provider,
    native_context: ?*NativeContext,
    painted_config_revision: u64 = 0,
    native_client: ?*AiClient,
    native_binding: ?*AiClient.Binding,
    endpoint: []const u8,
    model: []const u8,
    panel: *ui.Node,
    /// The owner / status text of a child dialog's header (the main panel shows it as the chrome subtitle).
    status: ?*ui.Node = null,
    /// The child dialog's status Tag label (O9: native W.Tag in the header; ai-redesign-c).
    status_label: ?*ui.Signal([]const u8) = null,
    feedback: ?*@import("../pane/view/ai_feedback_view.zig").View = null,
    /// “尚未配置 AI 服务”就地提示（输入区上方，panel-heads）：取代没有模型时的全局提醒。
    unconfigured: ?*@import("../pane/view/ai_unconfigured_view.zig").View = null,
    /// The conversation shows the empty state (welcome / setup guide) right now (set by the rebuild).
    empty_state_shown: bool = false,
    model_gate: ?anyerror = null,
    rollback_to_start: bool = false,
    prompt: *ui.Signal([]const u8),
    textarea: ?*ui.widgets.input.TextareaState = null,
    composer_input: ?ui.widgets.input.TextareaResult = null,
    composer_node: ?*ui.Node = null,
    composer_interaction: ?*@import("../composer/view/ai_composer_interaction_view.zig").View = null,
    user_interaction: @import("../../../ai/user_interaction.zig").Broker = .{},
    settings_host: ?*SettingsHost = null,
    settings_request: ?bool = null,
    send_disabled: ?*ui.Signal(bool) = null,
    /// The main panel's unified floating chrome (`shared/ui/float_card/float_chrome.zig`); null in child dialogs.
    chrome: ?*@import("../../../shared/ui/float_card/float_chrome.zig").Chrome = null,
    /// cards-float: the AI content (conversation, composer) — one node moved between the floating
    /// chrome's body and a tab body split pane (AI docked into its tab's card layout).
    content_node: ?*ui.Node = null,
    /// The Scope of the mounted content view (conversation, composer, header popovers): everything
    /// the view owns hangs off it and is released with it (`unmountContent`). Null while the panel
    /// is closed — the host (model, execution, drafts) lives on without a view (LIFECYCLE.md §3).
    view_scope: ?*ui.Scope = null,
    /// What the reader holds in the content view (scroll, selection, carets, keyboard), kept here
    /// while no view holds it (`captureViewState` / `stepViewRestore`).
    view_state: ViewState = .{},
    view_restore: enum { none, scroll, rest } = .none,
    /// The transcript row (by its first message's history index) the rest of `view_state` needs
    /// before it can go back: a virtual history mounts the rows of a restored scroll position in its
    /// own before-render, after its measurements settle. Null: nothing waits for a row.
    view_restore_row: ?usize = null,
    /// The conversation scroll's input serial when the scroll position went back: a reader who
    /// scrolls before the row comes has moved on, and what waited for the row is dropped.
    view_restore_serial: u64 = 0,
    /// The editing bubble's Textarea while its row is mounted (a virtual row scrolled out releases it).
    edit_input: ?ui.widgets.input.TextareaResult = null,
    /// The transcript rows mounted now, by their first message's history index (a virtual history
    /// mounts and releases rows as they scroll): what a captured selection finds its row by.
    row_anchors: std.AutoHashMapUnmanaged(usize, ui.hit.NodeHandle) = .empty,
    /// The current transcript is a virtual history (rows are rendered in before-render).
    history_virtual: bool = false,
    /// What the content view needs from its window (set once by the window, applied at every mount).
    content_env: ContentEnv = .{},
    /// The dock request recorded by the chrome / pane header, acted on in the next frame.
    dock_request: ?DockRequest = null,
    painted_colors: ?app_theme.Colors = null,
    /// Owned by the frame hook’s scope, which can outlive the conversation view.
    theme_watch: @import("../../../shared/ui/theme/theme_watch.zig").ThemeWatch = .{},
    /// Where this host's publications wake (LIFECYCLE.md §5.1): a view binds its own window; an
    /// execution host binds the window of the view that shows it (`attachedView`). Its mailboxes,
    /// bridges, brokers and driver publish through it.
    wake_target: @import("../../../ai/publication.zig").Wake = .{},
    /// When the frame hook runs its pass (view hosts only).
    gate: @import("frame_gate.zig").Gate = .{},
    /// The tail follow asked for another frame (a glide in progress).
    follow_busy: bool = false,
    /// The transcript content height the tail follow last followed.
    follow_content_h: f32 = 0,
    composer_controls: ?*@import("../composer/view/ai_composer_controls_view.zig").View = null,
    /// The composer area's view-model (`composer/view/ai_composer.yix`).
    composer: ?*@import("../composer/view/ai_composer_view.zig").View = null,
    attachments_view: ?*@import("../attachments/view/ai_attachments_view.zig").View = null,
    attachment_readers: std.ArrayList(*AiAttachmentReader) = .empty,
    attachment_picker_active: bool = false,
    images_view: ?*@import("../attachments/view/ai_image_attachments_view.zig").View = null,
    image_readers: std.ArrayList(*AiImageReader) = .empty,
    transcript_images: ?*@import("../attachments/view/ai_transcript_images.zig").Store = null,
    image_render_turn: ?*const @import("../../../ai/conversation_turn.zig").Turn = null,
    request_images: ?ai_images.Bundle = null,
    request_image_refs: std.ArrayList(ai_images.ContentRef) = .empty,
    preflight_image_refs: std.ArrayList([]ai_images.ContentRef) = .empty,
    remote_picker: ?*@import("../attachments/view/ai_remote_picker.zig").View = null,
    file_application: ?*file_application_mod.Host = null,
    request_attachments: ?ai_attachments.Bundle = null,
    attachment_preview_holder: ?*ui.Node = null,
    attachment_preview_scroll_y: ?f32 = null,
    composer_hash: ?u64 = null,
    composer_usage: @import("../../../ai/composer_usage_cache.zig").Cache = .{},
    context_usage_mailbox: @import("../../../ai/live_context_usage.zig").Mailbox = .{},
    request_effort: ?ai_provider.Effort = null,
    live_reasoning: @import("../../../ai/live_reasoning.zig").State = .{},
    request_thinking: ?bool = null,
    model_discovery: @import("../../../ai/model_discovery.zig").Service = .{},
    request_vision: bool = false,
    request_image_token_reservation: ?u32 = null,
    request_image_token_max_width: ?u32 = null,
    request_image_token_max_height: ?u32 = null,
    image_gate: ?anyerror = null,
    stream_mailbox: @import("../../../ai/stream_mailbox.zig").Mailbox,
    step_mailbox: @import("../../../ai/step_events.zig").Mailbox,
    current_turn: @import("../../../ai/conversation_turn.zig").Turn = .{},
    recall_index: ?usize = null,
    recall_draft: ?[]u8 = null,
    message_action: ?MessageAction = null,
    editing_index: ?usize = null,
    edit_text: ?*ui.Signal([]const u8) = null,
    edit_seed: ?usize = null,

    streaming_label: ?*ui.Node = null,
    live_card: ?*ui.Node = null,
    live_scope: ?*ui.Scope = null,
    live_dirty: bool = false,
    tool_bridge: @import("../tools/host/ai_tools.zig").Bridge,
    tool_results: @import("../../../ai/tool_results.zig").Store,
    host_approval: @import("../../../ai/host_approval.zig").Broker = .{},
    inventory_approval: @import("../../../ai/inventory_approval.zig").Broker = .{},
    request_policy_revision: u64 = 0,
    secret_controller: ?@import("../approvals/host/ai_host_secret_controller.zig").Controller = null,
    recording_archive: ?@import("../../../vt/session_archive.zig").Archive = null,
    recording_access: ?@import("../tools/host/ai_recording_query_access.zig").Access = null,
    lifecycle_runtime: ?@import("../../../ai/lifecycle_runtime.zig").Runtime = null,
    data_root: []const u8 = "",
    lifecycle_controller: ?*@import("../tools/host/ai_lifecycle_controller.zig").Controller = null,
    lifecycle_controllers: std.ArrayList(*@import("../tools/host/ai_lifecycle_controller.zig").Controller) = .empty,
    execution_backend: ?@import("../tools/host/ai_execution_backend.zig").Context = null,
    /// Settled executions of released workers, per conversation (view host only, c_allocator):
    /// a restored conversation reads its own receipts again (see `execution.Retained`).
    retained_executions: std.ArrayList(RetainedExecution) = .empty,
    execution_driver: ?*@import("../../../ai/host_execution_driver.zig").Driver = null,
    execution_close_sent: std.ArrayList(@import("../../../host/identity.zig").SessionHandle) = .empty,
    execution_bridge: @import("../tools/host/ai_tools.zig").Bridge,
    task_finish: ?@import("../cards/view/ai_task_finish.zig").Controller = null,
    task_finish_holder: ?*ui.Node = null,
    task_finish_views: std.ArrayList(TaskFinishView) = .empty,
    pending_host_notices: std.ArrayList(?PendingHostNotice) = .empty,
    pending_execution_action: ?ExecutionAction = null,
    released_task_contexts: std.ArrayList(@import("../../../ai/host_tools.zig").Context) = .empty,
    pending_ai_completions: std.ArrayList(?PendingAiCompletion) = .empty,
    host_catalog: @import("../../../ai/host_tool_catalog.zig").Buffer = undefined,
    host_catalog_len: usize = 0,
    turn_footer: ?*ui.Node = null,
    // Borrowed from tool_bridge's request table; never read after clear().
    request_tools: []const ai_provider.ToolDefinition = &.{},
    request_tools_len: usize = 0,
    request_tool_tokens: usize = 0,
    request_usage_fixed: @import("../../../ai/context_usage.zig").Fixed = .{},

    // ── Async request engine ─────────────────────────────────────────
    // The provider transport is a SYNCHRONOUS HTTP call that can take
    // seconds (mimo flash round-trips ~1-5s). Running it on the UI thread
    // froze every redraw (window drag, typing, terminal output) until the
    // response arrived. The request now runs on a dedicated worker thread
    // with its OWN std.Io.Threaded instance — std.Io is not thread-safe,
    // and the app's io is owned by the UI thread, so the worker gets a
    // private one it uses exclusively. Results cross back via an atomic
    // state flag consumed by a UI-thread after-layout hook (same pattern
    // as Workspace.PollHook): release-store in the worker, acquire-load
    // in the hook establishes the happens-before for the card data.
    ai_io: ?*std.Io.Threaded = null,
    thread_state: std.atomic.Value(u8) = .init(0), // 0 idle · 1 running · 2 done · 3 failed
    request_cancel: ai_provider.CancelToken = .{},
    /// Worker completion state: 4 means the user explicitly stopped the
    /// request.  It is distinct from provider/network failures so the UI
    /// does not present a normal error after pressing the design's stop
    /// control.
    worker_thread: ?std.Thread = null,
    /// Owned copy of the submitted prompt for the worker (controller's
    /// internal buffer would be overwritten by the next keystroke).
    request_text: ?[]u8 = null,
    failure_label: []const u8 = "AI request failed",
    attached_finalized: bool = false,
    presentation_saved_at_ns: i128 = 0,
    failure_detail: [1400]u8 = undefined,
    request_failure: ?anyerror = null,
    request_stats: ai_provider.ChatStats = .{ .usage_reported = false },
    recovery_failed: bool = false,
    recovery_pending: ?@import("../cards/view/ai_recovery_view.zig").Envelope = null,
    verification_pending: ?@import("../cards/view/ai_verification_view.zig").Ticket = null,
    recovery_cooldown_seconds: u64 = 0,
    answer_only: bool = false,
    retry_prefix_count: usize = 0,
    runtime_config: ?*RuntimeConfig = null,
    card_box: ?*ui.Node = null,
    conversation_viewport: ?*ui.Node = null,
    tail_follow: ?@import("../pane/view/ai_tail_follow.zig").Follow = null,
    /// Bumped by every batch of live output for the displayed conversation (the “新消息” hint's signal).
    live_output_serial: usize = 0,
    /// “新消息” hint over the transcript's bottom (ai-redesign-c).
    new_messages: ?*@import("../pane/view/ai_new_messages_view.zig").View = null,
    /// Tool-row slots of Stop / Send (their native Tooltip wrappers).
    /// Composer area margins last applied by layoutComposerArea (width rules).
    composer_margins: ?ui.Padding = null,
    composer_height: ?f32 = null,
    input_node: ?*ui.Node = null,
    request_config: ?@import("../../../config/runtime_config.zig").Snapshot = null,
    extension_session: ?@import("../../../ai/extension_gateway.zig").Session = null,
    request_context: ?@import("../../../ai/assembler.zig").Assembled = null,
    request_execution_policy: @import("../../../config/config.zig").ExecutionPolicy = .{ .execution_mode = .auto, .session_retention = .auto_idle },
    request_permission_mode: @import("../../../config/config.zig").PermissionMode = .confirm,
    request_host_context: ?@import("../../../ai/host_tools.zig").Context = null,
    host_notice_revision: u64 = 0,
    authority_notice_revision: u64 = 0,
    shell_notice_hash: ?[32]u8 = null,
    host_cursor_key: [32]u8 = @splat(0),
    request_session: ?ws.SessionId = null,
    request_owner: ?@import("../../../ai/tool_scope.zig").Owner = null,
    request_content_owner: ?@import("../../../host/identity.zig").ContentOwner = null,
    request_max_output: u32 = 0,
    notification_window: ?@import("../../../host/notification_host.zig").WindowId = null,
    request_operation_id: ?u64 = null,
    approval_notification: ?@import("../../../host/notification_coordinator.zig").NotificationEvent = null,
    display_owner: ?@import("../../../ai/tool_scope.zig").Owner = null,
    assistant_states: ?*@import("../../../ai/assistant_store.zig").Store = null,
    roster: ?*@import("../../workspace/model/group_model.zig").Roster = null,
    request_history: @import("../../../ai/wire_history.zig").History = .{},
    wire_history: @import("../../../ai/wire_history.zig").History = .{},
    compaction: @import("../../../ai/context_compaction.zig").Service = .{},
    conversation_titles: @import("../../../ai/conversation_title.zig").Service = .{},
    auto_compaction_attempts: std.AutoHashMapUnmanaged(u64, u64) = .empty,

    /// 对话流节点（refresh 时整体重建，样式复刻 mockup-ai-float）。
    conversation: ?*ui.Node = null,
    conversation_scope: ?*ui.Scope = null,
    history_heights: @import("../pane/view/ai_history_view.zig").Heights = .{},
    history_heights_conversation: ?u64 = null,
    conversation_dirty: bool = false,
    live_timeline: ?*@import("../pane/view/ai_timeline_view.zig").View = null,
    conversation_bubble_width: ?f32 = null,
    /// The message column's width (`messageWidth`), the model value user bubbles and sent-attachment
    /// rails cap themselves from (`ai_user_message_view.ContentWidth`). Written at every rebuild and
    /// whenever the panel's width changes; the views follow it.
    message_width: ?*ui.Signal(f32) = null,
    /// 最后一轮提交的用户输入（渲染用户气泡；submit 拷贝所有权）。
    last_user_text: ?[]u8 = null,
    last_user_wire: ?[]u8 = null,
    last_user_attachments: ?ai_attachments.Bundle = null,
    last_user_images: ?ai_images.Bundle = null,
    workspace: ?*ws.Workspace = null,
    application_host: ?*application_host_mod.ApplicationHost = null,
    execution_host: ?*AiHost = null,
    backend_owner: ?*AiHost = null,
    attached_runner: ?*@import("../../../ai/session_runtime.zig").Runner = null,
    shared_service: ?*@import("../../../ai/attached_service.zig").Host = null,
    resource_stamp: ?u64 = null,
    /// The AI's lifecycle controller committed a handoff / membership change since the last
    /// resource-stamp check (`handoffCommitted` / `membershipCommitted`): the environment refresh
    /// that follows keeps the trusted route choice the transition carries.
    lifecycle_transition: bool = false,
    attached_scope: ?@import("../../../ai/tool_scope.zig").Scope = null,
    attached_inputs: std.ArrayList(AttachedInput) = .empty,
    /// Test-id namespace of this conversation surface: `.child` for a child dialog's host (set where
    /// the dialog mounts it, together with the Scope's namespace), `.main` otherwise.
    id_space: @import("../shared/view/ai_id_space.zig").IdSpace = .main,
    /// A child dialog's host: the conversation phases board of its dialog (set where it is mounted).
    child_phases: ?*@import("../sessions/model/view_model.zig").SessionPhases = null,
    child_identity: ?@import("../../../host/identity.zig").AgentId = null,
    child_parent: ?*AiHost = null,
    children_view: ?*@import("../sessions/view/ai_children_view.zig").View = null,
    child_open_requested: ?struct { agent: @import("../../../host/identity.zig").AgentId, revision: u64, parent: ?@import("../../../host/identity.zig").ConversationId } = null,
    child_list_parent: ?@import("../../../host/identity.zig").ConversationId = null,
    child_dialog: ?*ChildDialog = null,

    history: std.ArrayList(HistoryMessage) = .empty,
    /// The reader's state in the content view that is not conversation data: where the transcript
    /// is scrolled, what is selected, where the carets are, who has the keyboard. It lives in the
    /// nodes while a view shows it; it is captured here when the panel is about to go away (closing,
    /// folding into its tab) or the view is released, and applied to the view that shows the same
    /// conversation next (LIFECYCLE.md §1). `captured` = this holds a state not yet given back.
    pub const ViewState = struct {
        captured: bool = false,
        conversation: ?u64 = null,
        scroll: ?struct { y: f32, following: bool, unseen: bool } = null,
        /// `row`: the history index of the transcript row the selection is in (a virtual history
        /// row); null: the path is from the transcript's top (every message is mounted).
        selection: ?struct { row: ?usize, saved: @import("../pane/view/ai_text_selection.zig").Saved } = null,
        composer: ?Caret = null,
        edit: ?Caret = null,
        focus: enum { none, composer, edit, selection } = .none,
        pub const Caret = struct {
            anchor: ?usize,
            offset: usize,
            fn of(state: *const ui.widgets.input.TextareaState) Caret {
                return .{ .anchor = state.cursor.anchor, .offset = state.cursor.offset };
            }
            fn apply(self: Caret, state: *ui.widgets.input.TextareaState) void {
                _ = state.setAccessibilitySelection(std.math.cast(u32, self.anchor orelse self.offset) orelse return, std.math.cast(u32, self.offset) orelse return);
            }
        };
    };
    pub const ContentEnv = struct {
        /// The area attachment / image previews are laid out in (the window's terminal area).
        preview_content: ?*ui.Node = null,
        /// The application (image previews open native windows).
        app: ?*@import("zenit_app").App = null,
    };
    const TaskFinishView = struct { task: @import("../../../host/identity.zig").TaskId, view: *@import("../cards/view/ai_task_finish.zig").View };
    const PendingHostNotice = struct {
        context: @import("../../../ai/host_tools.zig").Context,
        revision: u64,
        text: [512]u8,
        len: usize,
        fn content(self: *const @This()) []const u8 {
            return self.text[0..self.len];
        }
    };
    const MessageAction = struct { kind: enum { rewind, edit, save, cancel, fork }, index: usize, conversation: ?u64 = null };
    const ExecutionAction = struct { action: @import("../cards/view/ai_execution_result_view.zig").Action, target: @import("../../../ai/tool_results.zig").ExecutionActionTarget };
    const HistoryMessage = @import("../../../ai/assistant_store.zig").Message;

    pub fn childRecord(self: *AiHost) ?*@import("../../../ai/session_lifecycle.zig").Record {
        const shared_host = self.shared_service orelse return null;
        const agent = self.child_identity orelse if (self.attached_runner) |runner| if (runner.agent.role == .child) runner.agent.id else return null else return null;
        for (shared_host.service.store.records.items) |record| if (record.child) |owned| if (owned.info.agent.eql(agent)) return record;
        return null;
    }
    fn parentPermission(self: *AiHost) @import("../../../config/config.zig").PermissionMode {
        const record = self.childRecord() orelse return .confirm;
        const shared_host = self.shared_service orelse return .confirm;
        const parent = shared_host.presentations.findConversation(record.child.?.info.owning_parent_conversation) orelse return .confirm;
        if (parent.controls.permission) |permission| return permission;
        const runtime = self.runtime_config orelse (self.attachedView().runtime_config orelse return .confirm);
        return runtime.value.ai.permission_mode;
    }
    pub fn childCanWrite(self: *AiHost) bool {
        const record = self.childRecord() orelse return false;
        const parent = self.shared_service.?.service.store.find(record.child.?.info.owning_parent_conversation) orelse return false;
        if (parent.binding == null or parent.ending != null or parent.transition != null or parent.needs_recovery or record.ending != null or record.needs_recovery) return false;
        return self.attachmentOwnerExists(parent.binding.?.owner);
    }
    fn syncChildView(self: *AiHost) !void {
        const record = self.childRecord() orelse return error.ChildNotFound;
        const state = self.assistant_states.?.find(self.display_conversation orelse return error.ConversationNotFound) orelse return error.ConversationNotFound;
        if (self.currentBinding()) |owner| {
            self.display_owner = owner;
            state.owner = owner;
        }
        if (self.child_parent.?.child_dialog) |dialog| {
            const writable = self.childCanWrite();
            if (self.composer) |composer| composer.setShown(writable);
            dialog.apply_disabled.set(!writable);
            dialog.restore_parent.setDisplay(if (writable) .none else .flex);
            if (dialog.last_writable == null or dialog.last_writable.? != writable) {
                var label: [192]u8 = undefined;
                try dialog.parent_label.setTextContent(self.allocator, if (!writable) "父对话未绑定或正在收尾，恢复父对话后可继续" else try std.fmt.bufPrint(&label, "父对话 {s} · {s}上下文", .{ std.fmt.bytesToHex(record.child.?.info.owning_parent_conversation.bytes, .lower)[0..8], if (record.child.?.info.context_mode == .inherit) "继承" else "独立" }));
                dialog.last_writable = writable;
            }
            dialog.showStatus(@import("../../../ai/child_projection.zig").entry(&self.shared_service.?.service, record));
        }
    }
    fn bindUserChild(self: *AiHost, owner: ai_attachments.Owner) !*AiHost {
        if (!self.childCanWrite()) return error.ParentBindingChanged;
        const record = self.childRecord() orelse return error.ChildNotFound;
        const shared_host = self.shared_service.?;
        const agent = record.child.?.info.agent;
        var backend: *AiHost = undefined;
        if (shared_host.bridgeFor(agent)) |bridge| backend = @ptrCast(@alignCast(bridge.context)) else {
            if (shared_host.closing) return error.ApplicationClosing;
            try shared_host.bridges.ensureUnusedCapacity(shared_host.allocator, 1);
            const a = std.heap.c_allocator;
            backend = try a.create(AiHost);
            errdefer a.destroy(backend);
            backend.* = self.attachedSlot(a, shared_host);
            backend.bindExecutionWake(self);
            const parent = try shared_host.service.store.fence(record.child.?.info.owning_parent_conversation);
            const allowed = try self.child_parent.?.captureOwnerScope(owner);
            defer if (allowed.inventory) |ids| self.child_parent.?.allocator.free(ids);
            const prefs = @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record);
            const runner = try shared_host.service.useChild(parent, agent, record.revision, allowed, prefs.targets, .{ .context = backend, .wake = &backend.wake_target, .capture = captureAttached, .prepare = prepareAttached, .completed = completeAttached, .local_released = attachedReleased, .supersede = supersedeAttached, .stop = stopAttached, .release_worker = releaseAttachedWorker }, null);
            backend.attached_runner = runner;
            try shared_host.register(.{ .agent = agent, .window = self.application_host.?.window_id, .context = backend, .pump = pumpAttached, .released = disposeReadyAttached, .destroy = destroyAttached, .flush = flushAttached });
        }
        backend.backend_owner = self;
        backend.bindExecutionWake(self);
        self.execution_host = backend;
        const runner = backend.attached_runner.?;
        if (runner.thread != null) {
            runner.end_when_idle = true;
            return backend;
        }
        if (record.binding == null) {
            const parent = try shared_host.service.store.fence(record.child.?.info.owning_parent_conversation);
            const allowed = try self.child_parent.?.captureOwnerScope(owner);
            defer if (allowed.inventory) |ids| self.child_parent.?.allocator.free(ids);
            const prefs = @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record);
            for (prefs.targets) |target| {
                const tab = self.tabForSession(@backingInt(target.session_id)) orelse return error.TargetNotAuthorized;
                if (tab.content_owner != .session or !tab.content_owner.session.eql(target)) return error.TargetNotAuthorized;
            }
            _ = try shared_host.service.useChild(parent, agent, record.revision, allowed, prefs.targets, runner.backend, null);
        }
        // Explicit user continuation is allowed even when reusable=false. A
        // prior unknown attempt still restricts this new task to observation.
        var verification = false;
        for (shared_host.service.store.task_facts.items) |prior| if (prior.fact.agent.eql(agent)) @import("../../../ai/child_gateway.zig").checkReuse(prior.fact, runner.agent.targets, false) catch {
            verification = true;
        };
        for (shared_host.service.task_roots.items) |root| {
            root.lock();
            defer root.mutex.unlock();
            for (root.facts[0..root.count]) |prior| if (prior.agent.eql(agent)) @import("../../../ai/child_gateway.zig").checkReuse(prior, runner.agent.targets, false) catch {
                verification = true;
            };
        }
        runner.observation_only = verification;
        runner.end_when_idle = true;
        // Binding provenance changes on every explicit user continuation.
        // Publish that exact generation to the presentation before capture;
        // the execution backend validates it before admitting any tool.
        const state = self.assistant_states.?.find(self.display_conversation.?) orelse return error.ConversationNotFound;
        state.binding_revision = record.revision;
        state.owner = record.binding.?.owner;
        state.ended = false;
        state.closed = false;
        if (verification) self.setFeedback("原操作结果未知，本次续行为只读核验");
        return backend;
    }
    fn saveChildPreferences(self: *AiHost) !void {
        const life = @import("../../../ai/session_lifecycle.zig");
        const record = self.childRecord() orelse return error.ChildNotFound;
        const shared_host = self.shared_service.?;
        const parent = try shared_host.service.store.fence(record.child.?.info.owning_parent_conversation);
        const allowed = try self.child_parent.?.captureOwnerScope((try shared_host.service.store.validate(parent)).binding.?.owner);
        defer if (allowed.inventory) |ids| self.child_parent.?.allocator.free(ids);
        var prefs = life.Store.childPreferences(record);
        const controls = try self.selectedControls();
        prefs.model = controls.model;
        prefs.effort = controls.effort;
        prefs.thinking = controls.thinking;
        prefs.session_retention = controls.session_retention;
        prefs.permission = controls.permission orelse .confirm;
        prefs.execution_mode = controls.execution_mode orelse .auto;
        try shared_host.service.store.updateChildSettings(parent, record.child.?.info.agent, record.child_settings_revision, prefs, allowed);
    }
    pub fn childSelected(raw: *anyopaque, agent: @import("../../../host/identity.zig").AgentId, revision: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.child_open_requested = .{ .agent = agent, .revision = revision, .parent = self.child_list_parent orelse if (self.assistant_states.?.find(self.display_conversation orelse return)) |state| state.conversation_id else null };
        self.wake();
    }
    fn processChildren(self: *AiHost) !void {
        if (self.child_identity != null) return;
        if (self.child_dialog) |dialog| if (!dialog.open.peek()) {
            try dialog.releaseView();
            self.child_dialog = null;
            dialog.scope.dispose();
        };
        if (self.child_open_requested) |request| {
            self.child_open_requested = null;
            const shared_host = try self.shared();
            const parent_state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
            const parent_record = shared_host.service.store.find(request.parent orelse parent_state.conversation_id) orelse return;
            var chosen: ?*@import("../../../ai/session_lifecycle.zig").Record = null;
            for (shared_host.service.store.records.items) |record| if (record.child) |owned| if (owned.info.agent.eql(request.agent) and owned.info.owning_parent_conversation.eql(parent_record.id)) {
                chosen = record;
                break;
            };
            const record = chosen orelse return error.ChildNotFound;
            if (record.child_settings_revision != request.revision) return error.StaleChildSettings;
            if (self.child_dialog) |dialog| {
                if (dialog.host.child_identity.?.eql(request.agent)) {
                    dialog.open.set(true);
                    return;
                }
                try dialog.releaseView();
                self.child_dialog = null;
                dialog.scope.dispose();
            }
            // A single view owns the editable presentation; another window
            // locates that existing dialog rather than moving or copying it.
            if (shared_host.bridgeFor(request.agent)) |bridge| {
                const backend: *AiHost = @ptrCast(@alignCast(bridge.context));
                if (backend.backend_owner) |view| if (view.child_identity != null) {
                    if (process_state.process_windows) |process| for (process.runtime.windows.items) |managed| {
                        const nav = ProcessWindows.navFor(managed.app) orelse continue;
                        if (nav.application_host == view.application_host) {
                            _ = process.runtime.activateWindow(managed.app.windowId());
                            return;
                        }
                    };
                };
            }
            self.child_dialog = try ChildDialog.mount(self, record);
        }
        if (self.children_view) |view| {
            const shared_host = self.shared_service orelse return;
            const state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
            const rows = try @import("../../../ai/child_projection.zig").query(self.allocator, &shared_host.service, self.child_list_parent orelse state.conversation_id);
            defer self.allocator.free(rows);
            var running_count: ?usize = null;
            if (self.child_list_parent != null) {
                running_count = 0;
                for (shared_host.service.store.records.items) |candidate| if (candidate.child) |child| if (child.info.owning_parent_conversation.eql(state.conversation_id)) {
                    running_count.? += @intFromBool(@import("../../../ai/child_projection.zig").entry(&shared_host.service, candidate).running);
                };
            }
            try view.updateWithCount(rows, running_count);
            if (!view.open.peek()) self.child_list_parent = null;
        }
    }

    /// The Scope content views mount in: the mounted content view's (main panel), or the dialog's
    /// own (a child dialog's host lives exactly as long as its view). Null while unmounted.
    fn contentScope(self: *AiHost) ?*ui.Scope {
        return self.view_scope orelse if (self.child_identity != null) self.scope else null;
    }
    pub fn contentMounted(self: *const AiHost) bool {
        return self.content_node != null;
    }
    pub fn setContentApp(self: *AiHost, app: *@import("zenit_app").App) void {
        self.content_env.app = app;
        if (self.images_view) |view| view.app = app;
    }

    /// Build the content view (main panel): the content node with the transcript viewport, the
    /// header popovers and the composer area, in its own Scope. It goes where the panel is shown
    /// (`placeContent`); everything it displays comes from the host's model at the next frame's
    /// sync (`conversation_dirty` and the view caches start empty).
    fn mountContent(self: *AiHost) !void {
        if (self.child_identity != null or self.content_node != null) return;
        const cx = self.cx;
        const chrome = self.chrome orelse return error.MissingAssistantScope;
        const scope = try (self.scope orelse return error.MissingAssistantScope).childScope();
        errdefer scope.dispose();
        const styles = @import("../pane/view/ai_assistant_styles.zig");
        // One node, shown in the floating frame's body or in a split pane of its tab (cards-float).
        const content = try ui.box(cx, .{ .width = .fill(), .min_width = 0, .height = .{ .grow = .{} }, .min_height = 0, .direction = .column }, .{});
        content.meta.ownership.meta.test_id = "ai.content";
        errdefer cx.destroyDetached(content);
        const conversation = try ui.boxStyled(cx, styles.conversation, .{});
        conversation.meta.ownership.meta.test_id = "ai.conversation";
        const scroll = try ui.widgets.ScrollArea(.{ .height = 276, .direction = .vertical, .scrollbars = .always }).mount(scope, cx);
        scroll.container.meta.ownership.meta.test_id = "ai.conversation.viewport";
        scroll.content.setStyleInline(cx.allocator, .{ .will_change_transform = false });
        scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .overflow_hidden = true, .composited_group = true });
        try scroll.content.appendChild(cx.allocator, conversation);
        try content.appendChild(cx.allocator, scroll.container);
        // The two header popovers hang off the content node, which is displayed both floating and
        // docked: hung off the hidden chrome header, a docked popover's layer was suspended and
        // Escape could not close it (ai-redesign-c; cards_float_native 停靠会话列表).
        const children = try @import("../sessions/view/ai_children_view.zig").View.mount(cx, scope, chrome.slotNode(0) orelse return error.FloatChromeIncomplete, .{ .context = self, .select = childSelected });
        children.label_sink = .{ .chrome = chrome, .index = 0 };
        try content.appendChild(cx.allocator, children.root);
        const sessions = try @import("../sessions/view/ai_sessions_view.zig").View.mount(cx, scope, chrome.slotNode(1) orelse return error.FloatChromeIncomplete, .{ .context = self, .select = selectConversation, .request_close = requestConversationClose, .remove = deleteConversation, .act = conversationAction, .confirmed = lifecycleConfirmed });
        sessions.label_sink = .{ .chrome = chrome, .index = 1 };
        // A view mounted after the window bound the shared conversations follows them from the start
        // (phases, bound count); its Scope ends the subscription when the view is released.
        if (self.shared_service) |service| try sessions.follow(.{ .presentations = &service.presentations, .lifecycle = &service.service.store });
        try content.appendChild(cx.allocator, sessions.root);
        try self.wakeOnChange(bool, scope, children.open);
        try self.wakeOnChange(bool, scope, sessions.open);
        try self.wakeOnChange(bool, scope, sessions.history_open);
        self.view_scope = scope;
        self.children_view = children;
        self.sessions_view = sessions;
        self.conversation = conversation;
        self.content_node = content;
        self.conversation_viewport = scroll.container;
        self.tail_follow = .{ .scroll = scroll };
        errdefer self.forgetContent();
        try mountAssistantConversation(self, scope, content, scroll, conversation, self.prompt);
        if (self.images_view) |view| {
            view.preview_content = self.content_env.preview_content;
            view.app = self.content_env.app;
        }
        if (self.attachments_view) |view| view.preview_content = self.content_env.preview_content;
        // While it is outside the window (its pane's tab went away before the host placed it again)
        // the node belongs to this Scope.
        try surface_migration.own(scope, cx, content);
        self.conversation_dirty = true;
        self.wake();
    }

    /// Drop every reference into the content view and every cache of what it showed (the view
    /// built next starts from the model alone).
    fn forgetContent(self: *AiHost) void {
        self.view_scope = null;
        self.content_node = null;
        self.conversation = null;
        self.conversation_scope = null;
        self.conversation_viewport = null;
        self.tail_follow = null;
        self.children_view = null;
        self.sessions_view = null;
        self.task_finish_holder = null;
        self.task_finish_views.clearRetainingCapacity();
        self.turn_footer = null;
        self.attachment_preview_holder = null;
        self.attachments_view = null;
        self.images_view = null;
        self.remote_picker = null;
        self.feedback = null;
        self.new_messages = null;
        self.pending_view = null;
        self.unconfigured = null;
        self.composer = null;
        self.input_node = null;
        self.textarea = null;
        self.composer_input = null;
        self.composer_node = null;
        self.composer_controls = null;
        self.composer_interaction = null;
        self.send_hint = null;
        self.send_disabled = null;
        self.edit_input = null;
        self.row_anchors.clearRetainingCapacity();
        self.history_virtual = false;
        self.live_timeline = null;
        self.live_card = null;
        self.live_scope = null;
        self.live_dirty = false;
        self.streaming_label = null;
        // Caches of what the view showed.
        self.composer_hash = null;
        self.followup_hash = null;
        self.history_hash = null;
        self.composer_margins = null;
        self.composer_height = null;
        self.conversation_bubble_width = null;
        self.empty_state_shown = false;
        if (self.chrome) |chrome| self.card_box = chrome.root;
    }

    /// Release the content view: its Scope (effects, hooks, popups, widget state) and its nodes.
    /// Only at the frame hook's safe point (never inside an input callback of one of its nodes).
    /// What the reader held in it goes to `view_state` first; the host keeps running without it.
    fn unmountContent(self: *AiHost) void {
        const content = self.content_node orelse return;
        const scope = self.view_scope orelse return;
        if (!self.view_state.captured) self.captureViewState(.view);
        if (self.cx.pressed_node) |node| if (node == content or node.isDescendantOf(content)) self.cx.cancelPointerInteractions(.explicit);
        if (surface_migration.holdsFocus(self.cx, content)) self.cx.clearFocus();
        _ = self.cx.dismissOverlaysFrom(content);
        // The nodes first, then the Scope (its widgets' portal layers, effects, hooks): the same
        // order as every other view release. A node a pane teardown parked outside the window is
        // destroyed here too (its parked record goes with it, so `surface_migration.own` has
        // nothing left to free).
        if (content.parent) |holder| self.cx.detachChild(holder, content) else surface_migration.forget(content);
        self.cx.destroyDetached(content);
        self.forgetContent();
        scope.dispose();
        @import("../../../shared/ui/surface/lifecycle_budget.zig").counters.content_unmounts += 1;
    }

    /// Take what the reader holds in the view into the model. `.view`: everything, called while the
    /// keyboard is still where the reader left it (before a close hands it back to the terminal) and
    /// again when the view is released if nothing was taken yet. `.transcript`: what lives in the
    /// transcript's nodes only (selection, the edited question's caret, a keyboard in either), before
    /// a rebuild replaces them; the scroll position and the composer are not rebuilt.
    fn captureViewState(self: *AiHost, what: enum { view, transcript }) void {
        if (self.child_identity != null or self.content_node == null) return;
        const Selection = @import("../pane/view/ai_text_selection.zig");
        var state: ViewState = .{ .captured = true, .conversation = self.display_conversation };
        if (self.tail_follow) |follow| {
            if (what == .view) {
                const offset = ui.widgets.scroll_area.persistView(follow.scroll.container);
                state.scroll = .{ .y = if (offset) |view| view.y else 0, .following = follow.following, .unseen = follow.unseen };
            }
            if (Selection.selectedRoot(self.cx)) |root| if (root.isDescendantOf(follow.scroll.content)) {
                const row = self.rowOf(root);
                if (Selection.capture(self.cx, if (row) |value| value.node else follow.scroll.content)) |saved| {
                    state.selection = .{ .row = if (row) |value| value.key else null, .saved = saved };
                }
            };
        }
        if (what == .view) if (self.textarea) |textarea| {
            state.composer = .of(textarea);
        };
        if (self.edit_input) |editor| state.edit = .of(editor.state);
        if (self.cx.focus_manager.getFocused()) |focused| {
            if (self.edit_input != null and (focused == self.edit_input.?.input or focused.isDescendantOf(self.edit_input.?.wrapper))) {
                state.focus = .edit;
            } else if (what == .view and self.composer_node != null and (focused == self.composer_node.? or focused.isDescendantOf(self.composer_node.?))) {
                state.focus = .composer;
            } else if (state.selection != null) state.focus = .selection;
        }
        self.view_state = state;
    }

    /// The mounted transcript row `node` is in (its key and root), null outside the rows.
    fn rowOf(self: *AiHost, node: *ui.Node) ?struct { key: usize, node: *ui.Node } {
        var it = self.row_anchors.iterator();
        while (it.next()) |entry| {
            const row = self.cx.node_registry.resolve(entry.value_ptr.*, null) orelse continue;
            if (node == row or node.isDescendantOf(row)) return .{ .key = entry.key_ptr.*, .node = row };
        }
        return null;
    }

    /// Ask for a host pass (LIFECYCLE.md §5.1 “本地请求”): the caller changed something the pass
    /// must handle (a request, the model, the reader's state). Any thread: it publishes through
    /// this host's wake, which wakes the window that shows it; the pass runs in that window's next
    /// frame (in this frame, when called before its hook).
    pub fn wake(self: *const AiHost) void {
        self.wake_target.publish();
    }
    /// A step needs a pass again after `delay_ns` although nothing will be published (a retry, a
    /// timeout, a cooldown, a native execution only its snapshot shows). Main thread; an execution
    /// host's deadline is its view's.
    pub fn wakeAt(self: *AiHost, delay_ns: u64) void {
        const view = self.uiOwner();
        const now = @import("../../../platform/realtime.zig").monotonicNs();
        view.gate.wakeAt(now + delay_ns);
        view.cx.scheduleRedrawAfterNs(@intCast(@max(1, view.gate.untilDeadline(now) orelse delay_ns)));
    }
    /// A view host: its publications wake its own window, and its own services (titles, model
    /// discovery, compaction) publish through it. Called once the host is in its window.
    pub fn bindWindowWake(self: *AiHost) !void {
        self.wake_target.bind(@import("../../../platform/presentation_wakeup.zig").targetForWindow(@intFromPtr(self.cx)));
        self.conversation_titles.wake = &self.wake_target;
        self.compaction.wake = &self.wake_target;
        self.model_discovery.wake = &self.wake_target;
        self.wireWakes();
        // The draft: typed, recalled, written by a command — the pass persists it and updates Send.
        try self.wakeOnChange([]const u8, self.scope orelse return error.MissingAssistantScope, self.prompt);
    }
    /// A view signal the pass reads that the reader can change without calling the host (a popover
    /// or dialog closed by Esc or an outside click, the draft): a change asks for a pass.
    pub fn wakeOnChange(self: *AiHost, comptime T: type, scope: *ui.Scope, signal: *ui.Signal(T)) !void {
        const Watch = struct { host: *AiHost, signal: *ui.Signal(T), first: bool = true };
        const watch = try scope.createState(Watch, .{ .host = self, .signal = signal });
        try scope.createEffect(.{ .watch = watch }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.watch.signal.get();
                if (ctx.watch.first) {
                    ctx.watch.first = false;
                    return;
                }
                ctx.watch.host.wake();
            }
        }.run);
    }
    /// Everything this host owns that a worker writes into publishes through `wake_target`.
    /// Again after the host struct is replaced in place (`releaseAttachedWorker`).
    fn wireWakes(self: *AiHost) void {
        self.stream_mailbox.wake = &self.wake_target;
        self.step_mailbox.wake = &self.wake_target;
        self.context_usage_mailbox.wake = &self.wake_target;
        self.tool_bridge.wake = &self.wake_target;
        self.execution_bridge.wake = &self.wake_target;
        self.host_approval.wake = &self.wake_target;
        self.user_interaction.wake = &self.wake_target;
        if (self.execution_driver) |driver| driver.ui_wake = &self.wake_target;
    }
    /// An execution host is shown by `view` now: its publications wake that view's window.
    fn bindExecutionWake(self: *AiHost, view: *AiHost) void {
        self.wireWakes();
        self.wake_target.bind(view.wake_target.target.load(.acquire));
    }

    /// The panel is shown again: give the captured state back to the view once the transcript is
    /// built and laid out (`stepViewRestore` in the frame hook). A state of another conversation
    /// is dropped.
    fn requestViewRestore(self: *AiHost) void {
        if (!self.view_state.captured) return;
        if (self.view_state.conversation != self.display_conversation) {
            self.view_state = .{};
            self.view_restore = .none;
            return;
        }
        if (self.view_restore == .none) self.view_restore = .scroll;
        // Following is a mode, not a position: set it before the first layout so that frame does
        // not jump to the end of a transcript the reader had scrolled up in.
        if (self.view_state.scroll) |saved| if (self.tail_follow) |*follow| {
            follow.following = saved.following;
            follow.unseen = saved.unseen;
        };
    }

    /// One step of giving `view_state` back, after a layout of the built transcript: first the
    /// scroll position, then the composer's caret, then — once the transcript row they live in is
    /// mounted (`view_restore_row`, signalled by the row's render) — the edited question's caret,
    /// the selection and the keyboard. Returns whether this frame needs another layout.
    fn stepViewRestore(self: *AiHost) bool {
        switch (self.view_restore) {
            .none => return false,
            .scroll => {
                if (self.view_state.scroll) |saved| if (self.tail_follow) |*follow| {
                    // zenit's restore re-reads the extents from this layout before clamping.
                    if (!saved.following) ui.widgets.scroll_area.restorePersistOffset(follow.scroll.container, 0, saved.y);
                    follow.input_serial = follow.scroll.state.input_serial;
                };
                if (self.view_state.composer) |caret| if (self.textarea) |textarea| caret.apply(textarea);
                self.view_state.composer = null;
                self.view_restore = .rest;
                self.awaitRestoreRow();
                return self.stepViewRestore();
            },
            .rest => {
                if (self.view_restore_row) |key| {
                    const follow = self.tail_follow orelse return self.finishViewRestore(false);
                    // The reader scrolled before the row came: they are somewhere else now.
                    if (follow.scroll.state.input_serial != self.view_restore_serial) return self.finishViewRestore(false);
                    const handle = self.row_anchors.get(key) orelse return false;
                    if (self.cx.node_registry.resolve(handle, null) == null) return false;
                }
                return self.finishViewRestore(true);
            },
        }
    }
    /// What the rest of `view_state` waits for in a virtual history: the row of the edited question
    /// (a question starts its row) or of the selection, when the keyboard or a caret lives there.
    fn awaitRestoreRow(self: *AiHost) void {
        self.view_restore_row = null;
        if (!self.history_virtual) return;
        const state = &self.view_state;
        if (state.edit != null or state.focus == .edit) self.view_restore_row = self.editing_index;
        if (self.view_restore_row == null) if (state.selection) |selection| {
            self.view_restore_row = selection.row;
        };
        if (self.tail_follow) |follow| self.view_restore_serial = follow.scroll.state.input_serial;
    }
    /// A transcript row was rendered (its first message's history index): the restore waiting for it
    /// can go on in this frame's hook.
    fn noteRowMounted(self: *AiHost, key: usize) void {
        if (self.view_restore == .rest and self.view_restore_row == key) self.wake();
    }
    fn finishViewRestore(self: *AiHost, rows_ready: bool) bool {
        const saved = self.view_state;
        self.view_state = .{};
        self.view_restore = .none;
        self.view_restore_row = null;
        if (saved.composer) |caret| if (self.textarea) |textarea| caret.apply(textarea);
        if (!rows_ready) {
            if (saved.focus == .composer) if (self.input_node) |input| self.cx.setFocus(input);
            return false;
        }
        // The question being edited is the model's (`editing_index`); its editor exists while its
        // row is mounted.
        if (saved.edit) |caret| if (self.edit_input) |editor| caret.apply(editor.state);
        var selected = false;
        if (saved.selection) |selection| if (self.tail_follow) |follow| {
            const from: ?*ui.Node = if (selection.row) |key| (if (self.row_anchors.get(key)) |handle| self.cx.node_registry.resolve(handle, null) else null) else follow.scroll.content;
            if (from) |node| selected = @import("../pane/view/ai_text_selection.zig").restore(self.cx, node, selection.saved);
        };
        switch (saved.focus) {
            .edit => if (self.edit_input) |editor| self.cx.setFocus(editor.input),
            .composer => if (self.input_node) |input| self.cx.setFocus(input),
            .selection, .none => {},
        }
        self.wake();
        return selected;
    }

    pub fn execution(self: *const AiHost) *AiHost {
        return self.execution_host orelse @constCast(self);
    }
    fn managerRef(self: *const AiHost) *AiManager {
        const current = self.execution();
        if (current.attached_runner) |runner| if (runner.worker) |worker| return &worker.manager;
        return &current.manager;
    }
    pub fn cancelRef(self: *AiHost) *ai_provider.CancelToken {
        const current = self.execution();
        if (current.attached_runner) |runner| if (runner.worker) |worker| return &worker.cancel;
        return &current.request_cancel;
    }
    fn approvalsRef(self: *AiHost) *@import("../../../ai/host_approval.zig").Broker {
        const current = self.execution();
        if (current.attached_runner) |runner| if (runner.worker) |worker| return &worker.approvals;
        return &current.host_approval;
    }
    fn questionsRef(self: *AiHost) *@import("../../../ai/user_interaction.zig").Broker {
        const current = self.execution();
        if (current.attached_runner) |runner| if (runner.worker) |worker| return &worker.questions;
        return &current.user_interaction;
    }
    fn uiOwner(self: *AiHost) *AiHost {
        return self.backend_owner orelse self;
    }
    pub fn shared(self: *AiHost) !*@import("../../../ai/attached_service.zig").Host {
        if (self.shared_service) |service| return service;
        const app = self.application_host orelse return error.ContextUnavailable;
        const service = try app.domain.aiService();
        const already_failed = service.persistence_failure != null;
        service.ensurePersistence(self.data_root) catch |err| {
            if (!already_failed) self.setFeedback(@errorName(err));
            return err;
        };
        self.shared_service = service;
        self.assistant_states = &service.presentations;
        // The window's session views follow the shared conversations from now on (phases, bound count).
        if (self.sessions_view) |view| try view.follow(.{ .presentations = &service.presentations, .lifecycle = &service.service.store });
        return service;
    }
    /// The conversation phases this host's views read: the session list's (main panel; released with
    /// the content view), or the child dialog's own board (its Scope owns it, so rows in the dialog
    /// never outlive the board they subscribe to while the parent's content view comes and goes).
    fn sessionPhases(self: *AiHost) ?*@import("../sessions/model/view_model.zig").SessionPhases {
        if (self.child_identity != null) return self.child_phases;
        const view = self.sessions_view orelse return null;
        return view.phases;
    }

    /// 当前 tab 的 AI 归属（M10）：单卡 tab 与分屏（会话组）tab 都绑定自己的 TabId。tab 能否启动
    /// AI 由卡片派生：单卡 tab 看它的卡片，组 tab 是会话组的容器（成员逐张在作用域里派生）。
    pub fn currentBinding(self: *AiHost) ?ai_attachments.Owner {
        if (self.child_identity != null) return if (self.childRecord()) |record| if (self.shared_service.?.service.store.find(record.child.?.info.owning_parent_conversation)) |parent| if (parent.binding) |binding| binding.owner else self.display_owner else self.display_owner else self.display_owner;
        const workspace = self.workspace orelse return null;
        if (workspace.active_group_view) |id| {
            const roster = self.roster orelse return null;
            _ = roster.findById(id) orelse return null;
            return .{ .tab = @backingInt(workspace.groupTabId(id) orelse return null) };
        }
        const index = workspace.active_tab orelse return null;
        if (index >= workspace.tabs.items.len) return null;
        const tab = workspace.tabs.items[index];
        if (!self.supportsAssistant(tab)) return null;
        return tabOwner(tab);
    }
    fn tabOwner(tab: *const ws.SessionTab) ai_attachments.Owner {
        return .{ .tab = @backingInt(tab.tab_id) };
    }

    /// 一个 AI 归属解析到的 tab（M10）：tab 的内容，单卡 tab 另带它的会话卡片。只读的旧归属
    /// （回放的历史对话）按旧的会话 / 会话组解析，只用于显示来源与定位。
    pub const BoundTab = struct {
        tab: u64,
        content: @import("../../../ai/tool_scope.zig").Content,
        card: ?*ws.SessionTab = null,
    };
    pub fn resolveOwner(self: *AiHost, owner: ai_attachments.Owner) ?BoundTab {
        const workspace = self.workspace orelse return null;
        switch (owner) {
            .tab => |id| {
                const tab_id: @import("../../../host/identity.zig").TabId = @fromBackingInt(id);
                if (workspace.groupIdByTab(tab_id)) |group| {
                    const roster = self.roster orelse return null;
                    _ = roster.findById(group) orelse return null;
                    return .{ .tab = id, .content = .{ .group = group } };
                }
                for (workspace.tabs.items) |tab| if (@backingInt(tab.tab_id) == id) {
                    if (!self.supportsAssistant(tab)) return null;
                    return .{ .tab = id, .content = .{ .session = @backingInt(tab.content_owner.session.session_id) }, .card = tab };
                };
                return null;
            },
            .session => |id| {
                const tab = self.tabForSession(id) orelse return null;
                return .{ .tab = @backingInt(tab.tab_id), .content = .{ .session = id }, .card = tab };
            },
            .group => |id| {
                const small = std.math.cast(u32, id) orelse return null;
                const roster = self.roster orelse return null;
                _ = roster.findById(small) orelse return null;
                return .{ .tab = @backingInt(workspace.groupTabId(small) orelse return null), .content = .{ .group = id } };
            },
        }
    }
    /// 绑定 tab 的内容（会话或会话组）；tab 已不在时为 null。
    pub fn ownerContent(self: *AiHost, owner: ai_attachments.Owner) ?@import("../../../ai/tool_scope.zig").Content {
        return if (self.resolveOwner(owner)) |bound| bound.content else null;
    }
    /// tab 里声明了 AI 的会话卡片（单卡与分屏同一条路径）：单卡 tab 是它自己，组 tab 是会话组里
    /// 仍在组内的成员卡片。顺序与会话组成员顺序一致。
    fn appendTabCards(self: *AiHost, bound: BoundTab, ids: *std.ArrayList(u64)) !void {
        switch (bound.content) {
            .session => |id| try ids.append(self.allocator, id),
            .group => |id| {
                const group = (self.roster orelse return error.MissingAssistantOwner).findById(@intCast(id)) orelse return error.MissingAssistantOwner;
                for (group.members.items) |member| for (self.workspace.?.tabs.items) |tab| {
                    if (member.active and tab.id == member.pane_id and self.supportsAssistant(tab)) try ids.append(self.allocator, @backingInt(tab.content_owner.session.session_id));
                };
            },
        }
    }

    /// The caller frees inventory. Request/Bridge owners clone it before the
    /// next UI mutation; an empty group is still a valid conversation binding.
    fn captureCurrentScope(self: *AiHost) !@import("../../../ai/tool_scope.zig").Scope {
        const owner = self.currentBinding() orelse return error.MissingAssistantOwner;
        return self.captureOwnerScope(owner);
    }
    pub fn captureOwnerScope(self: *AiHost, owner: ai_attachments.Owner) !@import("../../../ai/tool_scope.zig").Scope {
        if (owner.legacy()) return error.MissingAssistantOwner;
        const bound = self.resolveOwner(owner) orelse return error.MissingAssistantOwner;
        var result: @import("../../../ai/tool_scope.zig").Scope = .{ .owner = owner, .content = bound.content, .members = .{} };
        var ids: std.ArrayList(u64) = .empty;
        defer ids.deinit(self.allocator);
        try self.appendTabCards(bound, &ids);
        const child_targets: ?[]const @import("../../../host/identity.zig").SessionHandle = if (self.attached_runner) |runner| (if (runner.agent.role == .child) runner.agent.targets else null) else if (self.child_identity != null) child: {
            const record = self.childRecord() orelse return error.ChildNotFound;
            if (record.binding != null) break :child self.shared_service.?.service.store.agent(self.child_identity.?).?.targets;
            break :child @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record).targets;
        } else null;
        if (child_targets) |assigned| {
            var kept: usize = 0;
            for (ids.items) |session_id| {
                const tab = self.tabForSession(session_id) orelse continue;
                const handle = tab.content_owner.session;
                for (assigned) |target| if (target.eql(handle)) {
                    ids.items[kept] = session_id;
                    kept += 1;
                    break;
                };
            }
            ids.shrinkRetainingCapacity(kept);
        }
        result.members.len = @min(ids.items.len, @import("../../../ai/tool_scope.zig").max_targets);
        @memcpy(result.members.ids[0..result.members.len], ids.items[0..result.members.len]);
        result.inventory = try ids.toOwnedSlice(self.allocator);
        return result;
    }

    pub fn currentScope(self: *AiHost) ?@import("../../../ai/tool_scope.zig").Scope {
        if (self.child_identity != null) {
            const owner = self.currentBinding() orelse return null;
            var result: @import("../../../ai/tool_scope.zig").Scope = .{ .owner = owner, .content = self.ownerContent(owner), .members = .{} };
            const record = self.childRecord() orelse return null;
            const targets = if (record.binding != null) self.shared_service.?.service.store.agent(self.child_identity.?).?.targets else @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record).targets;
            for (targets) |target| if (self.tabForSession(@backingInt(target.session_id))) |tab| if (tab.content_owner == .session and tab.content_owner.session.eql(target) and result.members.len < result.members.ids.len) {
                result.members.ids[result.members.len] = @backingInt(target.session_id);
                result.members.len += 1;
            };
            if (result.content == null) return null;
            return result;
        }
        const owner = self.currentBinding() orelse return null;
        const bound = self.resolveOwner(owner) orelse return null;
        var scope: @import("../../../ai/tool_scope.zig").Scope = .{ .owner = owner, .content = bound.content, .members = .{} };
        var ids: std.ArrayList(u64) = .empty;
        defer ids.deinit(self.allocator);
        self.appendTabCards(bound, &ids) catch return null;
        if (ids.items.len > scope.members.ids.len) return null;
        @memcpy(scope.members.ids[0..ids.items.len], ids.items);
        scope.members.len = ids.items.len;
        return if (scope.members.len == 0) null else scope;
    }

    /// tab 能否启动 AI 由卡片派生（PLUGIN_ARCH_PLAN 2.5.8 M9）：卡片类型声明了 `ai` 就能。只看
    /// 卡片类型，与放置无关；tab 上没有任何 AI 配置。会话组 tab 的作用域由各成员卡片逐张派生
    /// （`captureOwnerScope` / `currentScope` 对成员调用本函数）。
    fn supportsAssistant(self: *AiHost, tab: *const ws.SessionTab) bool {
        _ = self;
        // The assistant belongs to the retained tab, while its tools require a
        // live SessionHost. A disconnected/closing terminal must keep its AI
        // conversation and entry points available, so only the card type decides.
        return tab.content_owner == .session and tab.card_type.ai != null;
    }

    /// 工具是否可用（PLUGIN_ARCH_PLAN 2.5.8 第 8 条，按卡片派生）：单卡 tab 看这张卡片的 AI 声明与
    /// 运行状态（断开、关闭中、失败、本机进程未运行、终端 EOF、生命周期不是 attached / ready）；
    /// 分屏（会话组）tab 是"组内至少一张 AI 卡片可用"。条件与 `host.tab_context` 的 `available`
    /// 是同一个函数（`ai_tab_context.unavailableReason`）。
    fn assistantToolsAvailable(self: *AiHost, owner: ai_attachments.Owner) bool {
        const bound = self.resolveOwner(owner) orelse return false;
        const host = self.application_host orelse return false;
        const card_state = @import("../tools/host/ai_tab_context.zig");
        switch (bound.content) {
            .session => return card_state.unavailableReason(host, bound.card orelse return false) == null,
            .group => |id| {
                const group = (self.roster orelse return false).findById(std.math.cast(u32, id) orelse return false) orelse return false;
                return card_state.groupToolsAvailable(host, group);
            },
        }
    }

    pub fn tabForSession(self: *AiHost, session_id: u64) ?*ws.SessionTab {
        const workspace = self.workspace orelse return null;
        for (workspace.tabs.items) |tab| if (tab.content_owner == .session and @backingInt(tab.content_owner.session.session_id) == session_id) return tab;
        return null;
    }

    pub fn syncOwner(self: *AiHost) !void {
        if (self.child_identity != null) return self.syncChildView();
        const current_owner = self.currentBinding() orelse {
            // A tab without AI (or none) is current: the open panel stays open on its own tab and
            // folds away (the presentation commit); switching back unfolds it where it was.
            if (self.card) |card| card.cancel();
            self.requestPresentation();
            return;
        };
        const Owner = @import("../../../ai/tool_scope.zig").Owner;
        if (self.assistant_states == null) self.assistant_states = &(try self.shared()).presentations;
        if (self.lifecycle_command) |command| if (command.kind != .copy and self.lifecycle_confirmed and command.owner.eql(current_owner)) return;
        if (self.message_action) |pending| if (pending.kind == .fork and pending.conversation == self.display_conversation) {
            if (self.display_owner) |display| if (display.eql(current_owner)) return;
            self.message_action = null;
        };
        const selected_state = try self.assistant_states.?.get(current_owner);
        selected_state.controls.ensureDefaults(self.effectiveAi());
        const selected_id = selected_state.id;
        const owner_changed = self.display_owner == null or !self.display_owner.?.eql(current_owner);
        if (self.display_owner == null or !self.display_owner.?.eql(current_owner) or self.display_conversation != selected_id) try self.preservePendingEdit();
        try self.persistDisplayedDraft();
        const switching = owner_changed or self.display_conversation != selected_id;
        const now = @import("../../../platform/realtime.zig").monotonicNs();
        // Capture an in-flight display at most once every two seconds. Final
        // completion, tab switches and explicit actions still flush immediately.
        if (switching or (self.execution().thread_state.load(.acquire) == 1 and now - self.presentation_saved_at_ns >= 2 * std.time.ns_per_s)) {
            self.presentation_saved_at_ns = now;
            try self.saveDisplayedPresentation();
        }
        _ = try self.bindAttached(current_owner);
        if (self.display_owner) |owner| if (Owner.eql(owner, current_owner) and self.display_conversation == selected_id) return;
        if (self.card) |card| card.cancel();
        if (self.compaction.job != null) self.compaction.cancel();
        // Where this tab shows its AI (open, placement, docked into its split) is the tab's, not the
        // conversation's (LIFECYCLE.md §1): a change of conversation within the tab keeps it.
        const tab_presentation = self.controller.model.ownerPresentation();
        if (self.assistant_states == null) self.assistant_states = &(try self.shared()).presentations;
        const store = self.assistant_states.?;
        // Reserve the destination before moving any live state. Allocation
        // failure must leave the currently visible conversation intact.
        _ = try store.get(current_owner);
        if (self.display_owner != null) {
            const draft = try self.allocator.dupe(u8, self.prompt.get());
            errdefer self.allocator.free(draft);
            const saved = store.find(self.display_conversation orelse return) orelse return;
            const saved_id = saved.id;
            const saved_conversation_id = saved.conversation_id;
            const initial_owner = saved.initial_owner;
            const binding_revision = saved.binding_revision;
            const saved_owner = saved.owner;
            const selected = saved.selected;
            const listed = saved.listed;
            const phase = saved.phase;
            const closed = saved.closed;
            const ended = saved.ended;
            const historical_environment = saved.historical_environment;
            const controls = saved.controls;
            const title = saved.title;
            // An open panel stays open on its own tab: switching back restores it. A conversation
            // that leaves the tab (this tab now shows another one) takes none of the tab's
            // presentation along — above all not the split leaf the tab's AI is docked into.
            const presentation = if (owner_changed) self.controller.model else self.controller.model.withOwnerPresentation(.{});
            saved.controls = .{};
            saved.deinit(self.allocator);
            saved.* = .{ .title = title, .id = saved_id, .conversation_id = saved_conversation_id, .initial_owner = initial_owner, .binding_revision = binding_revision, .selected = selected, .listed = listed, .phase = phase, .closed = closed, .ended = ended, .historical_environment = historical_environment, .tool_results = self.tool_results, .controls = controls, .owner = saved_owner, .current_turn = self.current_turn, .history = self.history, .wire_history = self.wire_history, .stream = self.controller.stream, .last_user_text = self.last_user_text, .last_user_wire = self.last_user_wire, .last_user_attachments = self.last_user_attachments, .last_user_images = self.last_user_images, .draft = draft, .model = presentation };
            self.tool_results = @import("../../../ai/tool_results.zig").Store.init(self.allocator);
            self.current_turn = .{};
            self.history = .empty;
            self.wire_history = .{};
            self.controller.stream = @import("../../../ai/card_stream.zig").Stream.init(self.allocator);
            self.last_user_text = null;
            self.last_user_wire = null;
            self.last_user_attachments = null;
            self.last_user_images = null;
        }
        const saved = try store.get(current_owner);
        self.display_conversation = saved.id;
        const loaded_listed = saved.listed;
        const loaded_phase = saved.phase;
        self.tool_results.deinit();
        self.tool_results = saved.tool_results orelse @import("../../../ai/tool_results.zig").Store.init(self.allocator);
        saved.tool_results = null;
        self.current_turn = saved.current_turn;
        self.history = saved.history;
        self.wire_history = saved.wire_history;
        self.controller.stream.deinit();
        self.controller.stream = saved.stream;
        self.last_user_text = saved.last_user_text;
        self.last_user_wire = saved.last_user_wire;
        self.last_user_attachments = saved.last_user_attachments;
        self.last_user_images = saved.last_user_images;
        if (self.images_view) |view| view.dismiss();
        // Changing tabs restores that tab's own presentation (kept with the conversation it shows);
        // changing conversations within one tab keeps the tab's: an open panel stays open where it
        // floats, a docked one stays in its pane and the pane shows the new conversation.
        self.controller.model = if (owner_changed) saved.model else saved.model.withOwnerPresentation(tab_presentation);
        if (owner_changed) self.presentation_switched = true;
        self.prompt.set(saved.draft orelse "");
        if (saved.draft) |draft| self.allocator.free(draft);
        const controls = saved.controls;
        const conversation_id = saved.conversation_id;
        const initial_owner = saved.initial_owner;
        const binding_revision = saved.binding_revision;
        const title = saved.title;
        saved.* = .{ .title = title, .id = selected_id, .conversation_id = conversation_id, .initial_owner = initial_owner, .binding_revision = binding_revision, .listed = loaded_listed, .phase = loaded_phase, .controls = controls, .owner = current_owner, .stream = @import("../../../ai/card_stream.zig").Stream.init(self.allocator) };
        if (self.shared_service) |shared_host| if (shared_host.service.store.find(conversation_id)) |record| {
            self.display_content_revision = record.content_revision;
            if (self.wire_history.messages.len == 0 and record.history.messages.len != 0) {
                self.wire_history = try @import("../../../ai/wire_history.zig").History.copy(self.allocator, record.history.messages, "");
                self.wire_history.usage = record.history.usage;
            }
            if (self.history.items.len == 0 and self.last_user_text == null) {
                const presentation = @import("../../../ai/conversation_presentation.zig");
                self.history = try presentation.restoreHistory(self.allocator, record.presentation, record.last_turn, record.history.messages);
            }
        };
        self.setFeedback("");
        self.rollback_to_start = false;
        self.image_gate = null;
        self.recall_index = null;
        self.editing_index = null;
        self.edit_seed = null;
        self.edit_text = null;
        if (self.recall_draft) |value| self.allocator.free(value);
        self.recall_draft = null;
        self.display_owner = current_owner;
        self.conversation_dirty = true;
        self.streaming_label = null;
        self.captureTerminalFocus();
        if (self.tail_follow) |*follow| follow.reset();
        self.controller.model.setPrompt(self.last_user_text orelse "");
    }

    fn remoteScope(raw: *anyopaque, owner: ai_attachments.Owner) ?@import("../../../ai/tool_scope.zig").Scope {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.child_identity != null) {
            const selected = self.currentScope() orelse return null;
            return if (selected.owner.eql(owner)) selected else null;
        }
        const workspace = self.workspace orelse return null;
        const bound = self.resolveOwner(owner) orelse return null;
        if (owner.legacy()) return null;
        var scope: @import("../../../ai/tool_scope.zig").Scope = .{ .owner = owner, .content = bound.content, .members = .{} };
        switch (bound.content) {
            .session => |id| {
                const tab = bound.card orelse return null;
                if (tab.closing) return null;
                scope.members.ids[0] = id;
                scope.members.len = 1;
            },
            .group => |id| {
                const roster = self.roster orelse return null;
                for (roster.groups.items) |group| if (group.id == id) {
                    for (group.members.items) |member| if (member.active) {
                        for (workspace.tabs.items) |tab| if (tab.id == member.pane_id and !tab.closing and tab.content_owner == .session) {
                            if (scope.members.len == scope.members.ids.len) return null;
                            scope.members.ids[scope.members.len] = @backingInt(tab.content_owner.session.session_id);
                            scope.members.len += 1;
                        };
                    };
                };
                if (scope.members.len == 0) return null;
            },
        }
        return scope;
    }
    fn remoteEnsure(raw: *anyopaque, source: @import("../attachments/view/ai_remote_picker.zig").Source) !@import("../../../host/file_binding_host.zig").Bindings {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const files = self.file_application orelse return error.FileSourceUnavailable;
        const workspace = self.workspace orelse return error.FileSourceUnavailable;
        const owner = if (self.remote_picker) |picker| picker.owner orelse return error.TargetNotAuthorized else return error.TargetNotAuthorized;
        const allowed = remoteScope(self, owner) orelse return error.TargetNotAuthorized;
        _ = allowed.validate(&.{@backingInt(source.session.session_id)}) catch return error.TargetNotAuthorized;
        const tab = self.tabForSession(@backingInt(source.session.session_id)) orelse return error.TargetNotAuthorized;
        if (tab.closing or tab.content_owner != .session or !tab.content_owner.session.eql(source.session)) return error.StaleOwner;
        if (workspace.app_config.transfer.dedicated_connection) return files.ensureReadonlySource(source.session);
        const runtime = tab.runtime orelse return error.FileSourceUnavailable;
        const provider = try runtime.workerPtr().readonlyProvider();
        return files.ensureSharedReadonlySource(source.session, provider);
    }
    fn stageRemote(raw: *anyopaque, owner: ai_attachments.Owner, reference: *ai_attachments.ContentRef) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const scope = remoteScope(raw, owner) orelse return error.StaleOwner;
        const content = reference.content() orelse return error.EmptyAttachmentResult;
        if (content.source != .remote_file) return error.InvalidRemoteSource;
        _ = try scope.validate(&.{@backingInt(content.source.remote_file.owner.session_id)});
        const draft = try self.attachmentDraft(owner);
        const ticket = try draft.begin();
        errdefer _ = draft.cancel(ticket);
        try draft.stage(ticket, reference);
        if (self.display_owner) |display| if (display.eql(owner)) {
            if (self.attachments_view) |view| {
                try view.update(draft);
                try view.restoreCandidate(owner);
            }
        };
        self.wake();
    }
    fn attachRemote(raw: *anyopaque, owner: ai_attachments.Owner, reference: *ai_attachments.ContentRef) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const scope = remoteScope(raw, owner) orelse return error.StaleOwner;
        const content = reference.content() orelse return error.EmptyAttachmentResult;
        if (content.source != .remote_file) return error.InvalidRemoteSource;
        _ = try scope.validate(&.{@backingInt(content.source.remote_file.owner.session_id)});
        const source = self.remoteFileSource(@backingInt(content.source.remote_file.owner.session_id)) orelse return error.StaleOwner;
        if (!source.available or !source.session.eql(content.source.remote_file.owner)) return error.StaleOwner;
        const draft = try self.attachmentDraft(owner);
        const ticket = try draft.begin();
        errdefer _ = draft.cancel(ticket);
        try draft.stage(ticket, reference);
        _ = try draft.attach(ticket);
        if (self.display_owner) |display| if (display.eql(owner)) {
            if (self.attachments_view) |view| try view.update(draft);
        };
        self.wake();
    }
    fn remoteFileSource(self: *AiHost, id: u64) ?@import("../attachments/view/ai_remote_picker.zig").Source {
        const domain = self.application_host orelse return null;
        const tab = self.tabForSession(id) orelse return null;
        if (tab.content_owner != .session) return null;
        const state = domain.sessions.queryState(tab.content_owner.session) orelse return null;
        const manifest = domain.sessions.manifestFor(state.handle) orelse return null;
        if (!manifest.integration.auxiliary_readonly and domain.sessions.queryService(state.handle, .file_read) == .unsupported) return null;
        return .{ .session = state.handle, .name = tab.titleSlice(), .cwd = "", .available = state.lifecycle == .attached and !tab.closing };
    }
    fn remoteFilesAvailable(self: *AiHost, owner: ai_attachments.Owner) bool {
        const files = self.file_application orelse return false;
        if (files.file_host == null) return false;
        const scope = remoteScope(self, owner) orelse return false;
        for (scope.memberIds()) |id| {
            if (self.remoteFileSource(id)) |source| if (source.available) return true;
        }
        return false;
    }
    fn chooseRemoteFile(self: *AiHost, owner: ai_attachments.Owner) !void {
        if (!self.remoteFilesAvailable(owner)) return error.FileSourceUnavailable;
        const scope = remoteScope(self, owner) orelse return error.StaleOwner;
        const files = self.file_application orelse return error.FileSourceUnavailable;
        if (self.remote_picker == null) {
            const view = try @import("../attachments/view/ai_remote_picker.zig").View.mount(self.cx, self.contentScope() orelse return error.MissingAssistantScope, files.file_host orelse return error.FileSourceUnavailable, .{ .context = self, .ensure = remoteEnsure, .live = remoteScope, .stage = stageRemote, .attach = attachRemote });
            const parent = self.attachment_preview_holder orelse return error.MissingAssistantScope;
            // The holder already has 14px outer padding.
            view.root.setStyleInline(self.allocator, .{ .padding = .{} });
            try parent.appendChild(self.allocator, view.root);
            self.remote_picker = view;
        }
        var sources: [16]@import("../attachments/view/ai_remote_picker.zig").Source = undefined;
        var directories: [16]?[]u8 = @splat(null);
        defer for (directories) |directory| if (directory) |bytes| self.allocator.free(bytes);
        var count: usize = 0;
        for (scope.members.ids[0..scope.members.len]) |id| {
            var source = self.remoteFileSource(id) orelse continue;
            const tab = self.tabForSession(id) orelse continue;
            if (tab.runtime) |runtime| directories[count] = runtime.workerPtr().copyCwd(self.allocator) catch null;
            source.cwd = directories[count] orelse "";
            sources[count] = source;
            count += 1;
        }
        if (self.attachments_view) |view| view.dismiss();
        if (self.images_view) |view| view.dismiss();
        if (self.attachment_preview_holder) |holder| holder.setDisplay(.flex);
        try self.remote_picker.?.open(owner, sources[0..count]);
    }

    fn imageDraft(self: *AiHost, owner: ai_images.Owner) !*ai_images.Draft {
        if (self.assistant_states == null) self.assistant_states = &(try self.shared()).presentations;
        return if (self.child_identity != null) self.assistant_states.?.imageDraftForState(self.display_conversation orelse return error.ConversationNotFound) else self.assistant_states.?.imageDraft(owner);
    }

    fn attachmentConversation(self: *AiHost, id: ?@import("../../../host/identity.zig").ConversationId) ?*@import("../../../ai/assistant_store.zig").State {
        const store = if (self.assistant_states) |value| value else return null;
        const state = store.findConversation(id orelse return null) orelse return null;
        if (state.closed or !self.attachmentOwnerExists(state.owner)) return null;
        return state;
    }

    fn imageDraftForTicket(self: *AiHost, ticket: ai_images.Ticket) !*ai_images.Draft {
        _ = self.attachmentConversation(ticket.conversation_id) orelse return error.StaleAttachment;
        return self.assistant_states.?.imageDraftForTicket(ticket) orelse error.StaleAttachment;
    }

    fn attachmentTicketDisplayed(self: *AiHost, ticket: anytype) bool {
        const state = self.attachmentConversation(ticket.conversation_id) orelse return false;
        return self.display_conversation == state.id;
    }

    fn chooseImage(self: *AiHost, owner: ai_images.Owner) !void {
        if (self.attachment_picker_active) return error.AttachmentPickerBusy;
        const sdk = self.cx.system_sdk orelse return error.NotSupported;
        const conversation_id = (try self.imageDraft(owner)).conversation_id;
        self.attachment_picker_active = true;
        defer self.attachment_picker_active = false;
        var buffer: [4096]u8 = undefined;
        const path = try @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .open_file, .title = "选择图片（最多 4 张，单张 " ++ @import("../../../shared/base/format.zig").comptimeBytes(ai_images.max_bytes) ++ "）" }, &buffer) orelse return;
        const state = self.attachmentConversation(conversation_id) orelse return error.StaleAttachment;
        const draft = self.assistant_states.?.imageDraftFor(state.id) orelse return error.StaleAttachment;
        try self.addImageToDraft(draft, path);
    }

    fn addImagePath(self: *AiHost, owner: ai_images.Owner, path: []const u8) !void {
        if (!self.attachmentOwnerExists(owner)) return error.StaleAttachment;
        const draft = try self.imageDraft(owner);
        try self.addImageToDraft(draft, path);
    }

    fn addImageToDraft(self: *AiHost, draft: *ai_images.Draft, path: []const u8) !void {
        @import("../../../host/ai_image_snapshot.zig").preflight(self.cx.io, path, .{}) catch |err| switch (err) {
            error.ImageTooLarge => return self.attachLocalReference(draft.conversation_id, path, .{ .reason = .size_limit }),
            else => return err,
        };
        if (draft.items.items.len >= ai_images.max_count) return self.attachLocalReference(draft.conversation_id, path, .{ .reason = .image_count });
        const ticket = try draft.begin(path, .{});
        errdefer _ = draft.remove(ticket.id);
        const reader = try AiImageReader.start(self.allocator, ticket, path, .{});
        errdefer reader.deinit();
        reader.conversation = (self.attachmentConversation(ticket.conversation_id) orelse return error.StaleAttachment).id;
        try self.image_readers.append(self.allocator, reader);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn attachLocalReference(self: *AiHost, conversation_id: ?@import("../../../host/identity.zig").ConversationId, path: []const u8, reason: ai_attachments.LocalReference) !void {
        const state = self.attachmentConversation(conversation_id) orelse return error.StaleAttachment;
        const draft = try self.assistant_states.?.attachmentDraftForState(state.id);
        const ticket = try draft.begin();
        errdefer _ = draft.cancel(ticket);
        var metadata = reason;
        if (metadata.size_bytes == null) {
            const stat = try std.Io.Dir.cwd().statFile(self.cx.io, path, .{ .follow_symlinks = false });
            if (stat.kind != .file) return error.NotRegularLocalFile;
            metadata.size_bytes = stat.size;
        }
        var reference = try ai_attachments.ContentRef.createLocalReference(self.allocator, path, metadata);
        defer reference.release();
        _ = try draft.complete(ticket, &reference);
        if (self.attachmentTicketDisplayed(ticket)) if (self.attachments_view) |view| try view.update(draft);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn pasteImages(self: *AiHost, owner: ai_images.Owner) !void {
        const sdk = self.cx.system_sdk orelse return error.NotSupported;
        const count = try sdk.clipboardImageCount();
        if (count == 0) return error.NoClipboardImage;
        const draft = try self.imageDraft(owner);
        if (count > ai_images.max_count - @min(ai_images.max_count, draft.items.items.len)) return error.TooManyImages;
        // Capture the clipboard once; retries use these owned bytes.
        for (0..count) |index| {
            var image = (try sdk.clipboardGetImageAlloc(self.allocator, index)) orelse return error.NoClipboardImage;
            defer image.deinit(self.allocator);
            const bytes = image.raw_bytes orelse return error.UnsupportedImage;
            var label: [80]u8 = undefined;
            const name = try std.fmt.bufPrint(&label, "粘贴图片-{d}.png", .{index + 1});
            const ticket = try draft.beginBytes(name, bytes, .{});
            errdefer _ = draft.remove(ticket.id);
            const reader = try AiImageReader.startBytes(self.allocator, ticket, name, bytes, .{});
            errdefer reader.deinit();
            reader.conversation = (self.attachmentConversation(ticket.conversation_id) orelse return error.StaleAttachment).id;
            try self.image_readers.append(self.allocator, reader);
        }
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn pumpImages(self: *AiHost) !void {
        var index: usize = 0;
        while (index < self.image_readers.items.len) {
            const reader = self.image_readers.items[index];
            if (self.attachmentConversation(reader.ticket.conversation_id) == null) reader.cancel();
            if (!reader.poll()) {
                index += 1;
                continue;
            }
            const completion = reader.take().?;
            reader.deinit();
            _ = self.image_readers.orderedRemove(index);
            const store = if (self.assistant_states) |v| v else return;
            const draft = store.imageDraftForTicket(completion.ticket) orelse {
                var result = completion.result catch continue;
                result.release();
                continue;
            };
            if (self.attachmentConversation(completion.ticket.conversation_id) == null) {
                if (completion.result) |value| {
                    var reference = value;
                    reference.release();
                } else |_| {}
                _ = draft.remove(completion.ticket.id);
                continue;
            }
            var reference = completion.result catch |err| {
                if (err == error.Cancelled) {
                    _ = draft.remove(completion.ticket.id);
                } else if (err == error.ImageTooLarge) {
                    const item = draft.find(completion.ticket) orelse continue;
                    if (!std.fs.path.isAbsolute(item.path)) {
                        _ = draft.fail(completion.ticket, err);
                        if (self.attachmentTicketDisplayed(completion.ticket)) attachmentViewError(self, err);
                        continue;
                    }
                    self.attachLocalReference(completion.ticket.conversation_id, item.path, .{ .reason = .image_limit }) catch |fallback_error| {
                        _ = draft.fail(completion.ticket, fallback_error);
                        if (self.attachmentTicketDisplayed(completion.ticket)) attachmentViewError(self, fallback_error);
                        continue;
                    };
                    _ = draft.remove(completion.ticket.id);
                } else {
                    _ = draft.fail(completion.ticket, err);
                    if (self.attachmentTicketDisplayed(completion.ticket)) attachmentViewError(self, err);
                }
                continue;
            };
            draft.complete(completion.ticket, &reference) catch |err| {
                if (err != error.StaleAttachment) _ = draft.fail(completion.ticket, err);
            };
        }
        if (self.images_view) |view| {
            try view.update(if (self.display_owner) |owner| try self.imageDraft(owner) else null);
            if (self.attachments_view) |text_view| text_view.external_count = view.count;
        }
        self.promptChanged(self.prompt.get());
    }

    fn cancelImageReaders(self: *AiHost, owner: ?ai_images.Owner) void {
        var index: usize = 0;
        while (index < self.image_readers.items.len) {
            const reader = self.image_readers.items[index];
            if (owner) |selected| if (self.attachmentConversation(reader.ticket.conversation_id)) |state| if (!state.owner.eql(selected)) {
                index += 1;
                continue;
            };
            const ticket = reader.ticket;
            reader.cancel();
            reader.deinit();
            _ = self.image_readers.orderedRemove(index);
            const draft = self.imageDraftForTicket(ticket) catch continue;
            _ = draft.remove(ticket.id);
        }
    }

    fn removeImage(raw: *anyopaque, ticket: ai_images.Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const draft = try self.imageDraftForTicket(ticket);
        if (draft.find(ticket) == null) return error.StaleAttachment;
        for (self.image_readers.items) |reader| if (reader.ticket.eql(ticket)) reader.cancel();
        _ = draft.remove(ticket.id);
        if (self.images_view) |view| if (self.attachmentTicketDisplayed(ticket)) try view.update(draft);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn retryImage(raw: *anyopaque, ticket: ai_images.Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const draft = try self.imageDraftForTicket(ticket);
        const next = try draft.retry(ticket);
        errdefer _ = draft.fail(next, error.ImageReadFailed);
        const item = draft.find(next).?;
        const reader = if (item.source_bytes) |bytes| try AiImageReader.startBytes(self.allocator, next, item.path, bytes, item.limits) else try AiImageReader.start(self.allocator, next, item.path, item.limits);
        errdefer reader.deinit();
        reader.conversation = (self.attachmentConversation(next.conversation_id) orelse return error.StaleAttachment).id;
        try self.image_readers.append(self.allocator, reader);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn textPreviewVisibility(raw: *anyopaque, visible: bool) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        if (visible) if (self.images_view) |view| view.dismiss();
        attachmentPreviewVisibility(raw, visible);
    }

    fn imagePreviewVisibility(raw: *anyopaque, visible: bool) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        if (visible) {
            if (self.attachments_view) |view| view.dismiss();
            if (self.remote_picker) |picker| picker.close();
        }
        attachmentPreviewVisibility(raw, visible);
    }

    fn previewSentImage(raw: *anyopaque, reference: ai_images.ContentRef) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const view = self.images_view orelse return error.MissingAssistantScope;
        try view.openSentPreview(reference);
    }

    fn appendSentImages(self: *AiHost, parent: *ui.Node, bundle: *const ai_images.Bundle) !void {
        if (bundle.items.len == 0) return;
        if (self.conversation_scope == null) self.conversation_scope = try (self.contentScope() orelse return error.MissingAssistantScope).childScope();
        const view = try @import("../attachments/view/ai_image_attachments_view.zig").View.mount(self.cx, self.conversation_scope.?, .{ .context = self, .preview_sent = previewSentImage, .on_error = attachmentViewError }, self.attachment_preview_holder.?);
        if (self.images_view) |draft_view| view.app = draft_view.app;
        try view.updateSent(bundle);
        try parent.appendChild(self.allocator, view.root);
    }

    fn borrowImageRefs(self: *AiHost, bundle: ?ai_images.Bundle) ![]const ai_images.ContentRef {
        const value = bundle orelse return &.{};
        if (value.items.len == 0) return &.{};
        const refs = try self.allocator.alloc(ai_images.ContentRef, value.items.len);
        errdefer self.allocator.free(refs);
        for (value.items, refs) |item, *ref| ref.* = item.reference;
        try self.preflight_image_refs.append(self.allocator, refs);
        return refs;
    }
    fn clearPreflightImageRefs(self: *AiHost) void {
        for (self.preflight_image_refs.items) |refs| self.allocator.free(refs);
        self.preflight_image_refs.clearRetainingCapacity();
    }

    fn attachmentDraft(self: *AiHost, owner: ai_attachments.Owner) !*ai_attachments.Draft {
        if (self.assistant_states == null) self.assistant_states = &(try self.shared()).presentations;
        return if (self.child_identity != null) self.assistant_states.?.attachmentDraftForState(self.display_conversation orelse return error.ConversationNotFound) else self.assistant_states.?.attachmentDraft(owner);
    }

    fn validateAttachmentScope(self: *AiHost, allowed: @import("../../../ai/tool_scope.zig").Scope, bundle: *const ai_attachments.Bundle) !void {
        for (bundle.items) |item| {
            const content = item.reference.content() orelse continue;
            const source = switch (content.source) {
                .local_file, .local_reference => continue,
                .terminal => |value| value.owner,
                .remote_file => |value| value.owner,
            };
            allowed.validateDirectory(&.{@backingInt(source.session_id)}) catch return error.TargetNotAuthorized;
            const tab = self.tabForSession(@backingInt(source.session_id)) orelse return error.TargetNotAuthorized;
            if (tab.content_owner != .session or !tab.content_owner.session.eql(source)) return error.TargetNotAuthorized;
        }
    }

    fn attachmentDraftForTicket(self: *AiHost, ticket: ai_attachments.Ticket) !*ai_attachments.Draft {
        _ = self.attachmentConversation(ticket.conversation_id) orelse return error.StaleAttachment;
        return self.assistant_states.?.attachmentDraftForTicket(ticket) orelse error.StaleAttachment;
    }

    /// Explicit menu intent: the pane, assistant domain and selected anchors
    /// were frozen before opening the menu. Never submit or retarget tools.
    pub fn openTerminalSelection(self: *AiHost, intent: TerminalIntent) !void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        const workspace = self.workspace orelse return error.MissingAssistantOwner;
        const index = workspace.tabIndexById(intent.tab) orelse return error.StaleOwner;
        const tab = workspace.tabs.items[index];
        if (tab.closing or !tab.content_owner.eql(.{ .session = intent.source }) or tab.terminal == null) return error.StaleOwner;
        const surface = tab.terminal.?.terminal_surface;
        if (surface) |current| if (!current.owner.eql(intent.source)) return error.StaleOwner;
        if (intent.assistant_owner.legacy()) return error.StaleAssistantOwner;
        const intended = self.ownerContent(intent.assistant_owner) orelse return error.StaleAssistantOwner;
        switch (intended) {
            .session => |id| if (id != @backingInt(intent.source.session_id) or intent.assistant_owner.tab != @backingInt(intent.tab)) return error.StaleOwner,
            .group => |id| {
                if (workspace.active_group_view == null or @as(u64, workspace.active_group_view.?) != id) return error.StaleAssistantOwner;
                const current = self.currentScope() orelse return error.StaleAssistantOwner;
                if (!current.owner.eql(intent.assistant_owner)) return error.StaleAssistantOwner;
                _ = try current.validate(&.{@backingInt(intent.source.session_id)});
                if (current.members.len != intent.member_count) return error.StaleAssistantOwner;
                for (intent.members[0..intent.member_count]) |member| {
                    _ = try current.validate(&.{@backingInt(member.session_id)});
                    const original = self.tabForSession(@backingInt(member.session_id)) orelse return error.StaleAssistantOwner;
                    if (original.closing or original.content_owner != .session or !original.content_owner.session.eql(member)) return error.StaleAssistantOwner;
                }
            },
        }
        var reference: ai_attachments.ContentRef = .{};
        defer reference.release();
        if (intent.selection) |selected| {
            const reader = @import("../../../host/ai_terminal_selection.zig");
            var captured = try reader.capture(self.allocator, (surface orelse return error.StaleOwner).service, intent.source, selected, reader.max_service_bytes);
            defer captured.deinit();
            reference = try @import("../../../ai/terminal_text_attachments.zig").createSelection(self.allocator, .{ .owner = captured.owner, .source_name = tab.titleSlice(), .source_version = captured.source_version, .selected_rows = captured.selected_rows, .selection = captured.selection }, captured.bytes, @import("../../../platform/realtime.zig").milliseconds(self));
        }
        if (intent.legacy_selection) |selected| {
            if (surface != null or tab.terminal.?.history.selected != null) return error.StaleSelection;
            var captured = try tab.terminal.?.captureOwnedSelection(self.allocator, intent.source, selected.range, selected.source_version);
            defer captured.deinit();
            reference = try @import("../../../ai/terminal_text_attachments.zig").createSelection(self.allocator, .{ .owner = captured.owner, .source_name = tab.titleSlice(), .source_version = captured.source_version, .selected_rows = captured.selected_rows, .selection = captured.selection, .legacy_range = selected.range }, captured.bytes, @import("../../../platform/realtime.zig").milliseconds(self));
        }
        if (intended == .session and (workspace.active_tab != index or workspace.active_group_view != null)) workspace.selectTab(index);
        try self.syncOwner();
        const owner = self.display_owner orelse return error.MissingAssistantOwner;
        if (!owner.eql(intent.assistant_owner)) return error.StaleAssistantOwner;
        self.captureTerminalFocus();
        self.controller.model.visible = true;
        self.controller.model.expanded = true;
        self.refresh("AI 助手");
        if (reference.content() != null) {
            const draft = try self.attachmentDraft(owner);
            const ticket = try draft.beginTerminal(intent.source);
            errdefer _ = draft.cancel(ticket);
            try draft.stage(ticket, &reference);
            _ = try draft.attach(ticket);
            if (self.attachments_view) |view| try view.update(draft);
            self.promptChanged(self.prompt.get());
        } else self.focusComposer();
        self.wake();
    }

    fn chooseLocalText(self: *AiHost, owner: ai_attachments.Owner, replacement: ?ai_attachments.Ticket) !void {
        if (self.attachment_picker_active) return error.AttachmentPickerBusy;
        const sdk = self.cx.system_sdk orelse return error.NotSupported;
        const draft = if (replacement) |ticket| try self.attachmentDraftForTicket(ticket) else try self.attachmentDraft(owner);
        const ticket = try draft.begin();
        errdefer if (self.attachmentDraftForTicket(ticket)) |current| {
            _ = current.cancel(ticket);
        } else |_| {};
        self.attachment_picker_active = true;
        defer self.attachment_picker_active = false;
        var buffer: [4096]u8 = undefined;
        const path = try @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .open_file, .title = "选择本地文件" }, &buffer) orelse {
            if (self.attachmentDraftForTicket(ticket)) |current| {
                _ = current.cancel(ticket);
            } else |_| {}
            self.promptChanged(self.prompt.get());
            return;
        };
        const current = try self.attachmentDraftForTicket(ticket);
        if (!current.contains(ticket)) return error.StaleAttachment;
        const reader = try AiAttachmentReader.start(self.allocator, ticket, path);
        errdefer reader.deinit();
        reader.replaces = replacement;
        reader.conversation = (self.attachmentConversation(ticket.conversation_id) orelse return error.StaleAttachment).id;
        try self.attachment_readers.append(self.allocator, reader);
        self.promptChanged(self.prompt.get());
        if (self.attachmentTicketDisplayed(ticket)) self.refresh("正在处理本地文件…");
        self.wake();
    }

    /// 归属的 tab 是否还在（单卡 tab 的卡片仍在，或组 tab 的会话组仍在）。
    fn attachmentOwnerExists(self: *AiHost, owner: ai_attachments.Owner) bool {
        return self.resolveOwner(owner) != null;
    }

    fn cancelAttachmentReaders(self: *AiHost, owner: ?ai_attachments.Owner) void {
        var index: usize = 0;
        while (index < self.attachment_readers.items.len) {
            const reader = self.attachment_readers.items[index];
            if (owner) |selected| if (self.attachmentConversation(reader.ticket.conversation_id)) |state| if (!state.owner.eql(selected)) {
                index += 1;
                continue;
            };
            const ticket = reader.ticket;
            reader.cancel();
            reader.deinit();
            _ = self.attachment_readers.orderedRemove(index);
            if (self.assistant_states) |store| {
                const draft = store.attachmentDraftForTicket(ticket) orelse continue;
                _ = draft.cancel(ticket);
            }
        }
    }

    fn pumpAttachments(self: *AiHost) !void {
        var index: usize = 0;
        while (index < self.attachment_readers.items.len) {
            const reader = self.attachment_readers.items[index];
            if (self.attachmentConversation(reader.ticket.conversation_id) == null) reader.cancel();
            if (!reader.poll()) {
                index += 1;
                continue;
            }
            const completion = reader.take().?;
            const replacement = reader.replaces;
            reader.deinit();
            _ = self.attachment_readers.orderedRemove(index);
            const store = if (self.assistant_states) |v| v else return;
            const draft = store.attachmentDraftForTicket(completion.ticket) orelse {
                var result = completion.result catch continue;
                result.release();
                continue;
            };
            if (self.attachmentConversation(completion.ticket.conversation_id) == null) {
                if (completion.result) |value| {
                    var reference = value;
                    reference.release();
                } else |_| {}
                _ = draft.cancel(completion.ticket);
                continue;
            }
            var selected = completion.result catch |err| {
                _ = draft.cancel(completion.ticket);
                self.attachmentFailure(completion.ticket, err);
                continue;
            };
            defer selected.release();
            if (selected == .image) {
                if (!draft.contains(completion.ticket)) continue;
                _ = draft.cancel(completion.ticket);
                const state = self.attachmentConversation(completion.ticket.conversation_id) orelse continue;
                if (replacement) |old| {
                    var found = draft.candidate(old) != null;
                    for (draft.items.items) |item| if (item.id == old.id) {
                        found = true;
                        break;
                    };
                    if (!found or old.draft_epoch != draft.epoch) continue;
                }
                const image_draft = store.imageDraftForState(state.id) catch |err| {
                    self.attachmentFailure(completion.ticket, err);
                    continue;
                };
                const image_ticket = image_draft.begin(selected.image.content().?.path, .{}) catch |err| {
                    if (err == error.TooManyImages) {
                        self.attachLocalReference(completion.ticket.conversation_id, selected.image.content().?.path, .{ .reason = .image_count }) catch |fallback_error| {
                            self.attachmentFailure(completion.ticket, fallback_error);
                            continue;
                        };
                        if (replacement) |old| _ = draft.remove(old.id);
                        continue;
                    }
                    self.attachmentFailure(completion.ticket, err);
                    continue;
                };
                image_draft.complete(image_ticket, &selected.image) catch |err| {
                    _ = image_draft.remove(image_ticket.id);
                    self.attachmentFailure(completion.ticket, err);
                    continue;
                };
                if (replacement) |old| _ = draft.remove(old.id);
                if (self.attachmentTicketDisplayed(completion.ticket)) self.refresh("AI 助手");
                continue;
            }
            var reference = selected.file.retain();
            const byte_count = reference.content().?.bytes.len;
            draft.stageReplacing(completion.ticket, &reference, replacement) catch |err| {
                _ = draft.cancel(completion.ticket);
                if (err != error.StaleAttachment) self.attachmentFailure(completion.ticket, err);
                continue;
            };
            _ = draft.attach(completion.ticket) catch |err| {
                _ = draft.cancel(completion.ticket);
                self.attachmentFailure(completion.ticket, err);
                continue;
            };
            @import("../../../ai/tool_trace.zig").emit(.{ .event = "attachment_preview_ready", .owner = completion.ticket.owner, .draft_epoch = completion.ticket.draft_epoch, .attachment_id = completion.ticket.id, .bytes = byte_count });
            if (self.attachmentTicketDisplayed(completion.ticket)) self.refresh("AI 助手");
        }
        if (self.attachments_view) |view| {
            try view.update(if (self.display_owner) |owner| try self.attachmentDraft(owner) else null);
        }
        self.promptChanged(self.prompt.get());
    }

    fn attachmentFailure(self: *AiHost, ticket: ai_attachments.Ticket, err: anyerror) void {
        if (!self.attachmentTicketDisplayed(ticket)) return;
        const draft = self.attachmentDraftForTicket(ticket) catch return;
        if (draft.epoch != ticket.draft_epoch) return;
        self.refresh(switch (err) {
            error.LocalTextTooLarge => "文本超过 " ++ @import("../../../shared/base/format.zig").comptimeBytes(@import("../../../ai/local_text_attachments.zig").max_bytes) ++ "，请选择其他文件",
            error.NotRegularLocalFile, error.NotRegularLocalText => "所选路径不是普通文件，无法附加或预览",
            error.FileNotFound, error.NotDir => "本机文件不存在，请重新选择",
            error.BinaryLocalText => "此文件不是受支持的文本格式",
            error.InvalidLocalTextEncoding => "文本需要使用 UTF-8 编码",
            error.AccessDenied, error.PermissionDenied => "没有权限读取所选文件",
            error.LocalTextSourceChanged => "文件在读取期间发生变化，请重新选择",
            error.OutOfMemory => "内存不足，未添加附件",
            error.ImageTooLarge => "图片超过大小或像素限制，无法附加或预览",
            error.UnsupportedImage, error.InvalidImage => "图片格式不受支持或文件已损坏，无法预览",
            error.AnimatedImageUnsupported => "不支持多帧或动态图片，请选择静态图片",
            error.TooManyImages => "最多附加 4 张图片，请先移除其他图片",
            else => @errorName(err),
        });
    }

    fn removeAttachment(raw: *anyopaque, ticket: ai_attachments.Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const draft = try self.attachmentDraftForTicket(ticket);
        if (draft.epoch != ticket.draft_epoch) return error.StaleAttachment;
        for (self.attachment_readers.items) |reader| if (reader.ticket.eql(ticket)) reader.cancel();
        if (!draft.remove(ticket.id)) return error.StaleAttachment;
        if (self.attachments_view) |view| if (self.attachmentTicketDisplayed(ticket)) try view.update(draft);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn attachAttachment(raw: *anyopaque, ticket: ai_attachments.Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const draft = try self.attachmentDraftForTicket(ticket);
        _ = try draft.attach(ticket);
        if (self.attachments_view) |view| if (self.attachmentTicketDisplayed(ticket)) try view.update(draft);
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    fn reselectAttachment(raw: *anyopaque, ticket: ai_attachments.Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const draft = try self.attachmentDraftForTicket(ticket);
        if (draft.epoch != ticket.draft_epoch) return error.StaleAttachment;
        if (draft.candidate(ticket) == null) {
            var found = false;
            for (draft.items.items) |item| if (item.id == ticket.id) {
                found = true;
                break;
            };
            if (!found) return error.StaleAttachment;
        }
        try self.chooseLocalText(ticket.owner, ticket);
    }

    fn attachmentViewError(raw: *anyopaque, err: anyerror) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.refresh(switch (err) {
            error.ImageNotReady => "图片仍在处理中，请稍后预览",
            error.InvalidImage, error.UnsupportedImage => "图片格式不受支持或文件已损坏，无法预览",
            error.AnimatedImageUnsupported => "不支持多帧或动态图片，无法预览",
            error.ImageTooLarge => "图片超过大小或像素限制，无法预览",
            error.FileNotFound, error.NotDir => "本机文件不存在，无法预览",
            error.AccessDenied, error.PermissionDenied => "没有权限读取本机文件，无法预览",
            else => @errorName(err),
        });
    }

    fn previewSentAttachment(raw: *anyopaque, ticket: ai_attachments.Ticket, reference: ai_attachments.ContentRef) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const owner = self.display_owner orelse return error.StaleAttachment;
        if (!owner.eql(ticket.owner)) return error.StaleAttachment;
        const view = self.attachments_view orelse return error.MissingAssistantScope;
        try view.openSentPreview(ticket, reference);
    }

    fn attachmentPreviewVisibility(raw: *anyopaque, visible: bool) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // Portal previews never replace or resize the conversation viewport.
        _ = visible;
        self.wake();
    }

    /// The content view's capture handler: every input delivered into the AI's own views.
    fn attachmentPreviewEvent(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *AiHost = @ptrCast(@alignCast(raw orelse return .ignored));
        // Input to the AI's views asks for a pass (LIFECYCLE.md §5.1 “本地请求”): a view-model in the
        // content (the decision card's 稍后处理, a step's toggle, a queue row) may change what the pass
        // reads without calling the host. Pointer movement, hover, scrolling and focus are not input
        // to a model (the gate sees focus; the tail follow sees scrolling).
        switch (event) {
            .mouse_move, .mouse_enter, .mouse_leave, .scroll, .magnify, .focus, .blur, .ime_preedit => {},
            else => self.wake(),
        }
        switch (event) {
            .key_down => |key| if (key.key == .escape) {
                if (self.textarea) |textarea| if (textarea.imeIsComposing()) return .ignored;
                if (self.attachments_view) |view| if (view.escapePreview()) return .stop;
                if (self.images_view) |view| if (view.escapePreview()) return .stop;
            },
            else => {},
        }
        return .ignored;
    }

    pub fn archiveCommandError(raw: ?*anyopaque, hint: @import("../../../ai/command_error_hint.zig").Hint, preview: []const u8) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw orelse return));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const notifications = process_state.process_notifications orelse return;
        const window = self.notification_window orelse return;
        var command_length = @min(hint.command.len, 3072);
        while (!std.unicode.utf8ValidateSlice(hint.command[0..command_length])) command_length -= 1;
        const detail = try std.fmt.allocPrint(self.allocator, "命令  {s}\n输出  {s}\n退出码 {d}", .{ hint.command[0..command_length], preview, hint.exit_code });
        defer self.allocator.free(detail);
        var owner_name: []const u8 = "会话";
        if (self.workspace) |workspace| for (workspace.tabs.items) |tab| {
            if (tab.content_owner.eql(.{ .session = hint.owner })) {
                owner_name = tab.titleSlice();
                break;
            }
        };
        _ = try notifications.publish(.{ .owner_name = owner_name, .definition_id = "host.command_error", .owner = .{ .window_id = @backingInt(window), .content = .{ .session = hint.owner } }, .operation_id = hint.command_id, .event_revision = 1, .phase = .failed, .severity = .failure, .title = "命令执行失败", .detail = detail, .actions = &.{.{ .kind = .locate_owner, .label = "查看会话" }} });
    }

    pub fn openCommandError(raw: ?*anyopaque, hint: @import("../../../ai/command_error_hint.zig").Hint) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw orelse return error.MissingAssistantOwner));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const workspace = self.workspace orelse return error.MissingAssistantOwner;
        var source_index: ?usize = null;
        for (workspace.tabs.items, 0..) |tab, index| if (tab.content_owner.eql(.{ .session = hint.owner }) and !tab.closing and tab.terminal != null) {
            source_index = index;
            break;
        };
        const index = source_index orelse return error.StaleCommandHint;
        const terminal = &workspace.tabs.items[index].terminal.?;
        const surface = terminal.terminal_surface orelse return error.StaleCommandHint;
        if (!surface.owner.eql(hint.owner)) return error.StaleCommandHint;
        const original = terminal.commandErrorHint(hint.owner, hint.command_id) orelse return error.StaleCommandHint;
        if (original.end_sequence != hint.end_sequence or original.exit_code != hint.exit_code) return error.StaleCommandHint;
        const owner = tabOwner(workspace.tabs.items[index]);
        if (self.assistant_states == null) self.assistant_states = &(try self.shared()).presentations;
        const saved = try self.assistant_states.?.get(owner);
        const existing = if (self.display_owner != null and self.display_owner.?.eql(owner)) self.prompt.get() else saved.draft orelse "";
        const question = try @import("../../../ai/command_error_hint.zig").question(self.allocator, existing, original);
        defer self.allocator.free(question);
        // The explicit hint click opens its original session. Provider work is
        // untouched, and the captured command/context become only a draft.
        workspace.selectTab(index);
        try self.syncOwner();
        if (self.display_owner == null or !self.display_owner.?.eql(owner)) return error.StaleCommandHint;
        self.captureTerminalFocus();
        self.prompt.set(question);
        self.controller.model.visible = true;
        self.controller.model.expanded = true;
        self.refresh("AI 助手");
        self.focusComposer();
    }

    fn selectedControls(self: *AiHost) !*@import("../../../ai/assistant_store.zig").Controls {
        const owner = self.display_owner orelse return error.MissingAssistantOwner;
        const store = if (self.assistant_states) |value| value else return error.MissingAssistantOwner;
        const controls = if (self.child_identity != null) &(store.find(self.display_conversation orelse return error.ConversationNotFound) orelse return error.ConversationNotFound).controls else &(try store.get(owner)).controls;
        controls.ensureDefaults(self.effectiveAi());
        controls.ensureEffort(self.effectiveAi());
        return controls;
    }

    fn effectiveAi(self: *const AiHost) @import("../../../config/config.zig").Ai {
        const runtime = self.runtime_config orelse return .{};
        return self.model_discovery.effective(runtime.value.ai, runtime.value.config_revision);
    }
    fn controlsRevision(self: *const AiHost) u64 {
        const runtime = self.runtime_config orelse return 1;
        return runtime.value.config_revision *% 1000000 +% self.model_discovery.generation;
    }

    fn composerModelsOpened(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.model_discovery.refreshLists();
        self.wake();
    }

    fn composerUsageFixed(self: *AiHost) @import("../../../ai/context_usage.zig").Fixed {
        if (self.requestDisplayed()) return self.execution().request_usage_fixed;
        return if (self.wire_history.usage) |baseline| baseline.sample.fixed else .{};
    }

    fn composerUsage(self: *AiHost, selected: ?ai_provider_config.ProviderConfig) !@import("../../../ai/composer_usage_cache.zig").Summary {
        const had_baseline = self.wire_history.usage != null;
        const summary = self.composer_usage.readWithFixed(&self.wire_history, selected, self.composerUsageFixed());
        if (had_baseline and self.wire_history.usage == null) try self.saveDisplayedPresentation();
        return summary;
    }

    fn liveComposerUsage(self: *AiHost, selected: ?ai_provider_config.ProviderConfig) ?@import("../../../ai/live_context_usage.zig").Snapshot {
        if (!self.requestDisplayed() or self.execution().thread_state.load(.acquire) == 0) return null;
        const binding = self.execution().native_binding orelse return null;
        const model = selected orelse return null;
        const usage = @import("../../../ai/context_usage.zig");
        if (usage.modelKey(model) != usage.modelKey(binding.config)) return null;
        return self.execution().context_usage_mailbox.read(self.current_turn.id);
    }

    fn composerReserve(self: *AiHost) !usize {
        const budget = @import("../../../ai/local_text_request.zig");
        return self.composerUsageFixed().tokens() + budget.draftTokens(self.prompt.peek());
    }

    fn composerAction(raw: *anyopaque, envelope: @import("../composer/view/ai_composer_controls_view.zig").Envelope) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const owner = self.currentBinding() orelse return error.MissingAssistantOwner;
        const runtime = self.runtime_config orelse return error.MissingConfiguration;
        if (!owner.eql(envelope.owner) or envelope.revision != self.controlsRevision()) return error.StaleAssistantControls;
        try self.syncOwner();
        const controls = try self.selectedControls();
        if (self.child_identity != null and !self.childCanWrite()) return error.ParentBindingChanged;
        if (self.child_identity != null) switch (envelope.action) {
            .permission => |value| if (value == .auto and self.parentPermission() != .auto) return error.ParentPermissionCeiling,
            else => {},
        };
        switch (envelope.action) {
            .compact_context => {
                if (self.execution().thread_state.load(.acquire) != 0) return error.AssistantBusy;
                const selected = try ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model);
                const reserve = try self.composerReserve();
                try self.auto_compaction_attempts.put(self.allocator, self.display_conversation orelse return error.MissingAssistantOwner, self.compactionAttemptKey(selected.model));
                try self.compaction.startReserved(selected, self.compactionIdentity() orelse return error.MissingAssistantOwner, &self.wire_history, reserve);
                if (self.execution().attached_runner) |runner| {
                    runner.controller_busy = true;
                    self.compaction_agent = runner.agent.id;
                }
                self.conversation_dirty = true;
                self.wake();
            },
            .cancel_compaction => {
                self.compaction.cancel();
                self.conversation_dirty = true;
            },
            .model => |key| {
                const selection: ai_provider_config.ModelSelection = .{ .provider_id = key.provider_id, .model_id = key.model_id };
                _ = try ai_provider_config.fromSettingsSelection(self.effectiveAi(), selection);
                try controls.setModel(self.allocator, selection);
                self.wire_history.usage = null;
                try self.saveDisplayedPresentation();
                if (self.compaction.job != null) self.compaction.cancel();
                controls.thinking = null;
                controls.ensureEffort(self.effectiveAi());
            },
            .revoke_inventory => |conversation_id| {
                const state = self.assistant_states.?.find(self.display_conversation orelse return error.MissingAssistantOwner) orelse return error.MissingAssistantOwner;
                if (!state.conversation_id.eql(conversation_id)) return error.StaleAssistantControls;
                self.execution().inventory_approval.revokeConversation(state.conversation_id);
                self.execution().host_notice_revision = try @import("../../../host/identity.zig").advance(@max(1, self.execution().host_notice_revision));
            },
            .permission => |value| {
                if (self.child_identity == null and runtime.value.ai.permission_mode != value) try runtime.updateSetting(self.cx.io, std.Io.Dir.cwd(), "ai", "permission_mode", .{ .text = @tagName(value) });
                controls.permission = value;
                if (self.requestDisplayed()) {
                    const mode: @import("../../../ai/permission.zig").Mode = if (value == .auto) .auto else .confirm;
                    self.managerRef().setPermissionMode(mode);
                    self.execution().tool_bridge.setPermissionMode(mode);
                    self.execution().request_permission_mode = value;
                    self.conversation_dirty = true;
                }
            },
            .execution_mode => |value| {
                const mode = value orelse runtime.value.ai.execution_mode;
                if (self.child_identity == null and runtime.value.ai.execution_mode != mode) try runtime.updateSetting(self.cx.io, std.Io.Dir.cwd(), "ai", "execution_mode", .{ .text = @tagName(mode) });
                controls.execution_mode = mode;
            },
            .session_retention => |value| controls.session_retention = value,
            .effort => |value| {
                const key: ai_provider_config.ModelSelection = .{ .provider_id = value.model.provider_id, .model_id = value.model.model_id };
                const selected = try ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model);
                if (!std.mem.eql(u8, key.model_id, selected.model)) return error.StaleAssistantControls;
                if (controls.model) |current| {
                    if (!current.eql(key)) return error.StaleAssistantControls;
                } else if (!std.mem.eql(u8, key.provider_id, runtime.value.ai.default_provider)) return error.StaleAssistantControls;
                try ai_provider_config.validateEffort(self.effectiveAi(), key, value.value);
                if (controls.effort == value.value and controls.thinking != false) return;
                controls.effort = value.value;
                if (try ai_provider_config.supportsThinking(self.effectiveAi(), key)) controls.thinking = true;
                try self.publishReasoning(controls);
            },
            .thinking => |value| {
                const key: ai_provider_config.ModelSelection = .{ .provider_id = value.model.provider_id, .model_id = value.model.model_id };
                const selected = try ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model);
                if (!std.mem.eql(u8, selected.model, key.model_id)) return error.StaleAssistantControls;
                if (controls.model) |current| {
                    if (!current.eql(key)) return error.StaleAssistantControls;
                } else if (!std.mem.eql(u8, key.provider_id, runtime.value.ai.default_provider)) return error.StaleAssistantControls;
                if (!try ai_provider_config.supportsThinking(self.effectiveAi(), key)) return error.UnsupportedThinking;
                controls.thinking = value.enabled;
                if (!value.enabled) controls.effort = null;
                try self.publishReasoning(controls);
            },
            .attachment => |kind| switch (kind) {
                .image => try self.chooseImage(envelope.owner),
                .paste_image => try self.pasteImages(envelope.owner),
                .local_text => try self.chooseLocalText(envelope.owner, null),
                .remote_file => try self.chooseRemoteFile(envelope.owner),
            },
        }
        if (self.child_identity != null) {
            try self.saveChildPreferences();
            if (self.child_parent.?.child_dialog) |dialog| dialog.revision = self.childRecord().?.child_settings_revision;
        }
        self.composer_hash = null;
        self.wake();
    }

    fn publishReasoning(self: *AiHost, controls: *const @import("../../../ai/assistant_store.zig").Controls) !void {
        if (!self.requestDisplayed()) return;
        const backend = self.execution();
        const binding = backend.native_binding orelse return;
        const selected = try ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model);
        // A model picker change applies to later submissions. Never apply its
        // reasoning choices to a different model's currently running request.
        if (binding.config.kind != selected.kind or !std.mem.eql(u8, binding.config.endpoint, selected.endpoint) or !std.mem.eql(u8, binding.config.model, selected.model)) return;
        backend.live_reasoning.set(controls.effort, controls.thinking);
    }

    fn compactionIdentity(self: *AiHost) ?@import("../../../ai/context_compaction.zig").Identity {
        const scope = self.captureCurrentScope() catch return null;
        defer self.allocator.free(scope.inventory.?);
        const owner = self.display_owner orelse return null;
        if (!scope.owner.eql(owner)) return null;
        var generation = std.hash.Wyhash.init(0);
        for (scope.memberIds()) |session| {
            const tab = self.tabForSession(session) orelse return null;
            std.hash.autoHash(&generation, tab.content_owner);
        }
        return .{ .owner = owner, .conversation = self.display_conversation orelse return null, .revision = self.controlsRevision(), .scope_generation = generation.final() };
    }

    fn compactionAttemptKey(self: *AiHost, model: []const u8) u64 {
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, .{ @import("../../../ai/context_compaction.zig").fingerprint(self.wire_history.messages), self.controlsRevision(), self.display_conversation });
        hash.update(model);
        return hash.final();
    }

    fn refreshComposer(self: *AiHost) !void {
        if (self.compaction.job != null and self.compaction.pollWithCommit(self.allocator, self.compactionIdentity(), &self.wire_history, self.execution().thread_state.load(.acquire) != 0, .{ .context = self, .apply = commitCompactedHistory })) {
            self.composer_hash = null;
            self.conversation_dirty = true;
            if (self.compaction_agent) |agent| {
                if (self.shared_service.?.service.runnerFor(agent)) |runner| runner.controller_busy = false;
            }
            self.compaction_agent = null;
        }
        const view = self.composer_controls orelse return;
        const runtime = self.runtime_config orelse return;
        view.syncPasteShortcut(self.shortcuts().hint(.paste));
        const owner = self.display_owner orelse {
            try view.update(null);
            self.composer_hash = null;
            return;
        };
        const controls = try self.selectedControls();
        var config = runtime.value;
        var catalog_changed = false;
        // Discover models once the assistant is opened, not only after a first request: the native
        // binding is created by the first request, and a provider that lists its models only
        // automatically has no selectable model before discovery (the first send could never start).
        if (self.execution().native_binding != null or self.controller.model.visible) {
            if (try self.model_discovery.poll(config.ai, config.config_revision, @intCast(wallClockMsTransfer() / 1000))) {
                catalog_changed = true;
                self.composer_hash = null;
                // Only the welcome state depends on model readiness; an active
                // transcript keeps its nodes when catalog metadata arrives.
                if (self.last_user_text == null and self.history.items.len == 0) self.conversation_dirty = true;
            }
            // A running discovery publishes when it finishes; the next refresh is a time.
            if (!self.model_discovery.busy()) self.wakeAt(self.model_discovery.refreshDelaySeconds(config.ai, @intCast(wallClockMsTransfer() / 1000)) * 1000000000);
        }
        config.ai = self.effectiveAi();
        controls.ensureEffort(config.ai);
        const auto_selected = if (self.execution().thread_state.load(.acquire) == 0) ai_provider_config.fromSettingsSelection(config.ai, controls.model) catch null else null;
        if (auto_selected) |model| {
            const summary = try self.composerUsage(model);
            const reserve = try self.composerReserve();
            const output = @import("../../../ai/local_text_request.zig").outputTokens(0, model.context_window);
            const reserve_fits = reserve <= model.context_window -| output;
            const failed_conversation = if (self.assistant_states) |store| if (store.find(self.display_conversation orelse 0)) |saved| (saved.phase == .failed or saved.phase == .stopped) else false else false;
            if (reserve_fits and !failed_conversation and self.execution().thread_state.load(.acquire) == 0 and self.compaction.job == null and summary.can_compact and @import("../../../ai/context_compaction.zig").reachesThreshold(summary.tokens +| @import("../../../ai/local_text_request.zig").draftTokens(self.prompt.peek()), output, model.context_window)) {
                const attempt = self.compactionAttemptKey(model.model);
                if (self.auto_compaction_attempts.get(self.display_conversation orelse 0) != attempt) if (self.compactionIdentity()) |identity| {
                    try self.auto_compaction_attempts.put(self.allocator, self.display_conversation orelse return, attempt);
                    try self.compaction.startReserved(model, identity, &self.wire_history, reserve);
                    if (self.execution().attached_runner) |runner| {
                        runner.controller_busy = true;
                        self.compaction_agent = runner.agent.id;
                    }
                    self.conversation_dirty = true;
                    self.wake();
                };
            }
        }
        if (!(self.content_node orelse self.panel).isDisplayedInTree()) return;
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, owner);
        const remote_files_available = self.remoteFilesAvailable(owner);
        std.hash.autoHash(&hash, remote_files_available);
        std.hash.autoHash(&hash, config.config_revision);
        std.hash.autoHash(&hash, self.execution().thread_state.load(.acquire) == 1);
        std.hash.autoHash(&hash, controls.permission);
        std.hash.autoHash(&hash, controls.effort);
        std.hash.autoHash(&hash, controls.thinking);
        std.hash.autoHash(&hash, controls.execution_mode);
        std.hash.autoHash(&hash, controls.session_retention);
        std.hash.autoHash(&hash, self.model_discovery.generation);
        if (controls.model) |key| {
            hash.update(key.provider_id);
            hash.update(key.model_id);
        }
        const selected = ai_provider_config.fromSettingsSelection(config.ai, controls.model) catch null;
        const live_usage = self.liveComposerUsage(selected);
        const fixed_usage = if (live_usage) |live| live.fixed else self.composerUsageFixed();
        const context_tokens = fixed_usage.system_tokens;
        const history_usage = if (live_usage) |live| live.summary else try self.composerUsage(selected);
        var response_bytes: usize = 0;
        if (live_usage == null and self.execution().thread_state.load(.acquire) != 0) for (self.controller.stream.cards.items) |card| {
            response_bytes += switch (card) {
                .text => |text| text.len,
                .code => |code| code.body.len,
                else => 0,
            };
        };
        const compact_status = if (self.compaction.status_identity != null and self.compactionIdentity() != null and self.compaction.status_identity.?.eql(self.compactionIdentity().?)) self.compaction.status else .idle;
        const reserve_fits = if (selected) |model| (try self.composerReserve()) <= model.context_window -| @import("../../../ai/local_text_request.zig").outputTokens(0, model.context_window) else false;
        const can_compact = reserve_fits and self.execution().thread_state.load(.acquire) == 0 and self.compaction.job == null and history_usage.can_compact;
        std.hash.autoHash(&hash, compact_status);
        std.hash.autoHash(&hash, can_compact);
        const reserved_image_tokens = history_usage.reserved_image_tokens;
        const draft_tokens = @import("../../../ai/local_text_request.zig").draftTokens(self.prompt.peek());
        const live_tokens = if (live_usage != null) 0 else (response_bytes + 3) / 4 + if (self.requestDisplayed() and self.execution().thread_state.load(.acquire) != 0 and !self.execution().answer_only) @import("../../../ai/local_text_request.zig").draftTokens(self.execution().request_text orelse "") else @as(usize, 0);
        const catalog_tokens = fixed_usage.tool_tokens;
        const Part = @import("../composer/view/ai_composer_controls_view.zig").UsagePart;
        const fallback_parts = [_]Part{
            .{ .name = "终端上下文", .tokens = context_tokens },
            .{ .name = "对话", .tokens = (history_usage.added_tokens -| reserved_image_tokens) +| live_tokens },
            .{ .name = "草稿", .tokens = draft_tokens },
            .{ .name = "工具定义", .tokens = catalog_tokens },
            .{ .name = "图片保守预留", .tokens = reserved_image_tokens },
        };
        const measured_parts = [_]Part{
            .{ .name = "基准输入（实测）", .tokens = history_usage.measured_tokens orelse 0, .estimated = false },
            .{ .name = "新增内容（估算）", .tokens = (history_usage.added_tokens -| reserved_image_tokens) +| live_tokens, .estimated = true },
            .{ .name = "草稿", .tokens = draft_tokens, .estimated = true },
            .{ .name = "图片保守预留", .tokens = reserved_image_tokens, .estimated = true },
        };
        const parts: []const Part = if (history_usage.measured_tokens != null) measured_parts[0..if (reserved_image_tokens > 0) 4 else 3] else fallback_parts[0..if (reserved_image_tokens > 0) 5 else 4];
        const used = history_usage.tokens +| draft_tokens +| live_tokens;
        const estimated = history_usage.estimated or draft_tokens > 0 or live_tokens > 0;
        std.hash.autoHash(&hash, .{ history_usage.measured_tokens, estimated, draft_tokens, live_tokens });
        std.hash.autoHash(&hash, used);
        std.hash.autoHash(&hash, reserved_image_tokens);
        std.hash.autoHash(&hash, context_tokens);
        const fingerprint = hash.final();
        if (self.composer_hash == fingerprint) return;
        const usage: ?@import("../composer/view/ai_composer_controls_view.zig").Usage = if (selected) |model_config| .{ .used_tokens = used, .limit_tokens = model_config.context_window, .estimated = estimated, .parts = parts, .compaction = compact_status, .can_compact = can_compact, .compaction_before = self.compaction.before_tokens, .compaction_after = self.compaction.after_tokens } else null;
        const key: ?@import("../composer/view/ai_composer_controls_view.zig").ModelKey = if (controls.model) |value| .{ .provider_id = value.provider_id, .model_id = value.model_id } else if (selected) |value| .{ .provider_id = config.ai.default_provider, .model_id = value.model } else null;
        try view.update(.{ .owner = owner, .revision = self.controlsRevision(), .providers = config.ai.providers[0..@min(config.ai.provider_count, config.ai.providers.len)], .current = key, .usage = usage, .permission = if (self.child_identity != null and self.parentPermission() != .auto) .confirm else controls.permission orelse config.ai.permission_mode, .allow_auto_permission = self.child_identity == null or self.parentPermission() == .auto, .inventory_authorized = false, .inventory_conversation_id = null, .global_execution_mode = config.ai.execution_mode, .global_session_retention = config.ai.session_retention, .execution_mode_override = controls.execution_mode, .session_retention_override = controls.session_retention, .effort = controls.effort, .thinking = controls.thinking, .attachments = .{ .image = true, .paste_image = true, .local_text = true, .remote_file = remote_files_available }, .editable = self.child_identity == null or self.childCanWrite() });
        if (catalog_changed) view.preserveModelPopup();
        self.composer_hash = fingerprint;
        self.promptChanged(self.prompt.peek());
    }

    fn clearRequestHistory(self: *AiHost) void {
        self.execution().request_history.deinit();
    }

    fn retainCurrentTurn(self: *AiHost) !void {
        var additions: std.ArrayList(HistoryMessage) = .empty;
        defer additions.deinit(self.allocator);
        errdefer for (additions.items) |*message| message.deinit(self.allocator);
        if (self.last_user_text) |text| {
            var message = try (HistoryMessage{ .user = true, .turn = self.current_turn, .text = text, .wire_text = self.last_user_wire, .attachments = self.last_user_attachments, .images = self.last_user_images }).clone(self.allocator);
            additions.append(self.allocator, message) catch |err| {
                message.deinit(self.allocator);
                return err;
            };
        }
        for (self.controller.stream.cards.items) |card| {
            const body = switch (card) {
                .text => |text| text,
                .code => |code| code.body,
                else => continue,
            };
            const copy = try self.allocator.dupe(u8, body);
            additions.append(self.allocator, .{ .user = false, .text = copy }) catch |err| {
                self.allocator.free(copy);
                return err;
            };
        }
        if (self.execution().request_failure != null) {
            var message = try (HistoryMessage{ .user = false, .text = @constCast(self.execution().failure_label) }).clone(self.allocator);
            additions.append(self.allocator, message) catch |err| {
                message.deinit(self.allocator);
                return err;
            };
        }
        try self.history.ensureUnusedCapacity(self.allocator, additions.items.len);
        self.history.appendSliceAssumeCapacity(additions.items);
        self.controller.stream.clearRetainingCapacity();
        self.current_turn.deinit(self.allocator);
    }

    pub fn setFeedback(self: *AiHost, label: []const u8) void {
        if (label.len == 0) {
            if (self.feedback) |view| view.show("", .warning);
            return;
        }
        if (std.mem.startsWith(u8, label, "已") or std.mem.startsWith(u8, label, "正在") or std.mem.startsWith(u8, label, "图片处理中") or std.mem.startsWith(u8, label, "子配置已保存") or std.mem.startsWith(u8, label, "未保存的排队编辑已保留")) {
            if (self.feedback) |view| view.show(label, .warning);
            return;
        }
        const notifications = process_state.process_notifications orelse return;
        const window = self.notification_window orelse return;
        const before = notifications.coordinator.history_revision;
        var buffer: [2048]u8 = undefined;
        const text = if (@import("../../../ai/error_feedback.zig").localFailureLabel(label)) |message| message else @import("../../../shared/base/feedback_message.zig").message(label, &buffer);
        notifications.publishOperationError(window, null, "AI 助手", "AI 操作未完成", text, if (std.mem.indexOf(u8, text, "AI 设置") != null) .ai_settings else null) catch |err| applog.warn(.ui, "AI failure notification: {s}", .{@errorName(err)});
        if (notifications.coordinator.history_revision != before) self.wake();
    }

    fn imageGateLabel(problem: anyerror) []const u8 {
        return switch (problem) {
            error.AttachmentsProcessing => "图片处理中，请等待或移除",
            error.ImageAttachmentFailed => "图片读取失败，请重试附件或移除",
            error.ModelDoesNotSupportImages => "当前模型未启用识图，请选择兼容模型或移除图片",
            error.UnsupportedImageProtocol => "当前 Provider 尚未支持图片请求，请选择兼容模型或移除图片",
            error.UnknownImageBudget => "当前模型的图片预算未知，请选择兼容模型或移除图片",
            else => "请先配置可用模型",
        };
    }

    pub fn refresh(self: *AiHost, label: []const u8) void {
        _ = self.controller.snapshot(content_snapshot_origin, content_snapshot_region);
        var buffer: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        var owner_label: []const u8 = "当前会话";
        if (self.display_owner) |owner| if (self.resolveOwner(owner)) |bound| switch (bound.content) {
            .session => if (bound.card) |tab| {
                owner_label = tab.titleSlice();
            },
            .group => |group_id| if (self.roster) |roster| {
                for (roster.groups.items) |group| if (group.id == group_id) {
                    owner_label = group.name;
                    break;
                };
            },
        };
        self.setFeedback(if (self.recoveryVisible() or std.mem.eql(u8, label, "AI 助手") or
            std.mem.eql(u8, label, "AI Float") or
            std.mem.eql(u8, label, "AI 请求中…") or
            std.mem.eql(u8, label, "AI Float · 请求中") or
            std.mem.eql(u8, label, "AI · 当前助手") or
            std.mem.eql(u8, label, "AI response")) "" else label);
        var child_status: ?@import("../../../ai/child_projection.zig").Entry = null;
        if (self.child_identity != null) if (self.childRecord()) |record| {
            child_status = @import("../../../ai/child_projection.zig").entry(&self.shared_service.?.service, record);
            owner_label = child_status.?.status;
        };
        writer.print("{s}", .{owner_label}) catch return;
        if (self.chrome) |chrome| chrome.setSubtitle(writer.buffered()) else if (self.status_label) |status_tag| {
            if (child_status) |entry| if (self.child_parent.?.child_dialog) |dialog| dialog.showStatus(entry) else status_tag.set(owner_label) else status_tag.set(owner_label);
        } else if (self.status) |node| {
            node.setTextContent(self.allocator, writer.buffered()) catch return;
            node.markRenderDirty();
        }
        // Attachment history owns widget scopes and portal cleanup. Rebuild
        // only at the after-layout safe point, never inside a click callback.
        self.conversation_dirty = true;
        self.requestPresentation();
        self.promptChanged(self.prompt.get());
        self.wake();
    }

    /// 对话流重建：用户气泡（右缘 acc.07 底 10/10/3/10）+ 每张卡片一个
    /// 响应块（12.5px，code 卡 mono）。卡片数据仍来自 controller.cardView。
    /// “新消息”: glide back to the newest output and follow it again (reduce motion: jump).
    fn jumpToNewMessages(self: *AiHost) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        const follow = if (self.tail_follow) |*value| value else return;
        follow.jumpToEnd(self.cx.frame_time_ms, ui.fx.anchor_transition.reducedMotion(self.cx));
        if (self.new_messages) |hint| hint.setShown(false);
        self.wake();
    }

    fn pauseConversationFollow(self: *AiHost) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        if (self.tail_follow) |*follow| follow.following = false;
    }

    fn markdown(self: *AiHost, value: []const u8) !*ui.Node {
        if (self.conversation_scope == null) self.conversation_scope = try (self.contentScope() orelse return error.MissingAssistantScope).childScope();
        const scope = self.conversation_scope.?;
        return self.markdownIn(scope, value, self.image_render_turn);
    }

    fn markdownIn(self: *AiHost, scope: *ui.Scope, value: []const u8, turn: ?*const @import("../../../ai/conversation_turn.zig").Turn) !*ui.Node {
        const width = if (self.card_box) |box| @max(160, messageWidth(box)) else 540;
        return @import("../pane/view/ai_message_view.zig").mountWithImages(self.cx, scope, value, width, try self.markdownImages(turn));
    }
    fn markdownImages(self: *AiHost, turn: ?*const @import("../../../ai/conversation_turn.zig").Turn) !?@import("../attachments/view/ai_transcript_images.zig").Context {
        const module = @import("../attachments/view/ai_transcript_images.zig");
        if (turn == null or turn.?.file_source == null) return null;
        if (self.transcript_images == null) {
            const store = try self.allocator.create(module.Store);
            store.* = .{ .allocator = self.allocator };
            self.transcript_images = store;
        }
        return .{ .store = self.transcript_images.?, .source = turn.?.file_source, .conversation = self.display_conversation orelse 0, .turn = turn.?.id, .app = if (self.images_view) |view| view.app else null, .preview_context = self, .preview = previewSentImage };
    }

    fn userMessage(self: *AiHost, index: usize) ?HistoryMessage {
        if (index < self.history.items.len) return if (self.history.items[index].user) self.history.items[index] else null;
        if (index != self.history.items.len) return null;
        return .{ .user = true, .text = self.last_user_text orelse return null, .attachments = self.last_user_attachments, .images = self.last_user_images };
    }
    fn turnAt(self: *AiHost, index: usize) ?*@import("../../../ai/conversation_turn.zig").Turn {
        if (index < self.history.items.len) return if (self.history.items[index].turn) |*turn| turn else null;
        return if (index == self.history.items.len and self.last_user_text != null) &self.current_turn else null;
    }
    const MessageCell = struct {
        host: *AiHost,
        index: usize,
        kind: @FieldType(MessageAction, "kind"),
        copy_button: *@import("../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
        fn run(self: *MessageCell) void {
            self.host.message_action = .{ .kind = self.kind, .index = self.index, .conversation = self.host.display_conversation };
            self.host.wake();
        }
        fn copy(self: *MessageCell) void {
            const value = if (self.kind == .fork) (self.host.turnAt(self.index) orelse return).answer else (self.host.userMessage(self.index) orelse return).text;
            self.copy_button.copy(value);
        }
    };
    fn messageButton(self: *AiHost, parent: *ui.Node, index: usize, kind: @FieldType(MessageAction, "kind"), asset: ui.SvgAsset, label: []const u8, id: []const u8, copy: bool) !void {
        const cell = try self.conversation_scope.?.createState(MessageCell, .{ .host = self, .index = index, .kind = kind });
        const props = .{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = asset, .icon_size = @as(f32, 12), .a11y_label = label, .disabled = !copy and self.execution().thread_state.load(.acquire) != 0, .on_click = if (copy) self.cx.on(MessageCell, cell, MessageCell.copy) else self.cx.on(MessageCell, cell, MessageCell.run) };
        const button = if (copy) blk: {
            cell.copy_button = try @import("../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(self.cx, self.conversation_scope.?, props);
            break :blk cell.copy_button.node;
        } else try ui.widgets.Button(props).mount(self.conversation_scope.?, self.cx);
        button.meta.ownership.meta.test_id = id;
        try parent.appendChild(self.allocator, button);
    }
    fn appendUserMessage(self: *AiHost, parent: *ui.Node, message: HistoryMessage, index: usize) !void {
        const cx = self.cx;
        const styles = @import("../pane/view/ai_assistant_styles.zig");
        const user_view = @import("../pane/view/ai_user_message_view.zig");
        const content_width = try self.messageWidthModel();
        const width = content_width.peek();
        const row = try ui.box(cx, styles.messageRow(true), .{});
        row.meta.ownership.meta.test_id = self.id_space.id("ai.message.user.row");
        if ((if (message.attachments) |bundle| bundle.items.len else 0) + (if (message.images) |bundle| bundle.items.len else 0) > 0) {
            const sent = try user_view.mountAttachments(cx, self.conversation_scope.?, content_width);
            if (message.attachments) |*bundle| try self.appendSentAttachments(sent, bundle);
            if (message.images) |*bundle| try self.appendSentImages(sent, bundle);
            try row.appendChild(self.allocator, sent);
        }
        // Pencil Kaf7E A3: the native W.Card bubble (bg_active), at most 85% wide.
        const bubble = try user_view.mountBubble(cx, self.conversation_scope.?, content_width);
        if (self.editing_index == index) {
            if (self.edit_text == null) self.edit_text = try self.scope.?.createText("", .{});
            if (self.edit_seed != index) {
                self.edit_text.?.set(message.text);
                self.edit_seed = index;
            }
            const editor = try ui.widgets.Textarea(.{ .value = self.edit_text.?, .rows = 3, .embedded = true }).mountResult(self.conversation_scope.?, cx);
            editor.wrapper.setStyleInline(self.allocator, .{ .width = .{ .px = @max(150, width * 0.65) }, .height = .{ .px = 76 }, .flex_shrink = 0 });
            editor.input.meta.ownership.meta.test_id = self.id_space.id("ai.message.edit.input");
            self.edit_input = editor;
            // The editor goes with its row's Scope (a virtual row scrolled out, a rebuild): forget it then.
            const Forget = struct {
                host: *AiHost,
                input: *ui.Node,
                fn run(forget: *@This()) void {
                    if (forget.host.edit_input) |current| if (current.input == forget.input) {
                        forget.host.edit_input = null;
                    };
                }
            };
            const forget = try self.conversation_scope.?.createState(Forget, .{ .host = self, .input = editor.input });
            try self.conversation_scope.?.onCleanup(Forget, forget, Forget.run);
            try bubble.body.appendChild(self.allocator, editor.wrapper);
        } else {
            const text = try ui.textStyled(cx, styles.userText, message.text);
            text.meta.ownership.meta.test_id = self.id_space.id("ai.message.user.text");
            try bubble.body.appendChild(self.allocator, text);
            try @import("../pane/view/ai_text_selection.zig").attach(cx, self.conversation_scope.?, bubble.root);
        }
        try row.appendChild(self.allocator, bubble.root);
        const turn = self.turnAt(index) orelse {
            try parent.appendChild(self.allocator, row);
            return;
        };
        // Hover actions (Kaf7E ⑦): time, copy, rewind, edit — shown while hovered / focused / editing.
        const actions = try ui.boxStyled(cx, styles.userActions, .{});
        var buffer: [64]u8 = undefined;
        const full_time = @import("../../history/view/history_styles.zig").dateLabel(&buffer, @intCast(turn.sent_at_ms));
        const time = if (full_time.len >= 16) full_time[11..16] else full_time;
        const timestamp = try ui.textStyled(cx, styles.userTime, time);
        timestamp.meta.ownership.meta.test_id = self.id_space.id("ai.message.timestamp");
        try actions.appendChild(self.allocator, timestamp);
        try actions.appendChild(self.allocator, try ui.box(cx, .{ .width = .{ .px = 4 }, .height = .{ .px = 1 }, .flex_shrink = 0 }, .{}));
        try self.messageButton(actions, index, .rewind, ui.icons.copy, "复制用户消息", self.id_space.id("ai.message.copy"), true);
        try self.messageButton(actions, index, .rewind, ui.icons.get("undo-2").?, "回退并立即清除本回合及后续记录和上下文", self.id_space.id("ai.message.rewind"), false);
        try self.messageButton(actions, index, if (self.editing_index == index) .save else .edit, if (self.editing_index == index) ui.icons.check else ui.icons.get("pencil").?, if (self.editing_index == index) "保存编辑" else "编辑用户消息", if (self.editing_index == index) self.id_space.id("ai.message.edit.save") else self.id_space.id("ai.message.edit"), false);
        if (self.editing_index == index) try self.messageButton(actions, index, .cancel, ui.icons.x, "取消编辑", self.id_space.id("ai.message.edit.cancel"), false);
        try row.appendChild(self.allocator, actions);
        try user_view.Reveal.attach(cx, self.conversation_scope.?, row, actions, self.editing_index == index);
        try parent.appendChild(self.allocator, row);
    }
    fn appendProse(self: *AiHost, parent: *ui.Node, text: []const u8) !void {
        if (std.mem.trim(u8, text, " \t\r\n").len == 0) return;
        const row = try ui.box(self.cx, @import("../pane/view/ai_assistant_styles.zig").assistantMessage(), .{});
        row.meta.ownership.meta.test_id = self.id_space.id("ai.message.assistant");
        const body = try self.markdown(text);
        body.meta.ownership.meta.test_id = self.id_space.id("ai.response");
        try row.appendChild(self.allocator, body);
        try parent.appendChild(self.allocator, row);
    }
    fn appendRetainedStep(self: *AiHost, parent: *ui.Node, props: @import("../cards/view/ai_step_view.zig").Props, retained: ?*?@import("../cards/view/ai_step_view.zig").Result) !void {
        if (retained) |slot| if (slot.*) |view| {
            try view.update(props);
            return;
        };
        const view = try @import("../cards/view/ai_step_view.zig").mountRetained(self.cx, self.conversation_scope.?, props);
        try parent.appendChild(self.allocator, view.root);
        if (retained) |slot| slot.* = view;
    }
    fn appendToolStep(self: *AiHost, parent: *ui.Node, turn: *@import("../../../ai/conversation_turn.zig").Turn, step: *@import("../../../ai/step_events.zig").Step, now: u64) !bool {
        return self.appendRetainedToolStep(parent, turn, step, now, null);
    }
    fn appendRetainedToolStep(self: *AiHost, parent: *ui.Node, turn: *@import("../../../ai/conversation_turn.zig").Turn, step: *@import("../../../ai/step_events.zig").Step, now: u64, retained: ?*?@import("../cards/view/ai_step_view.zig").Result) !bool {
        const view = @import("../cards/view/ai_step_view.zig");
        // Pending requests are represented by the composer interaction slot.
        // A tool step exists only once execution is approved or dispatched.
        if (step.phase == .assembling or step.phase == .approval) return true;
        if (step.activity_started_ms == null and (step.phase == .failed or step.phase == .rejected or step.phase == .cancelled or step.phase == .skipped)) {
            const failure = @import("../../../ai/step_failure.zig");
            const description = try failure.describe(self.allocator, step.*);
            defer description.deinit(self.allocator);
            try self.appendRetainedStep(parent, .{ .title = view.title(step.name), .tool_name = step.name, .tool_arguments = step.command, .projection = description.summary, .projection_is_status = true, .detail = description.detail, .phase = step.phase, .elapsed_ms = 0, .show_elapsed = false, .expanded = &step.expanded, .test_id = self.id_space.id("ai.request.unsent"), .on_toggle = self.cx.on(AiHost, self, pauseConversationFollow) }, retained);
            return true;
        }
        var found = false;
        for (self.tool_results.records.items) |record| if (record.turn_id == turn.id and std.mem.eql(u8, record.call_id, step.call_id)) {
            if (record.total_elapsed_ms == null) record.expanded = step.expanded;
            record.decision = step.decision;
            record.total_elapsed_ms = step.elapsedAt(now);
            if (record.execution != null) {
                const node = try @import("../cards/view/ai_execution_result_view.zig").mount(self.cx, self.conversation_scope.?, &self.tool_results, record, .{ .context = self, .perform = performExecutionAction }, self.cx.on(AiHost, self, pauseConversationFollow));
                try @import("../cards/view/ai_verification_view.zig").mount(self.cx, self.conversation_scope.?, node, record, .{ .context = self, .enqueue = enqueueVerification });
                try parent.appendChild(self.allocator, node);
                found = true;
                break;
            }
            const result = try @import("../cards/view/ai_tool_results_view.zig").State.mount(self.cx, self.conversation_scope.?, record);
            try @import("../cards/view/ai_verification_view.zig").mount(self.cx, self.conversation_scope.?, result.root, record, .{ .context = self, .enqueue = enqueueVerification });
            result.on_toggle = self.cx.on(AiHost, self, pauseConversationFollow);
            for (record.images) |ref| try result.appendImage(ref, if (self.images_view) |images| images.app else null);
            try parent.appendChild(self.allocator, result.root);
            found = true;
            break;
        };
        if (!found) {
            try self.appendRetainedStep(parent, .{ .title = view.title(step.name), .tool_name = step.name, .projection = step.command, .decision = step.decision, .detail = step.detail, .phase = step.phase, .elapsed_ms = step.elapsedAt(now), .expanded = &step.expanded, .test_id = self.id_space.id("ai.step.tool"), .on_toggle = self.cx.on(AiHost, self, pauseConversationFollow) }, retained);
        }
        return true;
    }
    fn appendThinkingSegment(self: *AiHost, parent: *ui.Node, segment: *@import("../../../ai/conversation_turn.zig").Segment, now: u64) !void {
        // A failed provider attempt may release its timeline before this view
        // is rebuilt. Keep the segment alive through child widget cleanup.
        segment.retain();
        self.conversation_scope.?.onCleanup(@import("../../../ai/conversation_turn.zig").Segment, segment, @import("../../../ai/conversation_turn.zig").Segment.release) catch |err| {
            segment.release();
            return err;
        };
        if (segment.scroll == null) segment.scroll = try @import("../../../ai/conversation_turn.zig").ThinkingScroll.create(self.allocator);
        const text = std.mem.trim(u8, segment.text.items, " \t\r\n");
        const last_line = @import("../../../ai/step_groups.zig").thinkingProjection(text);
        try parent.appendChild(self.allocator, try @import("../cards/view/ai_step_view.zig").mount(self.cx, self.conversation_scope.?, .{ .title = "思考", .projection = last_line, .detail = text, .copy_detail = false, .phase = if (segment.ended_ms != null) .succeeded else .running, .elapsed_ms = (segment.ended_ms orelse now) -| segment.started_ms, .expanded = &segment.expanded, .scroll_position = segment.scroll, .test_id = self.id_space.id("ai.thinking"), .on_toggle = self.cx.on(AiHost, self, pauseConversationFollow) }));
    }
    fn invalidateTimeline(self: *AiHost) void {
        if (self.live_timeline) |view| view.invalidate() else self.conversation_dirty = true;
    }

    const DetailsContext = struct {
        host: *AiHost,
        turn: *@import("../../../ai/conversation_turn.zig").Turn,
        first: usize,
        end: usize,
        fn sync(raw: *anyopaque, retained: *@import("../pane/view/ai_timeline_view.zig").View) !void {
            const context: *DetailsContext = @ptrCast(@alignCast(raw));
            const self = context.host;
            const turn = context.turn;
            const previous_scope = self.conversation_scope;
            defer self.conversation_scope = previous_scope;
            const now: u64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
            var slot: usize = 0;
            for (turn.timeline.items[context.first..context.end], context.first..) |entry, index| {
                if (entry != .thinking and entry != .tool) continue;
                if (entry == .tool and !@import("../../../ai/step_groups.zig").toolVisible(turn.steps.items[entry.tool])) continue;
                const row = try retained.row(slot, index, .step);
                slot += 1;
                var source = std.hash.Wyhash.init(0);
                var hash = std.hash.Wyhash.init(0);
                if (entry == .thinking) {
                    const segment = entry.thinking;
                    std.hash.autoHash(&source, @intFromPtr(segment));
                    hash.update(segment.text.items);
                    std.hash.autoHash(&hash, segment.ended_ms);
                } else {
                    const step = turn.steps.items[entry.tool];
                    source.update(step.call_id);
                    hash.update(step.name);
                    hash.update(step.command);
                    hash.update(step.detail);
                    std.hash.autoHash(&hash, .{ step.phase, step.ended_ms, step.decision, step.activity_started_ms });
                    for (self.tool_results.records.items) |record| if (record.turn_id == turn.id and std.mem.eql(u8, record.call_id, step.call_id)) {
                        std.hash.autoHash(&source, @intFromPtr(record));
                        std.hash.autoHash(&hash, record.error_status);
                    };
                }
                const source_key = source.final();
                if (row.source_key != source_key) retained.clearBody(row);
                const fingerprint = hash.final();
                if (row.body_fingerprint != fingerprint or row.source_key != source_key) {
                    const body = try retained.body(row, row.root);
                    if (row.step == null) {
                        retained.clearBody(row);
                        row.body_scope = try row.scope.childScope();
                    }
                    self.conversation_scope = row.body_scope;
                    if (entry == .thinking) {
                        const segment = entry.thinking;
                        if (row.step == null) {
                            segment.retain();
                            row.body_scope.?.onCleanup(@import("../../../ai/conversation_turn.zig").Segment, segment, @import("../../../ai/conversation_turn.zig").Segment.release) catch |err| {
                                segment.release();
                                return err;
                            };
                        }
                        if (segment.scroll == null) segment.scroll = try @import("../../../ai/conversation_turn.zig").ThinkingScroll.create(self.allocator);
                        const text = std.mem.trim(u8, segment.text.items, " \t\r\n");
                        try self.appendRetainedStep(body, .{ .title = "思考", .projection = @import("../../../ai/step_groups.zig").thinkingProjection(text), .detail = text, .copy_detail = false, .phase = if (segment.ended_ms != null) .succeeded else .running, .elapsed_ms = (segment.ended_ms orelse now) -| segment.started_ms, .expanded = &segment.expanded, .scroll_position = segment.scroll, .test_id = self.id_space.id("ai.thinking"), .on_toggle = self.cx.on(AiHost, self, pauseConversationFollow) }, &row.step);
                    } else _ = try self.appendRetainedToolStep(body, turn, &turn.steps.items[entry.tool], now, &row.step);
                    row.source_key = source_key;
                    row.body_fingerprint = fingerprint;
                }
                // A growing step array may move. Retained widgets rebind their
                // disclosure flag before any subsequent UI event or hook.
                if (entry == .tool) if (row.step) |view| view.rebindExpanded(&turn.steps.items[entry.tool].expanded);
            }
            retained.truncate(slot);
        }
    };

    const TimelineContext = struct {
        host: *AiHost,
        turn: *@import("../../../ai/conversation_turn.zig").Turn,
        fn sync(raw: *anyopaque, retained: *@import("../pane/view/ai_timeline_view.zig").View) !void {
            const context: *TimelineContext = @ptrCast(@alignCast(raw));
            const self = context.host;
            const turn = context.turn;
            const groups = @import("../../../ai/step_groups.zig");
            const previous_scope = self.conversation_scope;
            const previous_turn = self.image_render_turn;
            defer self.conversation_scope = previous_scope;
            defer self.image_render_turn = previous_turn;
            self.image_render_turn = turn;
            try groups.sync(self.allocator, turn, self.effectiveAi().step_display == .expanded);
            const now: u64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
            var first: usize = 0;
            var slot: usize = 0;
            while (first < turn.timeline.items.len) : (slot += 1) {
                const item = turn.timeline.items[first];
                const kind: @FieldType(@import("../pane/view/ai_timeline_view.zig").Row, "kind") = if (item == .message and groups.boundary(item)) .message else if (item == .input) .input else if (item == .notice) .notice else .group;
                const end = if (kind == .group) groups.rangeEnd(turn, first) else first + 1;
                const row = try retained.row(slot, first, kind);
                var hash = std.hash.Wyhash.init(0);
                for (turn.timeline.items[first..end]) |entry| switch (entry) {
                    .message, .thinking, .input => |segment| {
                        hash.update(segment.text.items);
                        std.hash.autoHash(&hash, .{ segment.started_ms, segment.ended_ms });
                    },
                    .notice => |index| hash.update(turn.host_notices.items[index].text),
                    .tool => |index| {
                        const step = turn.steps.items[index];
                        hash.update(step.call_id);
                        hash.update(step.name);
                        hash.update(step.command);
                        hash.update(step.detail);
                        std.hash.autoHash(&hash, .{ step.phase, step.ended_ms, step.decision, step.activity_started_ms });
                        for (self.tool_results.records.items) |record| if (record.turn_id == turn.id and std.mem.eql(u8, record.call_id, step.call_id)) {
                            std.hash.autoHash(&hash, .{ @intFromPtr(record), record.total_elapsed_ms, record.error_status });
                        };
                    },
                };
                const fingerprint = hash.final();
                if (kind != .group) {
                    if (row.fingerprint != fingerprint) {
                        const body = try retained.body(row, row.root);
                        if (kind == .message) {
                            if (row.prose == null) {
                                row.body_scope = try row.scope.childScope();
                                row.prose = try @import("../pane/view/ai_message_view.zig").Retained.mount(self.cx, row.body_scope.?);
                                row.prose.?.root.meta.ownership.meta.test_id = self.id_space.id("ai.response");
                                const wrapper = try ui.box(self.cx, @import("../pane/view/ai_assistant_styles.zig").assistantMessage(), .{});
                                wrapper.meta.ownership.meta.test_id = self.id_space.id("ai.message.assistant");
                                try wrapper.appendChild(self.allocator, row.prose.?.root);
                                try body.appendChild(self.allocator, wrapper);
                            }
                            const width = if (self.card_box) |box| @max(160, messageWidth(box)) else 540;
                            try row.prose.?.update(item.message.text.items, width, try self.markdownImages(self.image_render_turn));
                        } else {
                            retained.clearBody(row);
                            row.body_scope = try row.scope.childScope();
                            self.conversation_scope = row.body_scope;
                            switch (kind) {
                                .message => unreachable,
                                .input => try self.appendSteerBubble(body, item.input.text.items, null, null),
                                .notice => {
                                    _ = try @import("../cards/view/ai_host_notice_view.zig").mount(self.cx, self.id_space, body, turn.host_notices.items[item.notice].text);
                                },
                                .group, .step => unreachable,
                            }
                        }
                        row.fingerprint = fingerprint;
                    }
                } else {
                    const summary = groups.summarize(turn, first, end, now);
                    if (summary.latest) |latest| {
                        const title = if (latest == .thinking) try self.allocator.dupe(u8, if (latest.thinking.ended_ms == null) "思考中" else "思考") else try @import("../cards/model/ai_tool_titles.zig").action(self.allocator, turn.steps.items[latest.tool].name, turn.steps.items[latest.tool].command);
                        defer self.allocator.free(title);
                        const projection = if (summary.thinking_projection) |text| try self.allocator.dupe(u8, text) else if (summary.count == 1 and latest == .tool) try @import("../cards/model/ai_tool_header_projection.zig").project(self.allocator, turn.steps.items[latest.tool].name, turn.steps.items[latest.tool].command) else try self.allocator.dupe(u8, "");
                        defer self.allocator.free(projection);
                        const state = groups.find(turn, first).?;
                        const props: @import("../cards/view/ai_step_group_view.zig").Props = .{ .group = state, .title = title, .projection = projection, .tool_name = if (latest == .tool) turn.steps.items[latest.tool].name else null, .step_count = if (summary.count == 1 and latest == .tool and summary.thinking_projection == null) null else summary.count, .phase = summary.phase, .elapsed_ms = summary.elapsed_ms, .live = summary.live, .failed_steps = summary.failed, .rejected_steps = summary.rejected, .on_toggle = self.cx.on(@import("../pane/view/ai_timeline_view.zig").View, retained, @import("../pane/view/ai_timeline_view.zig").View.toggled) };
                        if (row.group == null) {
                            row.group = try @import("../cards/view/ai_step_group_view.zig").mount(self.cx, row.scope, props);
                            try row.root.appendChild(self.allocator, row.group.?.root);
                        } else if (row.fingerprint != fingerprint) try row.group.?.update(props);
                        row.root.setDisplay(.flex);
                        row.fingerprint = fingerprint;
                        if (state.expanded) {
                            if (row.details == null) {
                                const body = try retained.body(row, row.group.?.content);
                                row.body_scope = try row.scope.childScope();
                                const details = try row.body_scope.?.createState(DetailsContext, .{ .host = self, .turn = turn, .first = first, .end = end });
                                row.details = try @import("../pane/view/ai_timeline_view.zig").View.mount(self.cx, row.body_scope.?, body, details, DetailsContext.sync, self.cx.on(AiHost, self, pauseConversationFollow));
                                row.details.?.root.setStyleInline(self.allocator, .{ .gap = 6 });
                            }
                            const details: *DetailsContext = @ptrCast(@alignCast(row.details.?.context));
                            details.end = end;
                            try DetailsContext.sync(details, row.details.?);
                            row.details.?.dirty = false;
                        }
                    } else row.root.setDisplay(.none);
                }
                first = end;
            }
            retained.truncate(slot);
        }
    };

    fn appendTurnSteps(self: *AiHost, parent: *ui.Node, turn: *@import("../../../ai/conversation_turn.zig").Turn) !void {
        const previous_image_turn = self.image_render_turn;
        self.image_render_turn = turn;
        defer self.image_render_turn = previous_image_turn;
        const view = @import("../cards/view/ai_step_view.zig");
        const now: u64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        if (turn.timeline.items.len > 0) {
            const timeline = @import("../pane/view/ai_timeline_view.zig");
            const context = try self.conversation_scope.?.createState(TimelineContext, .{ .host = self, .turn = turn });
            const retained = try timeline.View.mount(self.cx, self.conversation_scope.?, parent, context, TimelineContext.sync, self.cx.on(AiHost, self, pauseConversationFollow));
            if (turn == &self.current_turn) self.live_timeline = retained;
            try TimelineContext.sync(context, retained);
            retained.dirty = false;
            return;
        }
        if (turn.thinking.items.len > 0) {
            if (turn.thinking_scroll == null) turn.thinking_scroll = try @import("../../../ai/conversation_turn.zig").ThinkingScroll.create(self.allocator);
            const text = std.mem.trim(u8, turn.thinking.items, " \t\r\n");
            const last_line = @import("../../../ai/step_groups.zig").thinkingProjection(text);
            try parent.appendChild(self.allocator, try view.mount(self.cx, self.conversation_scope.?, .{ .title = "思考", .projection = last_line, .detail = text, .copy_detail = false, .phase = if (turn.thinking_ended_ms != null or turn.ended_at_ms != null) .succeeded else .running, .elapsed_ms = (turn.thinking_ended_ms orelse now) -| (turn.thinking_started_ms orelse now), .expanded = &turn.thinking_expanded, .scroll_position = turn.thinking_scroll, .test_id = self.id_space.id("ai.thinking"), .on_toggle = self.cx.on(AiHost, self, pauseConversationFollow) }));
        }
        var prose_offset: usize = 0;
        for (turn.steps.items) |*step| {
            const boundary = @min(turn.prose.items.len, @max(prose_offset, step.text_offset));
            try self.appendProse(parent, turn.prose.items[prose_offset..boundary]);
            prose_offset = boundary;
            if (!try self.appendToolStep(parent, turn, step, now)) return;
        }
        try self.appendProse(parent, turn.prose.items[prose_offset..]);
        for (turn.host_notices.items) |notice| _ = try @import("../cards/view/ai_host_notice_view.zig").mount(self.cx, self.id_space, parent, notice.text);
    }
    fn appendSteerBubble(self: *AiHost, parent: *ui.Node, content: []const u8, status: ?[]const u8, waiting_hint: ?[]const u8) !void {
        const styles = @import("../pane/view/ai_assistant_styles.zig");
        const row = try ui.box(self.cx, .{ .width = .fill(), .direction = .row, .justify = .end, .flex_shrink = 0 }, .{});
        // A steer message is a user turn too: the same native W.Card bubble.
        const card = try @import("../pane/view/ai_user_message_view.zig").mountBubble(self.cx, self.conversation_scope.?, try self.messageWidthModel());
        const bubble = card.body;
        card.root.meta.ownership.meta.test_id = if (status == null) self.id_space.id("ai.followup.consumed") else self.id_space.id("ai.followup.pending");
        const text = try ui.textStyled(self.cx, styles.userText, "");
        try text.setTextContent(self.allocator, content);
        try bubble.appendChild(self.allocator, text);
        if (status) |label| {
            const node = try ui.textStyled(self.cx, styles.userTime, label);
            node.meta.ownership.meta.test_id = self.id_space.id("ai.followup.status");
            if (waiting_hint) |hint| {
                const tip = try @import("../../../shared/ui/components/control_hint/control_hint.zig").mount(self.cx, self.conversation_scope.?, node, hint, .{ .id = self.id_space.id("ai.followup.waiting_hint") });
                try bubble.appendChild(self.allocator, tip.wrapper);
            } else try bubble.appendChild(self.allocator, node);
        }
        try row.appendChild(self.allocator, card.root);
        try parent.appendChild(self.allocator, row);
    }
    fn appendSteerMessages(self: *AiHost, parent: *ui.Node, turn: u64) !void {
        const shared_host = self.shared_service orelse return;
        const state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
        const record = shared_host.service.store.find(state.conversation_id) orelse return;
        record.inbox.lock();
        defer record.inbox.unlock();
        for (record.inbox.entries.items) |entry| {
            const receipt = entry.receipt;
            if (receipt.route != .steer or receipt.turn != turn or receipt.delivery == .cancelled) continue;
            const displayed: ?*const @import("../../../ai/conversation_turn.zig").Turn = if (self.current_turn.id == turn) &self.current_turn else found: {
                for (self.history.items) |*message| if (message.turn) |*stored| if (stored.id == turn) break :found stored;
                break :found null;
            };
            if (displayed != null and displayed.?.hasInput(receipt.id)) continue;
            const waiting_hint: ?[]const u8 = if (receipt.delivery == .consumed) null else if (receipt.delivery == .outcome_unknown) "提交状态待核对，确认前不会重复发送" else if (receipt.pause != null) "消息尚未纳入处理，可重新填写后发送" else record.inbox.work_phase.waitingHint();
            try self.appendSteerBubble(parent, entry.payload.messages[0].content, if (receipt.delivery == .consumed) null else if (receipt.delivery == .outcome_unknown) "待核对" else if (receipt.pause != null) "已暂停" else "待处理", waiting_hint);
            if (receipt.pause != null and receipt.delivery == .accepted) {
                const Restore = struct {
                    host: *AiHost,
                    ticket: @import("../approvals/view/ai_pending_view.zig").Ticket,
                    fn run(value: *@This()) void {
                        queueAction(value.host, value.ticket, .copy_text, "") catch |err| value.host.refresh(@errorName(err));
                    }
                };
                const action = try self.conversation_scope.?.createState(Restore, .{ .host = self, .ticket = .{ .receipt = receipt, .queue_revision = record.inbox.queue_revision } });
                const button = try ui.widgets.Button(.{ .label = "重新填写", .variant = .ghost, .base_style = @import("../approvals/view/ai_pending_styles.zig").action(), .on_click = self.cx.on(Restore, action, Restore.run) }).mount(self.conversation_scope.?, self.cx);
                button.meta.ownership.meta.test_id = self.id_space.id("ai.followup.restore");
                const row = try ui.box(self.cx, .{ .width = .fill(), .direction = .row, .justify = .end, .flex_shrink = 0 }, .{});
                try row.appendChild(self.allocator, button);
                try parent.appendChild(self.allocator, row);
            }
        }
    }
    fn appendTurnFooter(self: *AiHost, parent: *ui.Node, index: usize) !void {
        const turn = self.turnAt(index) orelse return;
        if (index < self.history.items.len) try self.appendSteerMessages(parent, turn.id);
        const status = @import("../pane/view/ai_turn_status_view.zig");
        const row = try status.mount(self.cx, self.conversation_scope.?, turn, self.welcome_logo_texture);
        if (turn.ended_at_ms != null) {
            try self.messageButton(row, index, .fork, ui.icons.copy, "复制模型正式输出", self.id_space.id("ai.turn.copy"), true);
            try self.messageButton(row, index, .fork, ui.icons.get("git-branch").?, "分叉为新会话，内容截止此回合", self.id_space.id("ai.turn.fork"), false);
        }
        try parent.appendChild(self.allocator, row);
    }

    fn commitCompactedHistory(raw: *anyopaque, messages: []const ai_provider.Message) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.commitHistorySnapshot(messages);
    }
    fn commitHistorySnapshot(self: *AiHost, messages: []const ai_provider.Message) !void {
        const shared_host = self.shared_service orelse return;
        const state = self.assistant_states.?.find(self.display_conversation orelse return) orelse return;
        const record = shared_host.service.store.find(state.conversation_id) orelse return;
        if (record.ending != null) return error.LifecycleBusy;
        const ticket = try shared_host.service.store.fence(record.id);
        const runner = shared_host.service.runnerFor(ticket.agent) orelse return error.AgentNotFound;
        if (runner.agent.busy or runner.pending_commit or runner.pending_notify) return error.AgentBusy;
        if (self.display_content_revision != 0 and self.display_content_revision != record.content_revision) return error.CheckpointChanged;
        try shared_host.service.store.checkpoint(ticket, record.last_turn, messages, true);
        self.display_content_revision = record.content_revision;
    }
    fn truncateTurns(self: *AiHost, index: usize) !void {
        const turn = self.turnAt(index) orelse return error.StaleTurn;
        var before = try @import("../../../ai/wire_history.zig").History.copy(self.allocator, turn.before.messages, "");
        errdefer before.deinit();
        try self.commitHistorySnapshot(before.messages);
        self.wire_history.deinit();
        self.wire_history = before;
        for (self.history.items[index..]) |*message| message.deinit(self.allocator);
        self.history.shrinkRetainingCapacity(index);
        self.controller.stream.clearRetainingCapacity();
        self.current_turn.deinit(self.allocator);
        if (self.last_user_text) |value| self.allocator.free(value);
        self.last_user_text = null;
        if (self.last_user_wire) |value| self.allocator.free(value);
        self.last_user_wire = null;
        if (self.last_user_attachments) |*bundle| bundle.deinit();
        self.last_user_attachments = null;
        if (self.last_user_images) |*bundle| bundle.deinit();
        self.last_user_images = null;
        self.tool_results.keepTurns(self.history.items);
        self.managerRef().discardTranscript();
        self.clearRequestHistory();
        self.execution().recovery_failed = false;
        self.recovery_pending = null;
        self.execution().request_failure = null;
        self.execution().request_stats = .{ .usage_reported = false };
        self.execution().request_conversation = null;
        self.editing_index = null;
        self.edit_seed = null;
        self.edit_text = null;
        self.compaction.cancel();
        @import("../../../ai/tool_trace.zig").emit(.{ .event = "conversation_rollback", .conversation_id = self.display_conversation, .history_messages = self.wire_history.messages.len, .display_messages = self.history.items.len, .request_history_messages = self.execution().request_history.messages.len, .tool_records = self.tool_results.records.items.len, .manager_cards = self.managerRef().cards.count(), .manager_transcript = if (self.managerRef().tool_run) |run| run.messages.items.len else @as(usize, 0) });
    }
    fn processMessageAction(self: *AiHost) !void {
        const action = self.message_action orelse return;
        self.message_action = null;
        if (action.conversation != null and action.conversation != self.display_conversation) return error.StaleTurn;
        if (self.execution().thread_state.load(.acquire) != 0) return error.AssistantBusy;
        const message = self.userMessage(action.index) orelse return error.StaleTurn;
        switch (action.kind) {
            .rewind => {
                const owner = self.display_owner orelse return;
                const draft = try self.attachmentDraft(owner);
                const images = try self.imageDraft(owner);
                var next_files = try ai_attachments.Draft.init(self.allocator, owner);
                defer next_files.deinit();
                next_files.conversation_id = draft.conversation_id;
                next_files.epoch = draft.epoch;
                next_files.next_id = draft.next_id;
                var next_images = try ai_images.Draft.init(self.allocator, owner);
                defer next_images.deinit();
                next_images.conversation_id = images.conversation_id;
                next_images.epoch = images.epoch;
                next_images.next_id = images.next_id;
                if (message.attachments) |*bundle| try next_files.restoreHistory(bundle) else try next_files.clear();
                if (message.images) |*bundle| try next_images.restoreHistory(bundle) else try next_images.clear();
                const restored_text = try self.allocator.dupe(u8, message.text);
                defer self.allocator.free(restored_text);
                try self.truncateTurns(action.index);
                self.rollback_to_start = self.history.items.len == 0;
                self.cancelConversationReaders(self.display_conversation orelse return);
                std.mem.swap(ai_attachments.Draft, draft, &next_files);
                std.mem.swap(ai_images.Draft, images, &next_images);
                self.prompt.set(restored_text);
                self.recall_index = null;
                if (self.recall_draft) |value| self.allocator.free(value);
                self.recall_draft = null;
                self.conversation_dirty = true;
                if (self.assistant_states) |store| if (self.display_conversation) |id| if (store.find(id)) |state| {
                    store.setPhase(state, if (self.history.items.len == 0) .idle else .done);
                };
                if (self.attachments_view) |view| try view.update(draft);
                if (self.images_view) |view| try view.update(images);
                self.focusComposer();
                self.composer_hash = null;
                self.promptChanged(self.prompt.peek());
                if (self.image_gate == null) if (self.feedback) |view| view.show(@import("../pane/view/ai_feedback_view.zig").rollback_label, .rollback);
                if (self.tail_follow) |*follow| follow.reset();
            },
            .edit => {
                self.editing_index = action.index;
                self.edit_seed = null;
                self.conversation_dirty = true;
            },
            .cancel => {
                self.editing_index = null;
                self.edit_seed = null;
                self.edit_text = null;
                self.conversation_dirty = true;
            },
            .save => {
                const value = (self.edit_text orelse return).peek();
                const copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(copy);
                const owner = self.display_owner orelse return error.StaleTurn;
                const empty: ai_attachments.Bundle = .{ .allocator = self.allocator, .owner = owner, .draft_epoch = 0, .items = &.{} };
                const new_wire = try ai_attachment_request.compose(self.allocator, value, if (message.attachments) |*bundle| bundle else &empty, @import("../../../ai/provider_http.zig").max_request_bytes);
                errdefer self.allocator.free(new_wire);
                const old_wire = if (action.index < self.history.items.len) self.history.items[action.index].wire_text orelse message.text else self.last_user_wire orelse message.text;
                try self.editContext(action.index, old_wire, new_wire);
                if (action.index < self.history.items.len) {
                    const target = &self.history.items[action.index];
                    self.allocator.free(target.text);
                    target.text = copy;
                    if (target.wire_text) |previous| self.allocator.free(previous);
                    target.wire_text = new_wire;
                } else {
                    if (self.last_user_text) |previous| self.allocator.free(previous);
                    self.last_user_text = copy;
                    if (self.last_user_wire) |previous| self.allocator.free(previous);
                    self.last_user_wire = new_wire;
                }
                self.editing_index = null;
                self.edit_seed = null;
                self.edit_text = null;
                self.conversation_dirty = true;
            },
            .fork => self.forkThrough(action.index) catch |err| {
                if (err != error.ResourceCleanupPending) return err;
                self.message_action = action;
                // Retried once its resources are released (a time: release has no single publisher).
                self.wakeAt(16 * std.time.ns_per_ms);
            },
        }
        self.wake();
    }
    fn editContext(self: *AiHost, index: usize, original: []const u8, edited: []const u8) !void {
        const History = @import("../../../ai/wire_history.zig").History;
        const target = self.turnAt(index) orelse return error.StaleTurn;
        const offset = target.before.messages.len;
        const Patch = struct { destination: *History, next: History };
        var patches: std.ArrayList(Patch) = .empty;
        defer {
            for (patches.items) |*patch| patch.next.deinit();
            patches.deinit(self.allocator);
        }
        var contexts: std.ArrayList(*History) = .empty;
        defer contexts.deinit(self.allocator);
        try contexts.append(self.allocator, &self.wire_history);
        for (self.history.items) |*m| if (m.turn) |*turn| {
            try contexts.append(self.allocator, &turn.before);
            try contexts.append(self.allocator, &turn.after);
        };
        try contexts.append(self.allocator, &self.current_turn.before);
        try contexts.append(self.allocator, &self.current_turn.after);
        for (contexts.items) |context| if (try context.editedUser(self.allocator, offset, original, edited)) |next| {
            var owned = next;
            patches.append(self.allocator, .{ .destination = context, .next = next }) catch |err| {
                owned.deinit();
                return err;
            };
        };
        for (patches.items) |patch| if (patch.destination == &self.wire_history) try self.commitHistorySnapshot(patch.next.messages);
        for (patches.items) |*patch| {
            patch.destination.deinit();
            patch.destination.* = patch.next;
            patch.next = .{};
        }
        self.compaction.cancel();
    }
    fn forkThrough(self: *AiHost, index: usize) !void {
        const turn = self.turnAt(index) orelse return error.StaleTurn;
        if (turn.ended_at_ms == null) return error.TurnNotComplete;
        const shared_host = try self.shared();
        const source = self.assistant_states.?.find(self.display_conversation orelse return error.StaleTurn).?;
        const record = shared_host.service.store.find(source.conversation_id) orelse return error.NoStableCheckpoint;
        const runner = self.execution().attached_runner orelse return error.AgentNotFound;
        const owner = self.currentBinding() orelse return error.MissingAssistantOwner;
        if (!owner.eql(runner.agent.owner) or !owner.eql(source.owner)) return error.BindingChanged;
        if (self.conversation_action != null or self.lifecycle_command != null) return error.LifecycleBusy;
        try self.preservePendingEdit();
        try self.persistDisplayedDraft();
        try self.saveDisplayedPresentation();
        var command = try @import("../../../ai/conversation_commands.zig").Command.prepare(&shared_host.service, .copy_use, record.id, runner.agent.id);
        errdefer command.deinit();
        try command.selectCheckpoint(&shared_host.service.store, turn.id, turn.after.messages);
        const sequence = try @import("../../../host/identity.zig").advance(@max(1, self.lifecycle_sequence));
        if (command.needsConfirmation()) if (self.sessions_view) |view| try view.confirmOperation(sequence, "结束当前会话并使用副本？", Confirm.label(.use, "会话副本"));
        self.lifecycle_sequence = sequence;
        self.lifecycle_confirmed = !command.needsConfirmation();
        self.lifecycle_command = command;
        self.wake();
    }
    fn recallPrompt(self: *AiHost, older: bool) bool {
        const input = self.textarea orelse return false;
        const text = input.getText();
        if (input.cursor.hasSelection()) return false;
        const offset = @min(input.cursor.offset, text.len);
        if (older and std.mem.indexOfScalar(u8, text[0..offset], '\n') != null) return false;
        if (!older and std.mem.indexOfScalar(u8, text[offset..], '\n') != null) return false;
        var chosen: ?usize = null;
        if (older) {
            var i = self.recall_index orelse (self.history.items.len + @as(usize, @intFromBool(self.last_user_text != null)));
            while (i > 0) {
                i -= 1;
                if (self.userMessage(i) != null) {
                    chosen = i;
                    break;
                }
            }
            if (chosen == null) return self.recall_index != null;
            if (self.recall_index == null) {
                if (self.recall_draft) |value| self.allocator.free(value);
                self.recall_draft = self.allocator.dupe(u8, text) catch return false;
            }
        } else {
            var i = (self.recall_index orelse return false) + 1;
            while (i <= self.history.items.len) : (i += 1) if (self.userMessage(i) != null) {
                chosen = i;
                break;
            };
        }
        self.recall_index = chosen;
        self.prompt.set(if (chosen) |i| (self.userMessage(i) orelse return false).text else self.recall_draft orelse "");
        self.promptChanged(self.prompt.peek());
        self.wake();
        return true;
    }

    const HistoryRows = struct {
        host: *AiHost,
        starts: std.ArrayList(usize) = .empty,
        fn cleanup(self: *HistoryRows) void {
            self.starts.deinit(self.host.allocator);
        }
        fn render(raw: *anyopaque, slot: usize, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
            const self: *HistoryRows = @ptrCast(@alignCast(raw));
            const host = self.host;
            const previous_scope = host.conversation_scope;
            const previous_turn = host.image_render_turn;
            host.conversation_scope = scope;
            defer {
                host.conversation_scope = previous_scope;
                host.image_render_turn = previous_turn;
            }
            const root = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = host.conversation.?.style.gap, .min_width = 0, .flex_shrink = 0 }, .{});
            const start = self.starts.items[slot];
            // The row by its first message: a captured selection finds it again after a remount.
            try host.row_anchors.put(host.allocator, start, .{ .id = root.id, .generation = try cx.node_registry.trackGeneration(root) });
            host.noteRowMounted(start);
            const end = if (slot + 1 < self.starts.items.len) self.starts.items[slot + 1] else host.history.items.len;
            var prose = false;
            var user: ?usize = null;
            for (host.history.items[start..end], start..) |message, i| {
                if (message.user) {
                    user = i;
                    host.image_render_turn = host.turnAt(i);
                    try host.appendUserMessage(root, message, i);
                    if (host.turnAt(i)) |turn| {
                        prose = turn.prose.items.len > 0;
                        try host.appendTurnSteps(root, turn);
                    }
                } else if (!prose) try root.appendChild(host.allocator, try host.markdown(message.text));
            }
            if (user) |index| try host.appendTurnFooter(root, index);
            return root;
        }
    };
    fn rebuildConversation(self: *AiHost, snap: *const @import("../../../ai/float_view.zig").Snapshot) void {
        // No view, nothing to rebuild (the view built next starts from the model).
        const conv = self.conversation orelse return;
        @import("../../../shared/ui/surface/lifecycle_budget.zig").counters.conversation_rebuilds += 1;
        // The reader's selection, the edited question's caret and a keyboard in either are in the
        // nodes this replaces: take them into the model first and give them to the rebuilt transcript
        // (same model; a selection whose text changed is dropped by `restore`). A close already took
        // everything (`view_state.captured`); the scroll position stays with the ScrollArea.
        if (!self.view_state.captured) {
            self.captureViewState(.transcript);
            if (self.view_state.selection == null and self.view_state.edit == null and self.view_state.focus == .none) self.view_state = .{} else self.view_restore = .rest;
        }
        self.edit_input = null;
        self.row_anchors.clearRetainingCapacity();
        self.live_timeline = null;
        self.conversation_bubble_width = null;
        self.live_card = null;
        self.live_scope = null;
        self.live_dirty = false;
        self.streaming_label = null;
        if (self.cx.pressed_node) |node| if (node.isDescendantOf(conv) or (if (self.turn_footer) |footer| node.isDescendantOf(footer) else false)) self.cx.cancelPointerInteractions(.explicit);
        if (self.cx.focus_manager.current_focus) |node| if (node.isDescendantOf(conv) or (if (self.turn_footer) |footer| node.isDescendantOf(footer) else false)) self.cx.clearFocus();
        if (self.conversation_scope) |scope| scope.dispose();
        self.conversation_scope = null;
        if (self.turn_footer) |footer| {
            while (footer.children.items.len > 0) {
                const child = footer.children.items[footer.children.items.len - 1];
                self.cx.detachChild(footer, child);
                self.cx.destroyDetached(child);
            }
            footer.setDisplay(.none);
        }
        // 清空旧流（status 节点不在 conv 内，安全）。
        var count = conv.children.items.len;
        while (count > 0) : (count -= 1) {
            const child = conv.children.items[count - 1];
            self.cx.detachChild(conv, child);
            if (child != self.status) self.cx.destroyDetached(child);
        }
        const cx = self.cx;
        const allocator = cx.allocator;
        const bubble_content_width = if (self.card_box) |box| messageWidth(box) else @import("../pane/view/ai_assistant_styles.zig").contentWidth(snap.width);
        self.conversation_scope = (self.contentScope() orelse return).childScope() catch return;
        (self.messageWidthModel() catch return).set(bubble_content_width);
        var user_index: ?usize = null;
        var timeline_prose = false;
        self.image_render_turn = null;
        defer self.image_render_turn = null;
        self.history_virtual = self.history.items.len > 48 and self.tail_follow != null;
        // A rebuilt virtual history mounts its rows in its own before-render: what goes back into
        // them waits for its row.
        if (self.view_restore == .rest) self.awaitRestoreRow();
        if (self.history_virtual) {
            const history = self.conversation_scope.?.createState(HistoryRows, .{ .host = self }) catch return;
            for (self.history.items, 0..) |message, i| if (i == 0 or message.user) {
                history.starts.append(allocator, i) catch return;
            };
            self.conversation_scope.?.onCleanup(HistoryRows, history, HistoryRows.cleanup) catch return;
            // Heights are keyed by the conversation's messages; a remount seeds them as estimates
            // (a width change in between only makes them stale estimates, see ai_history_view).
            if (self.history_heights_conversation != self.display_conversation) {
                self.history_heights.clearRetainingCapacity();
                self.history_heights_conversation = self.display_conversation;
            }
            const view = @import("../pane/view/ai_history_view.zig").View.mount(cx, self.conversation_scope.?, self.tail_follow.?.scroll, self.messageWidthModel() catch return, history.starts.items, &self.history_heights, history, HistoryRows.render) catch return;
            conv.appendChild(allocator, view.root) catch return;
        } else {
            for (self.history.items, 0..) |message, message_index| {
                if (message.user) {
                    if (user_index) |previous| self.appendTurnFooter(conv, previous) catch return;
                    user_index = message_index;
                    self.image_render_turn = self.turnAt(message_index);
                    self.appendUserMessage(conv, message, message_index) catch return;
                    timeline_prose = false;
                    if (self.turnAt(message_index)) |turn| {
                        timeline_prose = turn.prose.items.len > 0;
                        self.appendTurnSteps(conv, turn) catch return;
                    }
                } else if (!timeline_prose) conv.appendChild(allocator, self.markdown(message.text) catch return) catch return;
            }
            if (user_index) |previous| self.appendTurnFooter(conv, previous) catch return;
        }
        if (self.last_user_text) |text| {
            self.appendUserMessage(conv, .{ .user = true, .text = text, .attachments = self.last_user_attachments, .images = self.last_user_images }, self.history.items.len) catch return;
            self.appendTurnSteps(conv, &self.current_turn) catch return;
        }
        self.image_render_turn = &self.current_turn;
        // 响应卡片
        var index: usize = 0;
        while (self.current_turn.timeline.items.len == 0 and self.current_turn.prose.items.len == 0 and index < snap.card_count) : (index += 1) {
            const view = self.controller.cardView(index) orelse continue;
            if (view.kind != .text and view.kind != .code) continue;
            const card = ui.box(cx, @import("../pane/view/ai_assistant_styles.zig").assistantMessage(), .{}) catch return;
            const live_text = view.kind == .text and self.execution().thread_state.load(.acquire) == 1;
            const body_text = if (live_text) blk: {
                self.live_scope = self.conversation_scope.?.childScope() catch return;
                self.live_card = card;
                break :blk self.markdownIn(self.live_scope.?, view.body, &self.current_turn) catch return;
            } else if (view.kind == .text) self.markdown(view.body) catch return else @import("../pane/view/ai_message_view.zig").mountCode(cx, self.conversation_scope.?, view.body, view.title) catch return;
            if (index == 0 and view.kind == .text) {
                body_text.meta.ownership.meta.test_id = self.id_space.id("ai.response");
            }
            card.appendChild(allocator, body_text) catch return;
            conv.appendChild(allocator, card) catch return;
        }
        if (self.last_user_text != null) self.appendSteerMessages(conv, self.current_turn.id) catch return;
        if (self.recoveryVisible()) {
            if (self.conversation_scope == null) self.conversation_scope = (self.contentScope() orelse return).childScope() catch return;
            const run = self.managerRef().tool_run;
            const safe = run != null and run.?.compaction_failure == null;
            const unknown_outcome = self.recoveryHasUnknown();
            const cooldown = self.managerRef().cooldownRemainingMs();
            var retained_answer = false;
            for (self.controller.stream.cards.items) |item| switch (item) {
                .text => |text| {
                    if (std.mem.trim(u8, text, " \t\r\n").len > 0 and !std.mem.eql(u8, text, "— 重新尝试答复 —")) {
                        retained_answer = true;
                        break;
                    }
                },
                .code => |code| {
                    if (code.body.len > 0) {
                        retained_answer = true;
                        break;
                    }
                },
                else => {},
            };
            const recovery = @import("../cards/view/ai_recovery_view.zig").mount(cx, self.conversation_scope.?, .{
                .ticket = .{ .owner = self.execution().request_owner.?, .turn = self.managerRef().turn_id, .conversation_id = if (self.execution().request_host_context) |context| context.conversation_id else null },
                .reason = self.recoveryReason(),
                .detail = self.execution().failure_label,
                .title = if (self.execution().request_failure != null and self.execution().request_failure.? == error.ContextFixedOverhead) "模型窗口不足" else if (run != null and run.?.compaction_failure != null) "上下文压缩失败" else if (self.execution().request_failure != null and self.execution().request_failure.? == error.Timeout) "请求超时" else "请求失败",
                .retries = self.managerRef().retry_attempt,
                .max_retries = self.managerRef().retry_policy.max_attempts,
                .retry_enabled = safe and cooldown == 0,
                .regenerate_enabled = !unknown_outcome and cooldown == 0,
                .retry_disabled_reason = if (run == null) "仅重试答复不可用：缺少本轮上下文，请编辑问题后重新发送。" else if (run.?.compaction_failure != null) "仅重试答复不可用：上下文压缩失败，请先修复上下文。" else null,
                .regenerate_disabled_reason = if (unknown_outcome) "新计划不可用：请先核实结果未知的操作。" else null,
                .cooldown_seconds = (cooldown + 999) / 1000,
                .retained_answer = retained_answer,
                .has_tool_calls = if (run) |value| value.records.items.len > 0 else false,
            }, .{ .context = self, .enqueue = enqueueRecovery }) catch return;
            conv.appendChild(allocator, recovery) catch return;
        }
        if (self.last_user_text != null) {
            const footer = self.turn_footer orelse conv;
            footer.setDisplay(.flex);
            self.appendTurnFooter(footer, self.history.items.len) catch return;
        }
        const empty_state = snap.card_count == 0 and self.last_user_text == null and self.history.items.len == 0 and !self.rollback_to_start;
        if (self.empty_state_shown != empty_state) {
            self.empty_state_shown = empty_state;
            self.syncUnconfigured();
        }
        if (empty_state) {
            if (self.conversation_scope == null) self.conversation_scope = (self.contentScope() orelse return).childScope() catch return;
            const Empty = @import("../sessions/view/ai_empty_view.zig");
            var recent: [2]Empty.Recent = undefined;
            var recent_times: [2]u64 = .{ 0, 0 };
            var recent_owners: [2][256]u8 = undefined;
            var recent_count: usize = 0;
            if (self.assistant_states) |store| {
                var recent_index = store.states.items.len;
                while (recent_index > 0) {
                    recent_index -= 1;
                    const state = &store.states.items[recent_index];
                    if (state.child_agent != null or state.closed or !state.listed or self.display_conversation == state.id) continue;
                    var title_scratch: @import("../../../ai/conversation_title.zig").Title = .{};
                    const fallback = state.titleText(state.history.items, state.last_user_text, &title_scratch) orelse continue;
                    if (state.title.text() == null) _ = state.title.set(fallback);
                    const title = state.title.text().?;
                    var sent_at_ms = state.current_turn.sent_at_ms;
                    for (state.history.items) |message| if (message.turn) |turn| {
                        sent_at_ms = @max(sent_at_ms, turn.sent_at_ms);
                    };
                    var slot: usize = 0;
                    while (slot < recent_count and recent_times[slot] >= sent_at_ms) : (slot += 1) {}
                    if (slot >= recent.len) continue;
                    recent_count = @min(recent_count + 1, recent.len);
                    var move = recent_count - 1;
                    while (move > slot) : (move -= 1) {
                        recent[move] = recent[move - 1];
                        recent_times[move] = recent_times[move - 1];
                    }
                    recent[slot] = self.conversationEntry(state.id, title, "");
                    recent_times[slot] = sent_at_ms;
                }
            }
            for (recent[0..recent_count], 0..) |*entry, recent_slot| {
                const state = self.assistant_states.?.find(entry.id) orelse continue;
                entry.owner = if (state.historical_environment and !entry.bound) "历史连接环境" else self.conversationOwnerLabel(state.owner, &recent_owners[recent_slot]);
            }
            const empty = Empty.mount(cx, self.conversation_scope.?, self.hasSelectedModel(), .{ .context = self, .logo_texture = self.welcome_logo_texture, .recent = recent[0..recent_count], .session_hooks = .{ .context = self, .select = selectConversation, .request_close = requestConversationClose, .remove = deleteConversation, .act = conversationAction, .phases = self.sessionPhases() }, .summarize = emptySummarize, .logs = emptyLogs, .history = emptyHistory, .settings = emptySettings, .ollama = emptyOllama }) catch return;
            conv.appendChild(allocator, empty) catch return;
        }
    }

    fn appendSentAttachments(self: *AiHost, parent: *ui.Node, bundle: *const ai_attachments.Bundle) !void {
        if (bundle.items.len == 0) return;
        if (self.conversation_scope == null) self.conversation_scope = try (self.contentScope() orelse return error.MissingAssistantScope).childScope();
        const view = try @import("../attachments/view/ai_attachments_view.zig").View.mount(self.cx, self.conversation_scope.?, .{ .context = self, .preview_sent = AiHost.previewSentAttachment, .on_error = AiHost.attachmentViewError });
        try view.updateSent(bundle);
        try parent.appendChild(self.cx.allocator, view.root);
    }

    /// `ai.launcher` click: open the current tab's panel (the launcher is hidden while it is open).
    pub fn openFromLauncher(self: *AiHost) void {
        // cards-float: with the AI docked in this tab's split the icon stays and focuses the pane.
        if (self.controller.model.visible) {
            if (self.docked() != null) self.focusComposer();
            return;
        }
        self.toggle();
    }

    /// The docked AI pane (window coordinates) while the AI sits in this tab's split.
    fn dockedPaneRect(self: *AiHost) ?launcher_model.Rect {
        const leaf = self.docked() orelse return null;
        const pane = (self.workspace orelse return null).dockedCardPane(leaf) orelse return null;
        const r = pane.globalRect();
        if (r.w <= 0 or r.h <= 0 or !pane.isDisplayedInTree()) return null;
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }

    fn launcherArea(self: *AiHost) ?launcher_model.Rect {
        const workspace = self.workspace orelse return null;
        const r = workspace.terminal_area.globalRect();
        if (r.w <= 0 or r.h <= 0 or !workspace.terminal_area.isDisplayedInTree()) return null;
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }

    const plugin_ui = @import("../../../host/plugin_ui_contract.zig");
    const LauncherCard = struct { context: *anyopaque, info: plugin_ui.LauncherContext };

    /// The plugin content under the launcher's corner (Pencil j8WXoF rule 6: in a split only the
    /// card occupying the corner applies the avoidance rules). Read-only walk of the tabs.
    fn launcherCard(self: *AiHost, corner: launcher_model.Corner, area: launcher_model.Rect) ?LauncherCard {
        const workspace = self.workspace orelse return null;
        const p = launcher_model.cornerPoint(corner, area);
        for (workspace.tabs.items) |tab| {
            if (tab.closing) continue;
            const renderer = tab.plugin_renderer orelse continue;
            const query = renderer.vtable.launcher_context orelse continue;
            const info = query(renderer.context);
            const b = info.bounds orelse continue;
            if (p.x >= b.x and p.x < b.x + b.w and p.y >= b.y and p.y < b.y + b.h) return .{ .context = renderer.context, .info = info };
        }
        return null;
    }

    /// Where the launcher rests in `corner`: fixed in the corner; a top corner sits 12 below the
    /// occupying card's top chrome (j8WXoF O6).
    fn launcherRest(self: *AiHost, corner: launcher_model.Corner, area: launcher_model.Rect) launcher_model.Rect {
        const card = self.launcherCard(corner, area);
        return launcher_model.place(corner, area, if (card) |c| c.info.top_chrome_bottom else null);
    }

    /// Tell the occupying card where the launcher rests (its overlays give way); every other
    /// plugin card hears null. Kept while the panel replaces the icon, so overlays do not jump.
    fn publishLauncher(self: *AiHost, card: ?*anyopaque, rest: ?launcher_model.Rect) void {
        const workspace = self.workspace orelse return;
        for (workspace.tabs.items) |tab| {
            const renderer = tab.plugin_renderer orelse continue;
            const place_fn = renderer.vtable.place_launcher orelse continue;
            const mine = card != null and rest != null and renderer.context == card.?;
            place_fn(renderer.context, if (mine) plugin_ui.LauncherPlacement{
                .corner = std.meta.stringToEnum(plugin_ui.LauncherCorner, @tagName(self.launcher_corner)).?,
                .rect = .{ .x = rest.?.x, .y = rest.?.y, .w = rest.?.w, .h = rest.?.h },
            } else null);
        }
    }

    fn launcherKey(owner: @import("../../../ai/tool_scope.zig").Owner) u64 {
        return switch (owner) {
            .tab => |id| id << 2,
            .session => |id| (id << 2) | 1,
            .group => |id| (id << 2) | 2,
        };
    }

    /// Db7OS: shown while the current tab can start AI and its panel is closed; state by priority.
    fn updateLauncher(self: *AiHost) void {
        const view = self.launcher orelse return;
        if (self.child_identity != null) return;
        const area = self.launcherArea();
        const owner = self.display_owner;
        if (area == null or owner == null or self.currentBinding() == null or !owner.?.eql(self.currentBinding().?)) {
            self.launcher_drag = null;
            self.publishLauncher(null, null);
            view.update(null, .idle, false, false);
            return;
        }
        const corner_card = self.launcherCard(self.launcher_corner, area.?);
        // ai-redesign-c: a docked AI pane in the resting corner — the icon rests beside it instead of over
        // its composer.
        const rest = launcher_model.place(self.launcher_corner, launcher_model.avoidPane(self.launcher_corner, area.?, self.dockedPaneRect()), if (corner_card) |c| c.info.top_chrome_bottom else null);
        self.publishLauncher(if (corner_card) |c| c.context else null, rest);
        const same_owner = self.requestDisplayed();
        const facts: launcher_model.Facts = .{
            .pending = same_owner and (self.execution().tool_bridge.pendingApproval() != null or self.approvalsRef().snapshot() != null or self.execution().inventory_approval.snapshot() != null or self.questionsRef().snapshot() != null),
            .busy = same_owner and self.execution().thread_state.load(.acquire) == 1,
            .failed = same_owner and self.recoveryVisible(),
            .unknown = blk: {
                if (self.tool_results.hasUnknownFor(null, null)) break :blk true;
                if (same_owner) if (self.managerRef().tool_run) |run| if (run.uncertain) break :blk true;
                break :blk false;
            },
        };
        const entry = self.launcher_seen.getOrPut(self.allocator, launcherKey(owner.?)) catch {
            view.update(null, .idle, false, false);
            return;
        };
        // First sight of a tab: what it already shows is not news (restored history).
        if (!entry.found_existing) entry.value_ptr.acknowledge(facts);
        const now = @import("../../../platform/realtime.zig").milliseconds(self);
        const ping = self.launcher_pinger.step(facts.pending, now);
        if (self.controller.model.visible and self.docked() == null) {
            entry.value_ptr.acknowledge(facts);
            self.launcher_drag = null;
            // Reopened before a swipe collapse landed: no icon entrance pending.
            if (self.card) |card| _ = card.takeSwipeArrival();
            // Opening flight: the panel unfolds out of the icon, drawn above it, while the icon fades
            // out (yielded: 150 ms, pointer passes through) — a cross-fade instead of the icon
            // vanishing on the click (the first frames were empty) or on landing (its halo outside
            // the panel popped away then).
            // The fade starts with the first frame the picture is drawn: until then (the expand renders its
            // picture first) the icon stays as it is, so no frame shows neither.
            const opening = if (self.card) |card| card.anchor_flight and card.phase() == .expanding else false;
            const showing = opening and self.card.?.flightShowing();
            view.update(if (opening) rest else null, if (opening) launcher_model.project(entry.value_ptr.flags(facts)) else .idle, false, showing);
            return;
        }
        // The panel is folding into the launcher: the icon is already there under the shrinking,
        // fading panel (drawn above it), so the panel settles into it instead of the icon popping in
        // at full opacity when the flight lands.
        if (if (self.card) |card| card.anchor_flight else false) {
            self.launcher_drag = null;
            const covered = self.card.?.flightCovers(.{ .x = rest.x, .y = rest.y, .width = rest.w, .height = rest.h });
            view.update(if (covered) null else rest, launcher_model.project(entry.value_ptr.flags(facts)), false, false);
            return;
        }
        const state = launcher_model.project(entry.value_ptr.flags(facts));
        const rect = if (self.launcher_drag) |drag| drag.rect else rest;
        // j8WXoF: over a captured remote picture the launcher fades to 0 and lets the pointer through.
        const yielded = self.launcher_drag == null and launcher_model.yields(rest, if (corner_card) |c| if (c.info.captured) |r| launcher_model.Rect{ .x = r.x, .y = r.y, .w = r.w, .h = r.h } else null else null);
        view.update(rect, state, self.launcher_drag != null, yielded);
        // Swipe collapse (Pencil AveHg ③): the panel slid out of the view; the icon fades in at its
        // corner (160 ms after 120 ms, scale 0.92 → 1; reduce motion: a 120 ms fade). Over a
        // captured remote picture it stays yielded.
        if (self.card) |card| if (card.takeSwipeArrival() and !yielded) view.appear(@import("../../../shared/ui/styles/float_card_motion.zig").arrival(card.swipeReduced()));
        if (state == .approval) {
            view.ping(ping.rings);
            if (ping.wake_after_ms) |ms| self.wakeAt(@as(u64, @intCast(@max(1, ms))) * std.time.ns_per_ms);
        }
    }

    /// wqZ1s: drag inside the tab body only; release snaps to the nearest corner, shared by all tabs.
    pub fn dragLauncher(self: *AiHost, event: @import("../pane/view/ai_launcher_view.zig").ButtonDrag) void {
        const view = self.launcher orelse return;
        const area = self.launcherArea() orelse return;
        const animation = ui.fx.animation;
        switch (event.phase) {
            .start => {
                const r = view.rect();
                const start: launcher_model.Rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
                self.launcher_drag = .{ .start = start, .rect = launcher_model.dragged(start, event.dx, event.dy, area) };
                if (!self.cx.reduced_motion) inline for (.{ .scale_x, .scale_y }) |prop| animation.animateNode(view.root, self.allocator, .{ .prop = prop, .to = 1.05, .duration = 0.15 });
            },
            .move => if (self.launcher_drag) |*drag| {
                drag.rect = launcher_model.dragged(drag.start, event.dx, event.dy, area);
            },
            .end => if (self.launcher_drag) |drag| {
                self.launcher_drag = null;
                const corner = launcher_model.nearest(area, drag.rect.x + drag.rect.w / 2, drag.rect.y + drag.rect.h / 2);
                const target = self.launcherRest(corner, area);
                if (!self.cx.reduced_motion) {
                    // motion.normal 150 ms from where it was dropped into the corner.
                    animation.animateNode(view.root, self.allocator, .{ .prop = .translate_x, .from = drag.rect.x - target.x, .to = 0, .duration = 0.15 });
                    animation.animateNode(view.root, self.allocator, .{ .prop = .translate_y, .from = drag.rect.y - target.y, .to = 0, .duration = 0.15 });
                    inline for (.{ .scale_x, .scale_y }) |prop| animation.animateNode(view.root, self.allocator, .{ .prop = prop, .to = 1, .duration = 0.15 });
                }
                self.setLauncherCorner(corner);
            },
            .cancel => {
                self.launcher_drag = null;
                if (!self.cx.reduced_motion) inline for (.{ .scale_x, .scale_y }) |prop| animation.animateNode(view.root, self.allocator, .{ .prop = prop, .to = 1, .duration = 0.15 });
            },
        }
        self.wake();
    }

    fn setLauncherCorner(self: *AiHost, corner: launcher_model.Corner) void {
        self.launcher_corner = corner;
        const runtime = self.runtime_config orelse return;
        const Saved = @import("../../../config/config.zig").LauncherCorner;
        const saved: Saved = std.meta.stringToEnum(Saved, @tagName(corner)).?;
        if (runtime.value.ui.ai_launcher_corner == saved) return;
        var candidate = runtime.value;
        candidate.ui.ai_launcher_corner = saved;
        runtime.save(self.cx.io, std.Io.Dir.cwd(), candidate) catch |err| {
            applog.warn(.app, "AI launcher corner was not saved: {s}", .{@errorName(err)});
        };
    }

    pub fn loadLauncherCorner(self: *AiHost) void {
        const runtime = self.runtime_config orelse return;
        const saved = runtime.value.ui.ai_launcher_corner orelse return;
        self.launcher_corner = std.meta.stringToEnum(launcher_model.Corner, @tagName(saved)).?;
    }
    pub fn requestDisplayed(self: *AiHost) bool {
        return self.execution().request_conversation != null and self.execution().request_conversation == self.display_conversation;
    }
    /// Owner whose panel is on screen now: the bound owner when its panel is open.
    fn presentedNow(self: *AiHost) bool {
        const binding = self.currentBinding() orelse return false;
        const owner = self.display_owner orelse return false;
        return self.controller.model.visible and owner.eql(binding);
    }

    /// The launcher's rect for the current tab (where an open unfolds from and a close folds into).
    fn launcherAnchorRect(self: *AiHost) ?launcher_model.Rect {
        const area = self.launcherArea() orelse return null;
        return self.launcherRest(self.launcher_corner, area);
    }

    /// The panel's default geometry input: the current tab body and its launcher corner (4c-3).
    pub fn floatOrigin(self: *AiHost) ?float_model.Origin {
        const area = self.launcherArea() orelse return null;
        const l = self.launcherRest(self.launcher_corner, area);
        return .{
            .corner = std.meta.stringToEnum(float_model.Corner, @tagName(self.launcher_corner)).?,
            .anchor = .{ .x = l.x, .y = l.y, .width = l.w, .height = l.h },
            .content = .{ .x = area.x, .y = area.y, .width = area.w, .height = area.h },
        };
    }

    /// The generic card's `close` interaction: collapse the panel (the conversation stays).
    pub fn closeFloatCard(ctx: ?*anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(ctx orelse return));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.collapse();
    }

    /// The strip tab id of an AI owner (session tab or group tab), null when its tab is gone.
    fn ownerTabId(self: *AiHost, owner: @import("../../../ai/tool_scope.zig").Owner) ?u64 {
        const bound = self.resolveOwner(owner) orelse return null;
        if (bound.card) |tab| if (tab.closing) return null;
        return bound.tab;
    }

    fn currentTabId(self: *AiHost) ?u64 {
        const workspace = self.workspace orelse return null;
        if (workspace.active_group_view) |id| return if (workspace.groupTabId(std.math.cast(u32, id) orelse return null)) |tab| @backingInt(tab) else null;
        const index = workspace.active_tab orelse return null;
        return if (index < workspace.tabs.items.len) @backingInt(workspace.tabs.items[index].tab_id) else null;
    }

    /// The panel's presentation is the generic floating card's (Card.present): open / close unfold
    /// from / fold into the launcher, a tab switch folds into / unfolds from the owner tab.
    /// The presented state changed (model, owner, current tab): commit it at the next commit point.
    /// Input handlers, async results and the steps of the frame hook only change the model and call
    /// this; nobody but the commit point talks to the card's presentation (LIFECYCLE.md §4).
    fn requestPresentation(self: *AiHost) void {
        self.wake();
    }

    /// The presentation commit point: the first step of the frame hook, before any step of this
    /// frame that changes the conversation tree. A fold-away takes its picture from the frame that
    /// was just displayed; committing here means that picture's tree has not been touched by this
    /// frame's rebuilds (a change made later in the frame is committed at the next frame's start,
    /// after it has been laid out and painted).
    fn updatePresentation(self: *AiHost) void {
        if (self.child_identity != null) return;
        const card = self.card orelse {
            self.panel.setDisplay(if (self.presentedNow()) .flex else .none);
            return;
        };
        const explicit = self.presentation_explicit;
        const swapped = self.presentation_switched;
        self.presentation_explicit = false;
        self.presentation_switched = false;
        // cards-float: while docked the pane shows the content; the floating frame stays hidden.
        const shown = self.presentedNow() and self.docked() == null;
        if (shown and card.presented_visible != shown) self.cx.dispatcher.cancelScrollGesture();
        const launcher: ?float_model.Rect = if (self.launcherAnchorRect()) |l| .{ .x = l.x, .y = l.y, .width = l.w, .height = l.h } else null;
        card.present(.{
            .shown = shown,
            .tab = if (self.display_owner) |owner| self.ownerTabId(owner) else null,
            .current_tab = self.currentTabId(),
            .explicit = explicit,
            .swapped = swapped,
            .anchor = launcher,
        });
    }

    fn updateMotionProbe(self: *AiHost) void {
        const probe = self.motion_probe orelse return;
        const card = self.card orelse return;
        const phase = card.phase();
        const label = if (std.mem.eql(u8, card.anchor_label, "anchor")) "launcher" else card.anchor_label;
        probe.update(card.presentedRect(), card.presentedOpacity(), @tagName(phase), label);
        if (phase == .collapsing or phase == .expanding) self.wake();
    }

    /// Close without motion (the workspace lost its last tab).
    pub fn hidePanelNow(self: *AiHost) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        self.controller.model.visible = false;
        self.controller.model.expanded = false;
        if (self.card) |card| card.hideNow() else self.panel.setDisplay(.none);
    }

    pub fn focusComposer(self: *AiHost) void {
        // The content view is mounted and put where it is shown first (a closed panel has none), so
        // the composer is in the window when it takes the keyboard: no deferred request, the first
        // key after opening already reaches it.
        self.placeContent();
        const input = self.input_node orelse return;
        self.cx.setFocus(input);
    }

    pub fn toggle(self: *AiHost) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        if (self.currentBinding() == null) return;
        // Docked in the current tab's split: the shortcut focuses the pane instead of closing it.
        if (self.controller.model.visible and self.docked() != null and self.display_owner != null and self.display_owner.?.eql(self.currentBinding().?)) {
            self.focusComposer();
            return;
        }
        self.syncOwner() catch return;
        self.presentation_explicit = true;
        if (!self.controller.model.visible) self.captureTerminalFocus();
        if (self.display_conversation) |id| if (self.assistant_states) |store| {
            if (store.find(id)) |state| state.listed = true;
        };
        if (self.controller.model.visible) {
            self.collapse();
            return;
        }
        self.controller.toggle();
        self.controller.model.expanded = self.controller.model.visible;
        self.refresh(if (self.execution().thread_state.load(.acquire) == 1) "AI Float · 请求中" else "AI Float");
        if (self.controller.model.visible) {
            if (self.attachments_view) |view| if (self.display_owner) |owner| view.restoreCandidate(owner) catch {};
            self.focusComposer();
        } else self.restoreTerminalFocus();
    }

    fn ownerPane(self: *AiHost) ?*ui.Node {
        const workspace = self.workspace orelse return null;
        if (workspace.active_group_view) |id| {
            for (workspace.group_views.items) |view| if (view.id == id) return view.root;
            return null;
        }
        const active = workspace.active_tab orelse return null;
        return if (active < workspace.tabs.items.len) workspace.tabs.items[active].root else null;
    }

    pub fn ownerBounds(self: *AiHost) ?ui.ComputedRect {
        const workspace = self.workspace orelse return null;
        if (workspace.active_group_view) |id| return workspace.groupAssistantBounds(id);
        if (workspace.active_tab) |index| if (index < workspace.tabs.items.len) {
            const tab = workspace.tabs.items[index];
            if (tab.file_scope != null) if (self.file_application) |files| if (files.presentation) |presentation| {
                // Plugin content also owns a file_scope; only SFTP has a file presentation.
                if (tab.content_owner == .session) if (presentation.assistantBounds(tab.content_owner.session)) |bounds| return bounds;
            };
        };
        return if (self.ownerPane()) |pane| pane.globalRect() else null;
    }

    /// The width messages lay out in: the content node less its column insets (the docked 720 column,
    /// ai_content_column) less the conversation's own 16 + 16.
    fn messageWidth(box: *ui.Node) f32 {
        return @import("../pane/view/ai_assistant_styles.zig").contentWidth(box.globalRect().w - box.style.padding.left - box.style.padding.right);
    }
    /// The message-width model (created with the host's scope on first use).
    fn messageWidthModel(self: *AiHost) !*ui.Signal(f32) {
        if (self.message_width) |model| return model;
        const scope = self.scope orelse return error.AiHostNotMounted;
        const model = try scope.createSignal(f32, messageWidth(self.card_box orelse self.panel));
        self.message_width = model;
        return model;
    }
    /// Publish the message column's width after the panel's width changed (or after a rebuild);
    /// user bubbles and attachment rails follow the model. Returns whether a new width was applied.
    fn resizeConversationBubbles(self: *AiHost) bool {
        if (self.conversation == null) return false;
        const panel = self.card_box orelse return false;
        const width = panel.globalRect().w;
        if (width <= 0 or self.conversation_bubble_width == width) return false;
        self.conversation_bubble_width = width;
        (self.messageWidthModel() catch return false).set(messageWidth(panel));
        return true;
    }

    /// The panel's focus rule is the generic floating card's (OverlayHost `card`, `float_layer.Card`):
    /// opening remembers where focus was, closing gives it back while focus is still in the panel.
    /// 打开时没有焦点（启动器是原生 GlassButton，点击不取焦点）就回到当前页签的终端（AI 属于这个终端）。
    fn captureTerminalFocus(self: *AiHost) void {
        const card = self.card orelse return;
        card.focusOpened(self.activeTerminalInput());
    }

    fn activeTerminalInput(self: *AiHost) ?*ui.Node {
        const workspace = self.workspace orelse return null;
        const index = workspace.active_tab orelse return null;
        if (index >= workspace.tabs.items.len) return null;
        const tab = workspace.tabs.items[index];
        if (tab.closing) return null;
        const terminal = tab.terminal orelse return null;
        return terminal.root;
    }

    fn restoreTerminalFocus(self: *AiHost) void {
        if (self.card) |card| card.focusClosed();
    }

    pub fn collapse(self: *AiHost) void {
        // Before anything of the close runs: the keyboard and the selection are still the reader's.
        if (self.controller.model.visible) self.captureViewState(.view);
        if (self.lifecycle_command != null and !self.lifecycle_confirmed) {
            self.lifecycle_command.?.deinit();
            self.lifecycle_command = null;
            if (self.sessions_view) |view| view.confirmation.set(false);
        }
        self.close_confirmation = null;
        if (self.close_confirmation_view) |view| view.dismiss();
        if (self.sessions_view) |view| view.open.set(false);
        if (self.card) |card| card.cancel();
        if (self.composer_controls) |controls| controls.dismiss();
        if (self.attachments_view) |view| view.dismiss();
        if (self.images_view) |view| view.dismiss();
        if (self.remote_picker) |picker| picker.close();
        self.controller.model.visible = false;
        self.presentation_explicit = true;
        // Closing changes where the panel is, not what the transcript says: no rebuild (the view is
        // released once the frame has folded away, LIFECYCLE.md §3). A transient notice goes.
        self.setFeedback("");
        self.requestPresentation();
        self.restoreTerminalFocus();
    }

    pub fn closeAssistant(self: *AiHost) void {
        const id = self.display_conversation orelse return;
        conversationAction(self, id, .end);
    }
    fn validateCloseWindowRequest(self: *AiHost, request: CloseWindowRequest) !void {
        const store = if (self.assistant_states) |value| value else return error.StaleCloseConfirmation;
        const state = store.find(request.runtime_id) orelse return error.StaleCloseConfirmation;
        const owner = self.currentBinding() orelse return error.StaleCloseConfirmation;
        if (state.closed or !state.conversation_id.eql(request.ticket.conversation_id) or !state.owner.eql(request.owner) or !owner.eql(request.owner) or self.display_conversation != request.runtime_id or !std.meta.eql(self.current_turn.task_id, request.task_id)) return error.StaleCloseConfirmation;
    }
    pub fn confirmCloseWindow(raw: *anyopaque, ticket: @import("../pane/view/ai_close_confirmation_view.zig").Ticket) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const request = self.close_confirmation orelse return error.StaleCloseConfirmation;
        if (request.ticket.sequence != ticket.sequence or !request.ticket.conversation_id.eql(ticket.conversation_id)) return error.StaleCloseConfirmation;
        try self.validateCloseWindowRequest(request);
        self.close_confirmation = null;
        if (self.lifecycle_command != null and self.lifecycle_sequence == ticket.sequence) self.lifecycle_confirmed = true else self.close_window_requested = request;
        self.wake();
    }
    pub fn cancelCloseWindow(raw: *anyopaque, ticket: @import("../pane/view/ai_close_confirmation_view.zig").Ticket) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const request = self.close_confirmation orelse return;
        if (request.ticket.sequence != ticket.sequence or !request.ticket.conversation_id.eql(ticket.conversation_id)) return;
        self.close_confirmation = null;
        if (self.lifecycle_command != null and self.lifecycle_sequence == ticket.sequence and !self.lifecycle_confirmed) {
            self.lifecycle_command.?.deinit();
            self.lifecycle_command = null;
        }
        self.wake();
    }
    fn updateCloseConfirmation(self: *AiHost) !void {
        const view = self.close_confirmation_view orelse return;
        if (self.close_confirmation) |request| {
            self.validateCloseWindowRequest(request) catch {
                if (self.lifecycle_command != null and !self.lifecycle_confirmed and self.lifecycle_sequence == request.ticket.sequence) {
                    self.lifecycle_command.?.deinit();
                    self.lifecycle_command = null;
                }
                self.close_confirmation = null;
                try view.update(null);
                return;
            };
            var running = self.conversationHasActiveWork(request.runtime_id);
            if (request.task_id) |task| if (self.execution().execution_driver) |driver| if (driver.taskEvidence(task)) |facts| {
                running = running or facts.active_executions > 0 or facts.pending_dispatch > 0;
            };
            try view.update(.{ .ticket = request.ticket, .running = running });
        } else try view.update(null);
    }
    fn applyCloseWindow(self: *AiHost, request: CloseWindowRequest) !void {
        try self.validateCloseWindowRequest(request);
        if (self.shared_service) |shared_host| if (shared_host.service.store.find(request.ticket.conversation_id)) |record| {
            if (record.binding != null) {
                const ticket = try shared_host.service.store.fence(record.id);
                const operation = if (record.ending) |ending| ending.operation else @import("../../../host/identity.zig").HostOperationId.generate();
                try shared_host.service.endConversation(ticket, operation);
                if (record.binding != null) return error.ResourceCleanupPending;
            }
            const state = self.assistant_states.?.find(request.runtime_id).?;
            state.ended = true;
            state.selected = false;
            state.binding_revision = record.revision;
        };
        if (self.execution().request_conversation == request.runtime_id) {
            self.cancelRef().cancel();
            self.approvalsRef().stop();
            self.questionsRef().stop();
            self.execution().inventory_approval.stop();
        }
        if (request.task_id) |task| if (lookupLifecycleTask(self, request.ticket.conversation_id, task)) |controller| {
            if (self.application_host) |app| app.cancelOwnedTask(task);
            if (self.execution().execution_driver) |driver| try driver.stopTask(controller.authority);
        };
        self.cancelConversationReaders(request.runtime_id);
        if (self.compaction.job != null) if (self.compaction.status_identity) |identity| if (identity.conversation == request.runtime_id) self.compaction.cancel();
        // Retain the ended conversation in history, including preview-opened
        // sessions, before selecting a fresh welcome page. Late results keep
        // their original conversation identity.
        self.assistant_states.?.find(request.runtime_id).?.listed = true;
        const welcome = try self.assistant_states.?.create(request.owner);
        welcome.listed = false;
        try self.syncOwner();
        self.collapse();
    }
    fn conversationHasActiveWork(self: *AiHost, id: u64) bool {
        if (self.execution().request_conversation == id and self.execution().thread_state.load(.acquire) == 1) return true;
        for (self.attachment_readers.items) |reader| if (reader.conversation == id) return true;
        for (self.image_readers.items) |reader| if (reader.conversation == id) return true;
        if (self.compaction.job != null) if (self.compaction.status_identity) |identity| if (identity.conversation == id) return true;
        return false;
    }
    fn stopGroupedSource(raw: *anyopaque, source: @import("../../../ai/tab_grouping.zig").Activity) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        if (self.shared_service) |shared_host| if (shared_host.service.store.find(source.conversation)) |record| if (record.binding != null) {
            const ticket = shared_host.service.store.fence(record.id) catch return;
            const operation = if (record.ending) |ending| ending.operation else @import("../../../host/identity.zig").HostOperationId.generate();
            shared_host.service.endConversation(ticket, operation) catch |err| self.setFeedback(@errorName(err));
        };
        if (self.execution().request_conversation == source.id) {
            self.cancelRef().cancel();
            self.approvalsRef().stop();
            self.questionsRef().stop();
            self.execution().inventory_approval.stop();
            self.execution().tool_bridge.stopAll();
        }
        for (self.execution().lifecycle_controllers.items) |controller| {
            if (!controller.authority.conversation_id.eql(source.conversation)) continue;
            if (self.application_host) |app| app.cancelOwnedTask(controller.authority.task_id);
            if (self.execution().execution_driver) |driver| driver.stopTask(controller.authority) catch |err| self.setFeedback(@errorName(err));
        }
        self.cancelConversationReaders(source.id);
        if (self.compaction.job != null) if (self.compaction.status_identity) |value| if (value.conversation == source.id) self.compaction.cancel();
        self.execution().inventory_approval.clearConversation(source.conversation);
        if (self.display_conversation == source.id) self.collapse();
    }
    pub fn commitTabGrouping(self: *AiHost, plan: @import("../../../ai/tab_grouping.zig").Plan) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        const store = if (self.assistant_states) |value| value else return;
        @import("../../../ai/tab_grouping.zig").commit(store, plan, self, stopGroupedSource) catch |err| {
            self.setFeedback(@errorName(err));
            return;
        };
        if (plan.handoff) |handoff| {
            if (self.display_conversation == handoff.runtime_id) self.display_owner = handoff.to;
            if (self.execution().request_conversation == handoff.runtime_id) {
                // A user drop is independent of an AI lifecycle create. Old
                // route choices cannot authorize the expanded member set;
                // the existing round refresh configures the new authority.
                if (self.execution().tool_bridge.route_broker) |broker| broker.execution_route.revoke();
            }
        }
        const owner: ai_attachments.Owner = .{ .tab = plan.container };
        if (store.active(owner) != null) {
            self.execution().host_notice_revision = @max(1, self.execution().host_notice_revision +| 1);
            if (self.execution().request_conversation) |request| if (store.find(request)) |state| if (state.owner.eql(owner)) self.execution().tool_bridge.bindingChanged(owner, .{ .group = plan.group });
        }
        self.conversation_dirty = true;
        self.composer_hash = null;
        self.wake();
    }
    fn conversationEntry(self: *AiHost, id: u64, title: []const u8, owner: []const u8) @import("../sessions/view/ai_sessions_view.zig").Entry {
        var entry: @import("../sessions/view/ai_sessions_view.zig").Entry = .{ .id = id, .title = title, .owner = owner, .can_remove = true };
        const state = (self.assistant_states orelse return entry).find(id) orelse return entry;
        entry.phase = state.phase;
        entry.active = self.display_conversation == id;
        const shared_host = self.shared_service orelse return entry;
        const record = shared_host.service.store.find(state.conversation_id) orelse return entry;
        for (shared_host.service.store.records.items) |candidate| if (candidate.child) |child| if (child.info.owning_parent_conversation.eql(record.id)) {
            entry.has_children = true;
            break;
        };
        entry.bound = record.binding != null;
        entry.ending = record.ending != null;
        entry.first_use = record.parent != null and record.closed_revision == null;
        entry.can_restore = record.binding == null and record.ending == null and record.recoverable and record.history.failure == null and (record.closed_revision != null or record.parent != null);
        entry.can_copy = record.last_turn != 0 and record.recoverable and record.history.failure == null;
        entry.can_remove = record.binding == null and record.ending == null;
        record.inbox.lock();
        defer record.inbox.unlock();
        for (record.inbox.entries.items) |item| if (item.receipt.delivery == .outcome_unknown) {
            entry.can_remove = false;
            break;
        };
        return entry;
    }
    fn conversationHistoryVersion(record: *@import("../../../ai/session_lifecycle.zig").Record) u64 {
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, .{ record.content_revision, record.revision, record.draft_revision, record.ending, record.recoverable });
        record.inbox.lock();
        defer record.inbox.unlock();
        std.hash.autoHash(&hash, record.inbox.queue_revision);
        for (record.inbox.entries.items) |entry| std.hash.autoHash(&hash, entry.receipt);
        return hash.final();
    }
    fn showConversationHistory(self: *AiHost, id: u64) !void {
        const store = self.assistant_states orelse return error.ConversationNotFound;
        const state = store.find(id) orelse return error.ConversationNotFound;
        const record = (try self.shared()).service.store.find(state.conversation_id);
        var out = std.Io.Writer.Allocating.init(self.allocator);
        defer out.deinit();
        if (record) |value| {
            for (value.history.messages) |message| {
                try out.writer.print("{s}\n{s}\n\n", .{ switch (message.role) {
                    .user => "你",
                    .assistant => "AI 助手",
                    .tool => "历史工具结果",
                }, message.content });
            }
            if (value.draft) |draft| if (draft.len != 0) try out.writer.print("未发送草稿\n{s}\n\n", .{draft});
            {
                value.inbox.lock();
                defer value.inbox.unlock();
                for (value.inbox.entries.items) |item| if (!@import("../../../ai/session_input.zig").terminal(item.receipt.delivery)) try out.writer.print("{s}\n{s}\n\n", .{ if (item.receipt.delivery == .outcome_unknown) "待核对：尚不能确认是否消费，不自动重发" else if (item.receipt.delivery == .accepted) "任务已接收，尚未消费；保留原消息，不自动重发" else "待处理输入（不自动执行）", item.payload.messages[0].content });
            }
            self.history_hash = conversationHistoryVersion(value);
        }
        var title_scratch: @import("../../../ai/conversation_title.zig").Title = .{};
        const title = state.titleText(if (self.display_conversation == id) self.history.items else state.history.items, if (self.display_conversation == id) self.last_user_text else state.last_user_text, &title_scratch) orelse "AI 会话";
        if (self.sessions_view) |view| try view.showHistory(self.conversationEntry(id, title, ""), out.written());
    }
    pub fn conversationAction(raw: *anyopaque, id: u64, action: @import("../sessions/view/ai_sessions_view.zig").Action) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.conversation_action != null or self.lifecycle_command != null) {
            self.setFeedback("请先完成或取消当前会话操作");
            return;
        }
        self.conversation_action = .{ .id = id, .action = action, .owner = self.currentBinding(), .current = self.display_conversation };
        self.wake();
    }
    pub fn lifecycleConfirmed(raw: *anyopaque, sequence: u64, accepted: bool) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (sequence != self.lifecycle_sequence or self.lifecycle_command == null) return;
        if (accepted) self.lifecycle_confirmed = true else {
            self.lifecycle_command.?.deinit();
            self.lifecycle_command = null;
        }
        self.wake();
    }
    fn locateConversation(self: *AiHost, id: u64) !void {
        const state = (self.assistant_states orelse return error.ConversationNotFound).find(id) orelse return error.ConversationNotFound;
        const record = (try self.shared()).service.store.find(state.conversation_id) orelse return error.ConversationNotFound;
        const binding = record.binding orelse return error.ConversationUnbound;
        const bridge = self.shared_service.?.bridgeFor(binding.agent) orelse return error.OwnerWindowUnavailable;
        const backend: *AiHost = @ptrCast(@alignCast(bridge.context));
        const view = backend.attachedView();
        const workspace = view.workspace orelse return error.OwnerWindowUnavailable;
        const bound = view.resolveOwner(binding.owner) orelse return error.OwnerWindowUnavailable;
        switch (bound.content) {
            .session => {
                const tab = bound.card orelse return error.OwnerWindowUnavailable;
                const index = for (workspace.tabs.items, 0..) |item, i| {
                    if (item == tab) break i;
                } else return error.OwnerWindowUnavailable;
                workspace.selectTab(index);
            },
            .group => |group| try workspace.openGroup(view.roster orelse return error.OwnerWindowUnavailable, std.math.cast(u32, group) orelse return error.OwnerWindowUnavailable),
        }
        if (self.sessions_view) |popup| {
            popup.history_open.set(false);
            popup.open.set(false);
        }
        _ = view.assistant_states.?.select(id);
        try view.syncOwner();
        view.controller.model.visible = true;
        view.controller.model.expanded = true;
        view.refresh("AI 助手");
        if (process_state.process_windows) |process| for (process.runtime.windows.items) |managed| if (ProcessWindows.navFor(managed.app)) |nav| if (nav.ai == view) {
            managed.app.win.activate();
            break;
        };
    }
    fn processLifecycleAction(self: *AiHost) !void {
        if (self.conversation_action) |action| {
            self.conversation_action = null;
            if (action.action == .more) {
                self.list_limit += 50;
                self.list_requested = true;
                return;
            }
            if (action.action == .children) {
                const state = (self.assistant_states orelse return error.ConversationNotFound).find(action.id) orelse return error.ConversationNotFound;
                self.child_list_parent = state.conversation_id;
                if (self.children_view) |view| view.open.set(true);
                return;
            }
            if (action.action == .view) {
                try self.showConversationHistory(action.id);
                return;
            }
            if (action.action == .locate) {
                try self.locateConversation(action.id);
                return;
            }
            if (action.owner == null or self.currentBinding() == null or !action.owner.?.eql(self.currentBinding().?) or action.current != self.display_conversation) return error.BindingChanged;
            const shared_host = try self.shared();
            if (action.action != .copy) try self.preservePendingEdit();
            try self.persistDisplayedDraft();
            try self.saveDisplayedPresentation();
            const backend = try self.bindAttached(action.owner.?);
            const source = if (self.assistant_states.?.find(action.id)) |state| state.conversation_id else null;
            const kind: @import("../../../ai/conversation_commands.zig").Kind = switch (action.action) {
                .end => .end,
                .new => .new,
                .restore => .restore,
                .copy => .copy,
                .copy_use => .copy_use,
                else => unreachable,
            };
            if (kind == .end and source != null) {
                const current = backend.attached_runner.?.agent.current orelse {
                    // A blank welcome page has only a presentation identity;
                    // there is no bound conversation or resource to end yet.
                    if (shared_host.service.store.find(source.?) == null) {
                        self.collapse();
                        return;
                    }
                    return error.BindingConflict;
                };
                if (!source.?.eql(current)) return error.BindingConflict;
                const record = shared_host.service.store.find(current) orelse return error.ConversationNotFound;
                // Saving an unsent welcome draft can create a binding. It still
                // has no submitted work to end; hide it without replacing its
                // presentation identity or discarding the persisted draft.
                const no_submissions = blk: {
                    record.inbox.lock();
                    defer record.inbox.unlock();
                    break :blk record.inbox.entries.items.len == 0;
                };
                if (self.last_user_text == null and self.history.items.len == 0 and self.wire_history.messages.len == 0 and self.controller.stream.count() == 0 and record.last_turn == 0 and no_submissions and record.ending == null and !self.conversationHasActiveWork(action.id)) {
                    self.collapse();
                    return;
                }
            }
            self.lifecycle_command = try @import("../../../ai/conversation_commands.zig").Command.prepare(&shared_host.service, kind, source, backend.attached_runner.?.agent.id);
            self.lifecycle_sequence = try @import("../../../host/identity.zig").advance(@max(1, self.lifecycle_sequence));
            self.lifecycle_confirmed = !self.lifecycle_command.?.needsConfirmation();
            if (!self.lifecycle_confirmed and kind == .end) {
                const state = self.assistant_states.?.find(self.display_conversation orelse return error.BindingChanged).?;
                self.close_confirmation = .{ .ticket = .{ .sequence = self.lifecycle_sequence, .conversation_id = state.conversation_id }, .runtime_id = state.id, .owner = state.owner, .task_id = self.current_turn.task_id };
                try self.updateCloseConfirmation();
            } else if (!self.lifecycle_confirmed) if (self.sessions_view) |view| try view.confirmOperation(self.lifecycle_sequence, switch (kind) {
                .end => "结束当前 AI 会话？",
                .new => "结束当前会话并新建？",
                .restore => "结束当前会话并恢复？",
                .copy_use => "结束当前会话并使用副本？",
                else => unreachable,
            }, switch (kind) {
                .end => Confirm.label(.end, " AI 会话"),
                .new => Confirm.label(.new, " AI 会话"),
                .restore => Confirm.label(.restore, " AI 会话"),
                .copy_use => Confirm.label(.use, "会话副本"),
                else => unreachable,
            });
        }
        if (self.lifecycle_command) |*command| {
            if (command.kind != .copy and (self.currentBinding() == null or !command.owner.eql(self.currentBinding().?))) {
                command.deinit();
                self.lifecycle_command = null;
                self.lifecycle_confirmed = false;
                if (self.sessions_view) |view| view.confirmation.set(false);
                return error.BindingChanged;
            }
            if (!self.lifecycle_confirmed) return;
            const shared_host = try self.shared();
            try self.assistant_states.?.states.ensureUnusedCapacity(self.allocator, 1);
            const result = (try command.advance(&shared_host.service)) orelse {
                self.promptChanged(self.prompt.peek());
                self.setFeedback("已绑定 · 正在停止任务，等待资源释放");
                if (command.kind != .end and command.end_started) if (self.sessions_view) |view| try view.showProgress(self.lifecycle_sequence);
                self.wakeAt(16 * std.time.ns_per_ms);
                return;
            };
            const kind = command.kind;
            const owner = command.owner;
            const prior = command.previous;
            if (prior) |ticket| if (shared_host.presentations.findConversation(ticket.conversation)) |old| if (shared_host.service.store.find(ticket.conversation)) |record| {
                if (record.binding == null) {
                    old.ended = true;
                    old.selected = false;
                    old.listed = true;
                    old.binding_revision = record.revision;
                }
            };
            if (result.conversation) |id| {
                const record = shared_host.service.store.find(id).?;
                const state = shared_host.presentations.findConversation(id) orelse try shared_host.presentations.create(owner);
                state.conversation_id = id;
                state.initial_owner = record.initial_origin;
                state.owner = owner;
                state.binding_revision = record.revision;
                state.ended = !result.used;
                state.selected = result.used;
                state.listed = true;
                state.closed = false;
                state.historical_environment = true;
                state.controls.permission = null;
                state.controls.execution_mode = null;
                state.controls.ensureDefaults(self.effectiveAi());
                state.controls.session_retention = null;
                if (shared_host.presentations.attachmentDraftFor(state.id)) |draft| draft.owner = owner;
                if (shared_host.presentations.imageDraftFor(state.id)) |draft| draft.owner = owner;
                if (result.used) {
                    _ = shared_host.presentations.select(state.id);
                    self.cancelConversationReaders(state.id);
                }
                if (kind == .copy or kind == .copy_use) {
                    shared_host.presentations.setPhase(state, .done);
                    for (record.history.messages) |message| if (message.role == .user and message.content.len != 0) {
                        _ = state.title.set(message.content);
                        break;
                    };
                }
            } else {
                const welcome = try shared_host.presentations.create(owner);
                welcome.listed = false;
            }
            command.deinit();
            self.lifecycle_command = null;
            self.lifecycle_confirmed = false;
            if (self.sessions_view) |view| {
                view.history_open.set(false);
                view.confirmation.set(false);
                if (kind != .copy) view.open.set(false);
            }
            try self.syncOwner();
            if (kind == .end) self.collapse() else {
                self.controller.model.visible = true;
                self.controller.model.expanded = true;
                self.refresh("AI 助手");
            }
            self.list_requested = kind == .copy;
        }
        if (self.sessions_view) |view| if (view.history_open.peek()) if (view.history_entry) |id| if (self.assistant_states.?.find(id)) |state| if (self.shared_service.?.service.store.find(state.conversation_id)) |record| {
            const hash = conversationHistoryVersion(record);
            if (self.history_hash != hash) try self.showConversationHistory(id);
        };
    }
    pub fn requestConversationClose(raw: *anyopaque, id: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const state = (self.assistant_states orelse return).find(id) orelse return;
        if (self.shared_service) |shared_host| if (shared_host.service.store.find(state.conversation_id)) |record| if (record.binding != null) {
            self.setFeedback("请先结束并解绑此 AI 会话");
            return;
        };
        if (self.sessions_view) |view| view.confirm(id);
    }
    pub fn newConversation(self: *AiHost) void {
        conversationAction(self, self.display_conversation orelse 0, .new);
    }
    pub fn showConversations(self: *AiHost) void {
        if (self.sessions_view) |view| if (view.open.peek()) {
            view.open.set(false);
            return;
        };
        self.list_requested = true;
        self.wake();
    }
    pub fn selectConversation(raw: *anyopaque, id: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.select_requested = id;
        self.wake();
    }
    pub fn deleteConversation(raw: *anyopaque, id: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.delete_requested = id;
        self.wake();
    }
    fn conversationOwnerLabel(self: *AiHost, owner: ai_attachments.Owner, buffer: []u8) []const u8 {
        const bound = self.resolveOwner(owner) orelse return "原 Tab 已关闭";
        switch (bound.content) {
            .session => if (bound.card) |tab| {
                return std.fmt.bufPrint(buffer, "{d} · {s}", .{ (self.workspace.?.model.indexOf(tab.tab_id) orelse 0) + 1, tab.titleSlice() }) catch "Tab";
            },
            .group => |id| if (self.roster) |roster| {
                for (roster.groups.items) |group| if (group.id == id) return std.fmt.bufPrint(buffer, "组 · {s}", .{group.name}) catch "会话组";
            },
        }
        return "原 Tab 已关闭";
    }
    fn cancelConversationReaders(self: *AiHost, id: u64) void {
        var i = self.attachment_readers.items.len;
        while (i > 0) {
            i -= 1;
            const reader = self.attachment_readers.items[i];
            if (reader.conversation == id) {
                reader.cancel();
                reader.deinit();
                _ = self.attachment_readers.orderedRemove(i);
            }
        }
        i = self.image_readers.items.len;
        while (i > 0) {
            i -= 1;
            const reader = self.image_readers.items[i];
            if (reader.conversation == id) {
                reader.cancel();
                reader.deinit();
                _ = self.image_readers.orderedRemove(i);
            }
        }
    }
    fn processConversationActions(self: *AiHost) void {
        self.processLifecycleAction() catch |err| {
            var retryable = false;
            if (self.lifecycle_command) |command| if (command.previous) |ticket| if (self.shared_service.?.service.store.find(ticket.conversation)) |record| if (record.ending) |ending| {
                retryable = ending.operation.eql(command.operation);
            };
            if (retryable) {
                self.lifecycle_confirmed = false;
                if (self.sessions_view) |view| view.confirmOperation(self.lifecycle_sequence, "结束未完成，请重试", Confirm.label(.end, " AI 会话")) catch {};
            } else {
                if (self.lifecycle_command) |*command| command.deinit();
                self.lifecycle_command = null;
                self.lifecycle_confirmed = false;
            }
            self.setFeedback(@errorName(err));
        };

        if (self.close_window_requested) |request| {
            self.applyCloseWindow(request) catch |err| {
                if (err == error.ResourceCleanupPending) {
                    self.wakeAt(16 * std.time.ns_per_ms);
                    return;
                }
                self.close_window_requested = null;
                self.setFeedback(@errorName(err));
                return;
            };
            self.close_window_requested = null;
        }
        if (self.new_requested) {
            if (self.shared_service) |shared_host| if (self.display_conversation) |id| if (self.assistant_states.?.find(id)) |state| if (shared_host.service.store.find(state.conversation_id)) |record| {
                if (record.binding != null) {
                    const ticket = shared_host.service.store.fence(record.id) catch return;
                    const operation = if (record.ending) |ending| ending.operation else @import("../../../host/identity.zig").HostOperationId.generate();
                    shared_host.service.endConversation(ticket, operation) catch |err| {
                        self.setFeedback(@errorName(err));
                        return;
                    };
                    if (record.binding != null) {
                        self.wakeAt(16 * std.time.ns_per_ms);
                        return;
                    }
                }
                state.ended = true;
                state.selected = false;
                state.binding_revision = record.revision;
            };
            self.new_requested = false;
            const owner = self.currentBinding() orelse return;
            self.syncOwner() catch return;
            const retained_draft = self.allocator.dupe(u8, self.prompt.get()) catch return;
            defer self.allocator.free(retained_draft);
            _ = self.assistant_states.?.create(owner) catch return;
            self.syncOwner() catch return;
            self.prompt.set(retained_draft);
            self.controller.model.visible = true;
            self.controller.model.expanded = true;
            self.refresh("AI 助手");
        }
        if (self.select_requested) |id| {
            self.select_requested = null;
            self.showConversationHistory(id) catch |err| self.setFeedback(@errorName(err));
        }
        if (self.delete_requested) |id| {
            self.delete_requested = null;
            const store = if (self.assistant_states) |v| v else return;
            const target = store.find(id) orelse return;
            const owner = target.owner;
            if (self.shared_service) |shared_host| if (shared_host.service.store.find(target.conversation_id)) |record| {
                if (record.binding != null or record.ending != null) {
                    self.setFeedback("请先结束并解绑此 AI 会话");
                    return;
                }
                shared_host.service.store.remove(record.id) catch |err| {
                    self.setFeedback(@errorName(err));
                    return;
                };
            };

            self.execution().inventory_approval.clearConversation(target.conversation_id);
            target.closed = true;
            target.selected = false;
            if (self.execution().request_conversation == id and self.execution().thread_state.load(.acquire) == 1) {
                self.cancelRef().cancel();
                self.execution().tool_bridge.stopAll();
            }
            self.cancelConversationReaders(id);
            if (self.display_conversation == id) {
                self.collapse();
                _ = store.get(owner) catch return;
                self.syncOwner() catch return;
                self.controller.model.visible = false;
                self.refresh("AI 助手");
            }
            if (self.execution().request_conversation != id or self.execution().thread_state.load(.acquire) == 0) store.remove(id);
            self.conversation_dirty = true;
            if (self.sessions_view) |view| {
                if (view.open.peek()) self.list_requested = true;
            }
        }
        if (self.list_requested) {
            self.list_requested = false;
            const store = if (self.assistant_states) |v| v else return;
            if (self.display_conversation) |id| if (store.find(id)) |state| {
                state.listed = true;
            };
            var entries: std.ArrayList(@import("../sessions/view/ai_sessions_view.zig").Entry) = .empty;
            defer {
                for (entries.items) |entry| {
                    self.allocator.free(entry.title);
                    self.allocator.free(entry.owner);
                }
                entries.deinit(self.allocator);
            }
            for (store.states.items) |state| {
                if (state.child_agent != null or state.closed or !state.listed) continue;
                if (entries.items.len == self.list_limit) break;
                var label_buffer: [256]u8 = undefined;
                const bound_now = if (self.shared_service.?.service.store.find(state.conversation_id)) |record| record.binding != null else false;
                const owner_label = if (state.historical_environment and !bound_now) "历史连接环境" else self.conversationOwnerLabel(state.owner, &label_buffer);
                var title_scratch: @import("../../../ai/conversation_title.zig").Title = .{};
                const title = state.titleText(if (self.display_conversation == state.id) self.history.items else state.history.items, if (self.display_conversation == state.id) self.last_user_text else state.last_user_text, &title_scratch);
                const owned_title = if (title) |value| self.allocator.dupe(u8, value) catch return else std.fmt.allocPrint(self.allocator, "新会话 #{d}", .{state.id}) catch return;
                const owned_owner = self.allocator.dupe(u8, owner_label) catch {
                    self.allocator.free(owned_title);
                    return;
                };
                const facts = self.conversationEntry(state.id, owned_title, owned_owner);
                entries.append(self.allocator, .{ .bound = facts.bound, .ending = facts.ending, .can_restore = facts.can_restore, .has_children = facts.has_children, .can_copy = facts.can_copy, .can_remove = facts.can_remove, .first_use = facts.first_use, .id = state.id, .title = owned_title, .owner = owned_owner, .detail = if (self.display_conversation == state.id) self.prompt.peek() else state.draft orelse "空对话", .active = self.display_conversation == state.id, .phase = state.phase }) catch {
                    self.allocator.free(owned_title);
                    self.allocator.free(owned_owner);
                    return;
                };
            }
            if (self.sessions_view) |view| view.show(entries.items) catch {};
        }
    }

    pub fn maximize(self: *AiHost) void {
        // The chrome's maximize button follows the placement (FloatLayer keeps it in step).
        if (self.card) |card| card.toggleMaximized() else self.controller.model.placement.maximized = !self.controller.model.placement.maximized;
        self.wake();
    }

    /// Unified chrome header actions (`FloatLayer` handles maximize): minimize folds the panel into
    /// its launcher, close ends the current conversation (with its confirmation).
    pub fn headerAction(ctx: ?*anyopaque, action: @import("../../../shared/base/float_card.zig").HeaderAction) bool {
        const self: *AiHost = @ptrCast(@alignCast(ctx orelse return false));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        switch (action) {
            .minimize => self.collapse(),
            .close => self.closeAssistant(),
            .dock_to_split => {
                self.dock_request = .dock;
                self.wake();
            },
            .open_as_tab, .maximize => return false,
        }
        return true;
    }

    // ── cards-float：AI 放进所属 tab 的分屏（用户判定“AI chat也是可以放回cards layout的”）──────────

    pub const DockRequest = enum { dock, float_back, close, closed, children, sessions, new_conversation };
    /// The docked pane's own actions in its "更多" menu: the chrome's slot buttons, in their order
    /// (子智能体 · AI 会话列表 · 新建), so docked and floating offer the same entries. The two
    /// popovers open beside 更多 while docked (`ai_popover_anchor`).
    const pane_menu = [_]ws.CardMenuItem{ .{ .label = "子智能体", .icon = "bot" }, .{ .label = "AI 会话列表", .icon = "messages-square" }, .{ .label = "新建 AI 会话", .icon = "plus" } };

    fn docked(self: *const AiHost) ?u64 {
        return self.controller.model.docked_leaf;
    }

    /// Each frame: act on a dock request, drop a stale dock (its tab closed), keep the one content
    /// node where the current owner shows it (its pane, or the floating chrome), and tell the
    /// chrome's 放入分屏 whether the current tab can take a pane now.
    fn syncDock(self: *AiHost) void {
        if (self.child_identity != null) return;
        const workspace = self.workspace orelse return;
        const chrome = self.chrome orelse return;
        if (self.docked()) |leaf| if (workspace.dockedCardTab(leaf) == null) {
            self.controller.model.docked_leaf = null;
        };
        if (self.dock_request) |request| {
            self.dock_request = null;
            switch (request) {
                .dock => self.dockNow(),
                .float_back => self.undockNow(false),
                .close => self.undockNow(true),
                .closed => {
                    // The tab holding the pane closed: its conversation went with it.
                    self.controller.model.docked_leaf = null;
                    self.controller.model.visible = false;
                },
                .children => if (self.children_view) |view| view.toggle(),
                .sessions => self.showConversations(),
                .new_conversation => self.newConversation(),
            }
        }
        self.placeContent();
        self.releaseClosedContent();
        // The header popovers open beside the docked pane's 更多, or beside their chrome buttons.
        const more: ?*ui.Node = if (self.docked()) |leaf| workspace.dockedCardMore(leaf) else null;
        if (self.children_view) |view| view.setAnchor(more);
        if (self.sessions_view) |view| view.setAnchor(more);
        if (self.content_node) |content| self.syncContentColumn(content);
        // O7 / O8: the two popovers stay inside the AI panel (floating chrome) or its pane (docked).
        if (self.children_view) |view| view.setBounds(self.card_box);
        if (self.sessions_view) |view| view.setBounds(self.card_box);
        const refusal: ?[]const u8 = if (self.currentTabId()) |tab| if (workspace.dockRefusal(tab)) |value| value.text() else null else "没有可放入分屏的标签页";
        chrome.setActionState(.dock_to_split, refusal);
    }

    /// Whether the content view is needed now: docked in a split, shown floating, or its floating
    /// frame still in flight (a fold-away takes its picture of the content).
    fn contentWanted(self: *AiHost) bool {
        if (self.docked() != null or self.presentedNow()) return true;
        return if (self.card) |card| card.phase() != .collapsed else self.panel.style.display != .none;
    }

    /// The content view for the current state — the only place the AI decides it (LIFECYCLE.md §3):
    ///   - needed and not mounted: mount it from the model (the reader's captured state follows
    ///     after its first layout);
    ///   - docked and its pane is built: the content node is in that pane's body;
    ///   - floating (shown, or its frame still in flight): in the floating frame's body.
    /// A move goes through `surface_migration` (LIFECYCLE.md §2); calling this again in the same
    /// state does nothing. A view that is no longer needed is released by `releaseClosedContent`
    /// at the frame hook's safe point, not here (this also runs inside input callbacks).
    pub fn placeContent(self: *AiHost) void {
        if (self.child_identity != null) return;
        const chrome = self.chrome orelse return;
        if (!self.contentWanted()) return;
        if (self.content_node == null) {
            const started = @import("../../../platform/realtime.zig").monotonicNs();
            self.mountContent() catch |err| {
                applog.warn(.ui, "AI content view: {s}", .{@errorName(err)});
                return;
            };
            @import("../../../shared/ui/surface/lifecycle_budget.zig").noteContentMount(@import("../../../platform/realtime.zig").monotonicNs() - started);
        }
        const content = self.content_node orelse return;
        if (self.presentedNow()) self.requestViewRestore();
        if (self.docked()) |leaf| {
            const workspace = self.workspace orelse return;
            const host = workspace.dockedCardHost(leaf) orelse return;
            surface_migration.move(self.cx, content, host) catch return;
            if (workspace.dockedCardPane(leaf)) |pane| self.card_box = pane;
            return;
        }
        surface_migration.move(self.cx, content, .{ .parent = chrome.body }) catch return;
        self.card_box = chrome.root;
    }

    /// The panel is closed and its frame has come to rest: release the content view. Frame hook only.
    fn releaseClosedContent(self: *AiHost) void {
        if (self.child_identity != null or self.content_node == null or self.contentWanted()) return;
        // A remote file picker with listings in flight owns worker requests: let them drain first.
        if (self.remote_picker) |picker| if (!picker.shutdown()) {
            self.wakeAt(33 * std.time.ns_per_ms);
            return;
        };
        self.unmountContent();
    }

    /// 宽度规则（用户拍板）：停靠且宽 ≥ 760 时对话与输入区共用 720 宽的居中列（`ai_content_column`）。
    fn syncContentColumn(self: *AiHost, content: *ui.Node) void {
        const width = content.globalRect().w;
        if (width <= 0) return;
        const inset = @import("../pane/model/ai_content_column.zig").inset(self.docked() != null, width);
        if (@abs(content.style.padding.left - inset) < 0.1 and @abs(content.style.padding.right - inset) < 0.1) return;
        var padding = content.style.padding;
        padding.left = inset;
        padding.right = inset;
        content.setStyleInline(self.allocator, .{ .padding = padding });
        self.wake();
    }

    /// 放入分屏: the same content node goes into the current tab's split as a pane (Z12 flight from the
    /// floating rectangle). A single-card tab becomes a split; its conversation hands over to it (M10).
    fn dockNow(self: *AiHost) void {
        const workspace = self.workspace orelse return;
        const content = self.content_node orelse return;
        const chrome = self.chrome orelse return;
        const card = self.card orelse return;
        if (!self.presentedNow() or self.docked() != null) return;
        const tab = self.currentTabId() orelse return;
        const from = chrome.root.globalRect();
        const mode = card.layer.currentMode();
        const result = workspace.dockCard(.{
            .owner_tab = tab,
            .content = content,
            .title = "AI 助手",
            .icon = ui.icons.sparkles,
            .ids = .{ .pane = "ai.pane", .header = "ai.pane.header", .title = "ai.pane.title", .float = "ai.pane.float", .float_tooltip = "ai.pane.float.tooltip", .grip = "ai.pane.drag", .more = "ai.pane.more", .menu = "ai.pane.menu" },
            .port = .{ .ctx = self, .float_back = paneFloat, .closed = paneClosed, .close = paneClose, .menu = &pane_menu, .menu_action = paneMenu, .accent_icon = true },
            .from = from,
            .flight = .{ .anchor = if (mode == .anchor) .{ .rect = .{ .x = from.x, .y = from.y, .w = from.w, .h = from.h } } else .none, .tokens = @import("../../../shared/ui/styles/float_card_motion.zig").placeTokens(mode) },
        }) catch |err| {
            self.setFeedback(@errorName(err));
            return;
        };
        card.hideForDock();
        self.controller.model.docked_leaf = result.leaf;
        if (result.created_from) |source| self.handOffTab(source, result.tab);
        traceDock("dock", mode, from);
        self.wake();
    }

    /// The pane's 浮动 (back to the floating rectangle it left, unfolding from the pane) or 关闭 (the
    /// panel closes; the conversation stays). A split made for the dock goes back to its single-card
    /// tab, and the conversation with it.
    fn undockNow(self: *AiHost, close: bool) void {
        const workspace = self.workspace orelse return;
        const content = self.content_node orelse return;
        const chrome = self.chrome orelse return;
        const leaf = self.docked() orelse return;
        // The one content node goes from the pane straight into the floating frame
        // (`surface_migration`): what the reader holds in it stays — focus, selection, an edit.
        const undocked = workspace.undockCard(leaf, .{ .parent = chrome.body });
        self.controller.model.docked_leaf = null;
        // The conversation follows the tab first (a split made for the dock dissolved): where the
        // content belongs is decided for the owner it has now.
        if (undocked.dissolved_from) |group_tab| if (undocked.tab) |tab| self.handOffTab(group_tab, tab);
        self.placeContent();
        if (close) {
            self.collapse();
            return;
        }
        const card = self.card orelse return;
        if (self.floatOrigin()) |origin| card.update(origin, true);
        const from: ?@import("../../../shared/ui/float_card/float_layer.zig").Rect = if (undocked.rect) |r| .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h } else null;
        card.unfoldFrom(undocked.tab orelse self.currentTabId(), from);
        card.layer.raise(card);
        traceDock("float", card.layer.currentMode(), undocked.rect);
        // Focus that was in the content came along with it; only an AI that did not hold the
        // keyboard takes it now (the reader asked for the panel).
        if (!surface_migration.holdsFocus(self.cx, content)) self.focusComposer();
        self.wake();
    }

    /// M10 handover between a single-card tab and the split made from it for a docked card.
    fn handOffTab(self: *AiHost, from: u64, to: u64) void {
        const store = self.assistant_states orelse return;
        const state = store.active(.{ .tab = from }) orelse return;
        const plan = store.prepareHandoff(state.conversation_id, state.owner, state.binding_revision, .{ .tab = to }) catch |err| {
            self.setFeedback(@errorName(err));
            return;
        };
        store.commitHandoff(plan) catch |err| {
            self.setFeedback(@errorName(err));
            return;
        };
        if (self.display_conversation == plan.runtime_id) self.display_owner = plan.to;
        if (self.execution().request_conversation == plan.runtime_id) {
            if (self.execution().tool_bridge.route_broker) |broker| broker.execution_route.revoke();
            self.execution().host_notice_revision = @max(1, self.execution().host_notice_revision +| 1);
            if (self.ownerContent(plan.to)) |content| self.execution().tool_bridge.bindingChanged(plan.to, content);
        }
        // The conversation is the same one; only the tab it is bound to changed. Its transcript
        // does not show the owner, so it is not rebuilt (the reader's selection, an open editor and
        // its caret live in those nodes). The welcome page lists conversations with their owner.
        if (self.last_user_text == null and self.history.items.len == 0) self.conversation_dirty = true;
        self.composer_hash = null;
    }

    fn traceDock(action: []const u8, mode: @import("../../../shared/ui/float_card/float_layer.zig").TransitionMode, from: ?ui.ComputedRect) void {
        if (!@import("../../../platform/runtime_mode.zig").automation) return;
        const r = from orelse ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        std.debug.print("ZW_AI_DOCK {{\"action\":\"{s}\",\"mode\":\"{s}\",\"from\":[{d:.1},{d:.1},{d:.1},{d:.1}]}}\n", .{ action, @tagName(mode), r.x, r.y, r.w, r.h });
    }

    fn paneFloat(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.dock_request = .float_back;
        self.wake();
    }
    fn paneClose(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.dock_request = .close;
        self.wake();
    }
    fn paneClosed(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.dock_request = .closed;
        self.wake();
    }
    fn paneMenu(raw: *anyopaque, index: usize) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.dock_request = switch (index) {
            0 => .children,
            1 => .sessions,
            2 => .new_conversation,
            else => return,
        };
        self.wake();
    }

    /// The chrome's slot buttons, in `main_window` order: 子智能体 · 会话列表 · 新建.
    pub fn headerSlot(ctx: ?*anyopaque, index: usize) void {
        const self: *AiHost = @ptrCast(@alignCast(ctx orelse return));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        switch (index) {
            0 => if (self.children_view) |view| view.toggle(),
            1 => self.showConversations(),
            2 => self.newConversation(),
            else => {},
        }
    }

    fn hasSelectedModel(self: *AiHost) bool {
        if (self.runtime_config == null) return false;
        const controls = self.selectedControls() catch return false;
        _ = ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model) catch return false;
        return true;
    }

    fn emptyHistory(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.showConversations();
    }

    fn emptySummarize(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        // Append to the current owner's draft; never overwrite existing input.
        const previous = self.prompt.peek();
        const next = std.fmt.allocPrint(self.allocator, "{s}{s}请概括终端报错，分析所选文字或最近输出。", .{ previous, if (previous.len == 0) "" else "\n" }) catch return;
        defer self.allocator.free(next);
        self.prompt.set(next);
        self.promptChanged(self.prompt.peek());
        self.focusComposer();
    }

    fn emptyLogs(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const owner = self.display_owner orelse return;
        self.chooseLocalText(owner, null) catch |err| self.refresh(@errorName(err));
    }

    fn emptySettings(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.settings_request = false;
        self.wake();
    }

    fn emptyOllama(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.settings_request = true;
        self.wake();
    }

    /// The current model configuration problem (none = a usable model is selected), independent of typing.
    fn modelConfigurationProblem(self: *AiHost) ?anyerror {
        if (self.runtime_config == null) return null;
        // No owner yet (no tab): nothing to guide.
        const controls = self.selectedControls() catch return null;
        _ = ai_provider_config.fromSettingsSelection(self.effectiveAi(), controls.model) catch |err| return err;
        return null;
    }

    /// The unconfigured guide's place: the empty state (empty conversation) or the Alert above the
    /// composer (conversation with history) — never both (`ai_unconfigured_view.placement`).
    fn syncUnconfigured(self: *AiHost) void {
        const view = self.unconfigured orelse return;
        const unconfigured = @import("../pane/view/ai_unconfigured_view.zig");
        const problem = self.modelConfigurationProblem();
        switch (unconfigured.placement(problem, self.empty_state_shown)) {
            .none, .empty_state => view.hide(),
            .alert => {
                var buffer: [512]u8 = undefined;
                if (unconfigured.isMissing(problem.?)) view.show(unconfigured.missing_title, unconfigured.missing_message) else view.show(unconfigured.unusable_title, @import("../../../shared/base/feedback_message.zig").message(@errorName(problem.?), &buffer));
            },
        }
    }

    /// “配置 AI 服务”（就地提示的动作）：与空状态 / 模型菜单的“设置”同一个入口，打开 AI 设置。
    fn configureService(self: *AiHost) void {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        emptySettings(self);
    }

    fn composerSettings(raw: *anyopaque) void {
        emptySettings(raw);
    }

    pub fn openRequestedSettings(self: *AiHost) void {
        const ollama = self.settings_request orelse return;
        self.settings_request = null;
        const settings = self.settings_host orelse return;
        if (settings.busy()) return;
        if (!settings.open) settings.toggle();
        if (!settings.open) return;
        if (self.composer_controls) |controls| controls.dismiss();
        settings.navigateSettings(.{ .page = 4, .sub = 0 }); // AI 辅助 › 服务提供方
        if (ollama) for (settings.controller.model.value.ai.providers[0..settings.controller.model.value.ai.provider_count], 0..) |provider, index| {
            if (provider.kind != .ollama) continue;
            settings.controller.ai_fields.provider_open.put(self.allocator, index, true) catch return;
            settings.controller.ai_fields.connection_open.put(self.allocator, index, true) catch return;
            settings.controller.scroll_offsets[4] = 0;
            break;
        };
        self.wake();
    }

    fn recoveryReason(self: *AiHost) []const u8 {
        return if (self.execution().request_failure) |err|
            @import("../../../ai/error_feedback.zig").recoveryReason(err, self.execution().failure_label, if (self.execution().native_context) |context| context.diagnostic.status else 0)
        else
            "请求失败，已保留收到的内容";
    }

    fn recoveryHasUnknown(self: *const AiHost) bool {
        if (self.managerRef().tool_run) |run| if (run.uncertain) return true;
        // The displayed Store is conversation-owned and may retain an earlier
        // assistant binding from the same turn (for example session -> group).
        return self.tool_results.hasUnknownFor(null, self.managerRef().turn_id);
    }
    fn recoveryVisible(self: *AiHost) bool {
        if (!self.requestDisplayed() or !self.execution().recovery_failed or self.execution().thread_state.load(.acquire) != 0) return false;
        const owner = self.display_owner orelse return false;
        if (self.execution().request_host_context) |context| return owner.eql(context.binding);
        const captured = self.execution().request_owner orelse return false;
        return owner.eql(captured);
    }

    fn enqueueVerification(raw: *anyopaque, ticket: @import("../cards/view/ai_verification_view.zig").Ticket) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.verification_pending == null) self.verification_pending = ticket;
        self.wake();
    }
    fn readVerification(raw: *anyopaque, anchor: @import("../../../ai/readonly_verification.zig").Anchor) !@import("../../../ai/readonly_verification.zig").Observation {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.validateVerificationTarget(anchor);
        const observed = if (anchor.execution_id != null) blk: {
            const context = anchor.context orelse return error.TargetNotAuthorized;
            const backend = if (self.execution().execution_backend) |*value| value else return error.VerificationSourceUnavailable;
            break :blk try backend.observeVerification(anchor, context);
        } else try self.execution().tool_bridge.observeVerification(self.application_host orelse return error.StaleSession, anchor);
        try self.validateVerificationTarget(anchor);
        return observed;
    }
    fn validateVerificationTarget(self: *AiHost, anchor: @import("../../../ai/readonly_verification.zig").Anchor) !void {
        const app = self.application_host orelse return error.StaleSession;
        const owner = self.display_owner orelse return error.TargetNotAuthorized;
        const captured = try self.captureOwnerScope(owner);
        defer if (captured.inventory) |inventory| self.allocator.free(inventory);
        if (std.mem.indexOfScalar(u64, captured.memberIds(), @backingInt(anchor.owner.session_id)) == null) return error.TargetNotAuthorized;
        const state = app.sessions.queryState(anchor.owner) orelse return error.StaleSession;
        if (anchor.create_key) |key| if (!state.create_operation.eql(key)) return error.StaleSession;
        if (!app.sessions.bindingIsLive(anchor.service)) return error.StaleBinding;
        const service = switch (app.sessions.queryService(anchor.owner, anchor.service.kind)) {
            .available => |binding| binding,
            else => return error.ServiceDenied,
        };
        try @import("../../../ai/readonly_verification.zig").validateBinding(anchor, state.handle, service, state.create_operation);
        const id = app.legacyForHandle(anchor.owner) orelse return error.StaleSession;
        const tab = app.workspace.sessionTab(id) orelse return error.StaleSession;
        if (!tab.content_owner.eql(.{ .session = anchor.owner }) or tab.closing or tab.failed or tab.isCard()) return error.StaleSession;
        if (!tab.local) {
            const runtime = tab.runtime orelse return error.StaleSession;
            const reconnect = runtime.reconnectSnapshot() orelse return error.StaleSession;
            if (reconnect.phase != .active and reconnect.phase != .ready) return error.StaleSession;
            if (anchor.create_key) |key| if (reconnect.key == null or !reconnect.key.?.eql(key)) return error.StaleSession;
        }
    }
    fn applyVerification(self: *AiHost) !void {
        const ticket = self.verification_pending orelse return;
        self.verification_pending = null;
        const V = @import("../../../ai/readonly_verification.zig");
        if (self.display_owner == null or !self.display_owner.?.eql(ticket.owner)) return;
        const states = if (self.assistant_states) |value| value else return;
        const displayed = states.find(self.display_conversation orelse return) orelse return;
        if (ticket.conversation_id == null or !displayed.conversation_id.eql(ticket.conversation_id.?)) return;
        for (self.tool_results.records.items) |record| {
            const anchor = ticket.resolve(record) orelse continue;
            const observed = if (self.execution().thread_state.load(.acquire) != 0) V.Observation{ .anchor = anchor, .observed_at_ms = @import("../../../platform/realtime.zig").milliseconds(self), .failure = error.OperationBusy } else V.observe(anchor, @import("../../../platform/realtime.zig").milliseconds(self), .{ .context = self, .read = readVerification });
            const history = if (ticket.target_index) |index| &record.targets[index].checks else &record.checks;
            const extra = if (history.items.capacity == 0) @sizeOf(V.Observation) * V.History.max_observations else @as(usize, 0);
            try history.append(record.arena.allocator(), observed);
            self.tool_results.retained_bytes += extra;
            if (self.execution().thread_state.load(.acquire) == 0) if (self.managerRef().tool_run) |run| if (run.turn_id == record.turn_id and run.scope.owner.eql(record.owner) and self.execution().request_host_context != null and record.conversation_id != null and self.execution().request_host_context.?.conversation_id.eql(record.conversation_id.?)) {
                var summary: [768]u8 = undefined;
                var note: [1536]u8 = undefined;
                const text = try std.fmt.bufPrint(&note, "Original call {s}, target #{d} generation {d}, observed_at_ms {d}: {s}\n", .{ record.call_id, @backingInt(anchor.owner.session_id), anchor.owner.generation, observed.observed_at_ms, observed.describe(&summary) });
                if (run.verification_notes.items.len + text.len > 8192) run.verification_notes.clearRetainingCapacity();
                try run.verification_notes.appendSlice(run.arena.allocator(), text);
            };
            self.conversation_dirty = true;
            self.wake();
            return;
        }
    }
    fn enqueueRecovery(raw: *anyopaque, envelope: @import("../cards/view/ai_recovery_view.zig").Envelope) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.recovery_pending == null) self.recovery_pending = envelope;
        self.wake();
    }

    // Run at the after-layout safe point, after owner synchronization. Button
    // callbacks never dispose their own conversation scope or change targets.
    fn applyRecovery(self: *AiHost) void {
        const envelope = self.recovery_pending orelse return;
        self.recovery_pending = null;
        if (!self.recoveryVisible() or envelope.ticket.turn != self.managerRef().turn_id or !envelope.ticket.owner.eql(self.execution().request_owner.?)) return;
        const current = self.currentBinding() orelse return;
        if (envelope.ticket.conversation_id) |conversation| {
            const context = self.execution().request_host_context orelse return;
            if (!context.conversation_id.eql(conversation) or !current.eql(context.binding)) return;
        } else if (!current.eql(envelope.ticket.owner)) return;
        const question = self.last_user_text orelse return;
        if (envelope.action == .edit) {
            const previous = self.prompt.peek();
            const text = if (previous.len == 0) self.allocator.dupe(u8, question) else if (std.mem.endsWith(u8, previous, question)) self.allocator.dupe(u8, previous) else std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ previous, question });
            const draft = text catch return;
            defer self.allocator.free(draft);
            self.prompt.set(draft);
            self.promptChanged(self.prompt.peek());
            if (self.input_node) |node| self.cx.setFocus(node);
            return;
        }
        if (self.managerRef().cooldownRemainingMs() != 0) return;
        if (envelope.action == .regenerate) {
            if (self.recoveryHasUnknown()) return;
            // submit allocates a new turn and captures fresh permission/scope.
            // It copies question before changing the retained conversation.
            const draft = self.allocator.dupe(u8, self.prompt.peek()) catch return;
            defer self.allocator.free(draft);
            self.submit(question);
            // This action resubmits the original question, not the next draft.
            self.prompt.set(draft);
            self.promptChanged(self.prompt.peek());
            return;
        }
        if (self.managerRef().tool_run == null or self.managerRef().tool_run.?.compaction_failure != null) return;
        // Snapshot/ledger and Provider binding remain frozen. Never call submit
        // or prepare a new bridge for an answer-only continuation.
        self.controller.stream.clearRetainingCapacity();
        for (self.managerRef().cards.cards.items) |card| _ = self.controller.stream.append(card) catch return;
        self.execution().retry_prefix_count = self.controller.stream.count();
        self.execution().answer_only = true;
        self.execution().attached_finalized = false;
        self.execution().request_stats = .{ .usage_reported = false };
        self.cancelRef().* = .{};
        self.execution().request_failure = null;
        self.execution().thread_state.store(1, .release);
        const shared_host = self.shared_service orelse return;
        const runner = self.execution().attached_runner orelse return;
        const conversation = runner.agent.current orelse return;
        shared_host.service.resumeAnswer(shared_host.service.store.fence(conversation) catch return) catch |err| {
            self.execution().thread_state.store(0, .release);
            self.execution().request_failure = err;
            self.execution().answer_only = false;
            self.refresh(@errorName(err));
            return;
        };
        self.execution().recovery_failed = false;
        self.current_turn.ended_at_ms = null;
        self.refresh("AI 助手");
    }

    fn sendPrompt(self: *AiHost) void {
        if (@import("../../../update/admission.zig").blocked()) return;
        self.submit(self.prompt.get());
    }

    fn previewInputRoute(self: *AiHost, mode: @import("../../../ai/session_input.zig").Mode) @import("../../../ai/session_input.zig").Route {
        const host = self.shared_service orelse return .start;
        const state = (self.assistant_states orelse return .start).find(self.display_conversation orelse return .start) orelse return .start;
        const ticket = host.service.store.fence(state.conversation_id) catch return .queue;
        return host.service.previewInput(ticket, mode) catch .queue;
    }
    const shortcut_router = @import("../../shell/mod.zig").shortcut_router;
    /// 输入框里“换一种跟进方式”的组合（局部键，文字来自快捷键路由）。
    const alternate_follow_up = shortcut_router.defaultHint(.ai_alternate_follow_up);
    /// 快捷键路由（键位读 `[keys]`）：粘贴图片的组合与提示文字都从这里取。
    fn shortcuts(self: *const AiHost) shortcut_router.Router {
        const defaults = struct {
            const map: shortcut_router.Map = .{};
        };
        return .{ .keys = if (self.runtime_config) |runtime| &runtime.value.keys else &defaults.map };
    }
    fn refreshSendHint(self: *AiHost) void {
        const mode = if (self.runtime_config) |config| config.value.ai.follow_up_mode else .steer;
        const route = self.previewInputRoute(mode);
        const opposite = self.previewInputRoute(if (mode == .steer) .queue else .steer);
        if (self.send_hint) |hint| {
            const text = switch (route) {
                .start => "发送问题",
                .steer => "引导当前任务 · " ++ alternate_follow_up ++ " 加入队列",
                .queue => if (opposite == .steer) "加入队列 · " ++ alternate_follow_up ++ " 引导当前任务" else "加入队列，当前任务就绪后处理",
            };
            if (!std.mem.eql(u8, hint.peek(), text)) hint.set(text);
        }
        if (self.composer) |composer| composer.setSendHint(composer.controls.send_hint.peek(), switch (route) {
            .start => "发送问题",
            .steer => "引导当前任务",
            .queue => "加入队列",
        });
    }
    /// Composer area margins by width (Pencil Kaf7E ⑤): 0 12 12 12; a 320-class panel 8; docked in a
    /// pane 16; from 760 wide the composer shares the conversation's centered 720 column.
    fn layoutComposerArea(self: *AiHost) bool {
        const area = self.composer_node orelse return false;
        const parent = area.parent orelse return false;
        const width = parent.globalRect().w;
        if (width <= 0) return false;
        // Short panels: the decision content scrolls sooner so the panel keeps its header, some
        // conversation and the decision row (≤ 180, ≥ 60).
        const capped = if (self.composer_interaction) |interaction| interaction.setMaxBody(parent.globalRect().h * 0.4) else false;
        if (capped) return true;
        const in_pane = self.child_identity == null and self.docked() != null;
        const margin: f32 = if (width <= 340) 8 else if (in_pane) 16 else 12;
        // ≥ 760: the 720 column is ai.content's own margins (ai-redesign-c); the area keeps its 16.
        const side: f32 = margin;
        // Top 6: with the conversation's 6 bottom margin, replies end 12 above the composer
        // (Pencil: the conversation's own 16 bottom padding, ai-redesign-b).
        const next: ui.Padding = .{ .left = side, .right = side, .bottom = margin, .top = 6 };
        // The column gives the conversation what the composer area leaves: pin the area to its
        // content height (queue, decision panel or composer field, 8 apart, plus the bottom margin).
        var content: f32 = 0;
        var shown: f32 = 0;
        for (area.children.items) |child| {
            if (child.style.display == .none or child.style.position == .absolute) continue;
            const h = child.globalRect().h;
            if (h <= 0) continue;
            content += h;
            shown += 1;
        }
        const height = content + @max(0, shown - 1) * 8 + margin + 6;
        self.composer_height = height;
        self.composer_margins = next;
        const composer = self.composer orelse return false;
        return composer.setArea(next, height, side);
    }
    /// Pencil Kaf7E A8: while a turn runs, Stop shows; Send stays for a draft (it steers or
    /// queues, see refreshSendHint) and gives way to Stop while the draft is empty.
    fn syncActions(self: *AiHost, text: []const u8) void {
        const busy = self.execution().thread_state.load(.acquire) == 1 and self.requestDisplayed();
        const draft = text.len != 0 or (if (self.attachments_view) |view| view.height() > 0 else false);
        if (self.composer) |composer| composer.setActions(busy, !(busy and !draft));
    }
    fn sendComposer(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.sendPrompt();
    }
    fn stopComposer(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.stop();
    }
    fn composerPromptChanged(raw: *anyopaque, text: []const u8) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        self.promptChanged(text);
    }
    pub fn promptChanged(self: *AiHost, text: []const u8) void {
        self.refreshSendHint();
        self.syncActions(text);

        var ready: usize = 0;
        var processing = self.attachment_picker_active;
        var image_problem: ?anyerror = null;
        var has_images = if (self.last_user_images) |bundle| bundle.items.len > 0 else false;
        for (self.history.items) |message| if (message.images) |bundle| {
            has_images = has_images or bundle.items.len > 0;
        };
        if (self.display_owner) |owner| {
            if (self.attachmentDraft(owner)) |draft| {
                ready = draft.items.items.len;
                processing = processing or draft.pending.items.len != 0;
            } else |_| {}
            if (self.imageDraft(owner)) |draft| {
                has_images = has_images or draft.items.items.len > 0;
                for (draft.items.items) |item| switch (item.state) {
                    .ready => ready += 1,
                    .processing => {
                        processing = true;
                        image_problem = error.AttachmentsProcessing;
                    },
                    .failed => {
                        processing = true;
                        image_problem = error.ImageAttachmentFailed;
                    },
                };
            } else |_| {}
            if (has_images and image_problem == null) {
                const controls = self.selectedControls() catch null;
                const selected = if (self.runtime_config != null) ai_provider_config.fromSettingsSelection(self.effectiveAi(), if (controls) |value| value.model else null) catch null else null;
                if (selected) |config| {
                    if (!config.vision) image_problem = error.ModelDoesNotSupportImages else if (config.kind != .openai_compat) image_problem = error.UnsupportedImageProtocol else if (!config.supportsImageBudget()) image_problem = error.UnknownImageBudget;
                } else image_problem = error.MissingModel;
            }
        }
        const ending = if (self.shared_service) |host| if (self.assistant_states.?.find(self.display_conversation orelse 0)) |state| if (host.service.store.find(state.conversation_id)) |record| record.ending != null else false else false else false;
        if (self.send_disabled) |disabled| disabled.set((self.child_identity != null and !self.childCanWrite()) or ending or !self.hasSelectedModel() or (std.mem.trim(u8, text, " \t\r\n").len == 0 and ready == 0) or processing or image_problem != null);
        const gate_changed = self.image_gate != image_problem;
        self.image_gate = image_problem;
        var model_problem: ?anyerror = null;
        if (self.runtime_config != null and (std.mem.trim(u8, text, " \t\r\n").len != 0 or ready > 0)) {
            const controls = self.selectedControls() catch null;
            _ = ai_provider_config.fromSettingsSelection(self.effectiveAi(), if (controls) |value| value.model else null) catch |err| blk: {
                model_problem = err;
                break :blk null;
            };
        }
        const model_gate_changed = self.model_gate != model_problem;
        self.model_gate = model_problem;
        if (model_gate_changed and model_problem == null and image_problem == null) if (process_state.process_notifications) |notifications| if (self.notification_window) |window| notifications.resolveOperationErrors(window, "AI 助手");
        // Keep the reason visible through unrelated refreshes while sending is
        // blocked. Clearing the last image also clears the obsolete warning.
        // 模型配置问题的引导（主会话判定，ai-redesign-c 对齐 panel-heads 的就地提示）：空对话只在空状态里引导，
        // 已有对话历史时才在输入区上方放原生 W.Alert；两者不同时出现，也不再走全局提醒。
        self.syncUnconfigured();
        if (self.execution().thread_state.load(.acquire) != 1) {
            const inline_model = self.unconfigured != null and model_problem != null;
            if (image_problem) |problem| self.setFeedback(imageGateLabel(problem)) else if (model_problem != null and !inline_model) self.setFeedback(@errorName(model_problem.?)) else if (gate_changed or model_gate_changed) self.setFeedback("");
        }
    }

    fn preflightMessages(self: *AiHost, prompt: []const u8) !std.ArrayList(ai_provider.Message) {
        var messages: std.ArrayList(ai_provider.Message) = .empty;
        errdefer messages.deinit(self.allocator);
        const context = &self.wire_history;
        if (context.failure) |err| return err;
        try messages.appendSlice(self.allocator, context.messages);
        try messages.append(self.allocator, .{ .content = prompt });
        return messages;
    }

    fn composerEvent(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *AiHost = @ptrCast(@alignCast(raw orelse return .ignored));
        const textarea = self.textarea orelse return .ignored;
        switch (event) {
            .key_down => |key| if (self.shortcuts().match(key.key, key.modifiers) == .paste and !textarea.imeIsComposing()) {
                const sdk = self.cx.system_sdk orelse return .ignored;
                const kinds = sdk.clipboardProbe() catch return .ignored;
                if (!kinds.image) return .ignored;
                const owner = self.display_owner orelse return .ignored;
                self.pasteImages(owner) catch |err| self.refresh(@errorName(err));
                return .stop;
            } else if ((key.key == .up or key.key == .down) and !key.modifiers.super and !key.modifiers.alt and !key.modifiers.shift and !textarea.imeIsComposing()) {
                if (self.recallPrompt(key.key == .up)) return .stop;
            } else if (key.key == .@"return") {
                switch (@import("../composer/view/ai_composer_keys.zig").handleReturn(key, textarea)) {
                    .composing => return .ignored,
                    .alternate => {
                        const configured = (self.runtime_config orelse return .stop).value.ai.follow_up_mode;
                        self.submitAttached(self.prompt.get(), if (configured == .steer) .queue else .steer) catch |err| self.refresh(@errorName(err));
                    },
                    .newline => {},
                    .submit => self.sendPrompt(),
                }
                return .stop;
            },
            .drag => |drag| {
                if (drag.payload_kind != .file_or_url or textarea.imeIsComposing()) return .ignored;
                if (drag.kind != .dropped) return .handled;
                if (drag.payload_truncated) {
                    self.refresh("拖入文件列表不完整，请重新选择");
                    return .stop;
                }
                const owner = self.display_owner orelse return .ignored;
                var paths = std.mem.splitScalar(u8, drag.paths, '\n');
                while (paths.next()) |path| {
                    if (path.len == 0) continue;
                    self.addImagePath(owner, path) catch |err| {
                        self.refresh(@errorName(err));
                        return .stop;
                    };
                }
                return .stop;
            },
            else => {},
        }
        return .ignored;
    }

    const AttachedInput = struct {
        id: @import("../../../host/identity.zig").SubmissionId,
        text: []u8,
        wire: []u8,
        config: ?@import("../../../config/runtime_config.zig").Snapshot,
        controls: @import("../../../ai/assistant_store.zig").Controls,
        attachments: ai_attachments.Bundle,
        images: ai_images.Bundle,
        fn deinit(self: *@This(), a: std.mem.Allocator) void {
            a.free(self.text);
            a.free(self.wire);
            if (self.config) |*config| config.deinit();
            self.controls.deinit(a);
            self.attachments.deinit();
            self.images.deinit();
        }
    };
    fn attachedInput(self: *AiHost, id: @import("../../../host/identity.zig").SubmissionId) !*AttachedInput {
        for (self.attached_inputs.items) |*input| if (input.id.eql(id)) return input;
        return error.SubmissionNotFound;
    }
    fn bindAttached(self: *AiHost, owner: @import("../../../ai/tool_scope.zig").Owner) !*AiHost {
        if (self.child_identity != null) return self.bindUserChild(owner);
        const shared_host = try self.shared();
        const agent = try shared_host.service.store.attach(owner);
        if (shared_host.bridgeFor(agent.id)) |bridge| {
            const execution_host: *AiHost = @ptrCast(@alignCast(bridge.context));
            self.execution_host = execution_host;
            return execution_host;
        }
        if (shared_host.closing) return error.ApplicationClosing;
        try shared_host.bridges.ensureUnusedCapacity(shared_host.allocator, 1);
        const a = std.heap.c_allocator;
        const execution_host = try a.create(AiHost);
        errdefer a.destroy(execution_host);
        execution_host.* = self.attachedSlot(a, shared_host);
        execution_host.bindExecutionWake(self);
        const runner = try shared_host.service.attach(owner, .{ .context = execution_host, .wake = &execution_host.wake_target, .capture = captureAttached, .prepare = prepareAttached, .completed = completeAttached, .local_released = attachedReleased, .supersede = supersedeAttached, .stop = stopAttached, .release_worker = releaseAttachedWorker });
        execution_host.attached_runner = runner;
        try shared_host.register(.{ .agent = agent.id, .window = self.application_host.?.window_id, .context = execution_host, .pump = pumpAttached, .released = disposeReadyAttached, .destroy = destroyAttached, .flush = flushAttached });
        self.execution_host = execution_host;
        return execution_host;
    }
    fn attachedSlot(self: *AiHost, a: std.mem.Allocator, shared_host: *@import("../../../ai/attached_service.zig").Host) AiHost {
        return .{
            .allocator = a,
            .cx = undefined,
            .panel = undefined,
            .status = undefined,
            .prompt = undefined,
            .controller = AiController.init(a),
            .manager = AiManager.init(a),
            .stream_mailbox = @import("../../../ai/stream_mailbox.zig").Mailbox.init(a),
            .step_mailbox = @import("../../../ai/step_events.zig").Mailbox.init(a),
            .tool_bridge = @import("../tools/host/ai_tools.zig").Bridge.init(a),
            .execution_bridge = @import("../tools/host/ai_tools.zig").Bridge.init(a),
            .tool_results = @import("../../../ai/tool_results.zig").Store.init(a),
            .provider = undefined,
            .native_context = null,
            .native_client = null,
            .native_binding = null,
            .endpoint = "",
            .model = "",
            .backend_owner = self,
            .shared_service = shared_host,
            .assistant_states = &shared_host.presentations,
            .application_host = self.application_host,
            .workspace = self.workspace,
            .roster = self.roster,
            .file_application = self.file_application,
            .data_root = self.data_root,
            .recording_archive = self.recording_archive,
            .notification_window = self.notification_window,
        };
    }
    fn attachedView(self: *AiHost) *AiHost {
        return self.backend_owner orelse self;
    }
    fn withAttachedView(self: *AiHost) ?*AiHost {
        const view = self.attachedView();
        const previous = view.execution_host;
        view.execution_host = self;
        return previous;
    }
    fn captureAttached(raw: *anyopaque, context: @import("../../../ai/session_runtime.zig").Context) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.attached_finalized = false;
        const stamp = try self.resourceStamp();
        if (self.resource_stamp) |previous_stamp| if (stamp != previous_stamp) {
            self.resource_stamp = stamp;
            try self.refreshAttachedEnvironment();
            return error.StaleEnvironment;
        };
        self.resource_stamp = stamp;
        const input = try self.attachedInput(context.submission);
        const live_config = self.backend_owner.?.runtime_config.?.value;
        if (live_config.config_revision != input.config.?.value.config_revision) {
            var frozen_ai = input.config.?.value.ai;
            frozen_ai.follow_up_mode = live_config.ai.follow_up_mode;
            frozen_ai.permission_mode = live_config.ai.permission_mode;
            frozen_ai.execution_mode = live_config.ai.execution_mode;
            frozen_ai.extensions = live_config.ai.extensions;
            frozen_ai.child_context_mode = live_config.ai.child_context_mode;
            frozen_ai.child_reuse_policy = live_config.ai.child_reuse_policy;
            if (!@import("../../../config/settings_schema.zig").same(frozen_ai, live_config.ai)) return error.StaleConfiguration;
        }
        const view = self.attachedView();
        const previous = self.withAttachedView();
        defer view.execution_host = previous;
        const selected = view.display_conversation != null and view.assistant_states.?.find(view.display_conversation.?) != null and view.assistant_states.?.find(view.display_conversation.?).?.conversation_id.eql(context.fence.conversation);
        const state = self.assistant_states.?.findConversation(context.fence.conversation) orelse return error.ConversationNotFound;
        self.request_conversation = state.id;
        self.request_owner = context.owner;
        self.context_usage_mailbox.reset(context.turn);
        self.managerRef().turn_id = context.turn;
        if (self.request_config) |*old| old.deinit();
        var generation_config = input.config.?.value;
        generation_config.config_revision = live_config.config_revision;
        generation_config.agent_policy_revision = live_config.agent_policy_revision;
        self.request_config = try @import("../../../config/runtime_config.zig").Snapshot.init(self.allocator, generation_config);
        if (self.extension_session) |*old| old.deinit();
        self.extension_session = null;
        var extensions = self.request_config.?.value.ai.extensions;
        if (self.attached_runner.?.record.?.child) |owned_child| {
            const child_info = owned_child.info;
            extensions = try @import("../../../ai/extension_gateway.zig").select(self.request_config.?.arena.allocator(), extensions, (if (self.childRecord()) |record| @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record).skill_ids else child_info.skill_ids), (if (self.childRecord()) |record| @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record).mcp_ids else child_info.mcp_ids));
        }
        self.extension_session = try @import("../../../ai/extension_gateway.zig").Session.init(self.allocator, extensions, self.data_root);
        const controls = input.controls;
        const selected_config = try ai_provider_config.fromSettingsSelection(self.request_config.?.value.ai, controls.model);
        if (self.native_context == null) {
            self.native_context = try self.allocator.create(NativeContext);
            self.native_context.?.* = .{ .io = undefined };
        }
        if (self.native_client == null) self.native_client = try self.allocator.create(AiClient);
        if (self.native_binding == null) self.native_binding = try self.allocator.create(AiClient.Binding);
        self.native_binding.?.config = selected_config;
        self.endpoint = selected_config.endpoint;
        self.model = selected_config.model;
        self.request_effort = controls.effort;
        self.request_thinking = controls.thinking;
        self.live_reasoning.set(controls.effort, controls.thinking);
        self.request_vision = selected_config.vision;
        self.request_image_token_reservation = selected_config.image_token_reservation;
        self.request_image_token_max_width = selected_config.image_token_max_width;
        self.request_image_token_max_height = selected_config.image_token_max_height;
        self.request_max_output = 0;
        self.request_policy_revision = self.request_config.?.value.agentPolicyRevision();
        self.request_execution_policy = @import("../../../config/config.zig").resolveExecutionPolicy(self.request_config.?.value.ai, controls.execution_mode, controls.session_retention);
        self.request_permission_mode = controls.permission orelse self.request_config.?.value.ai.permission_mode;
        if (context.child_origin != null and self.parentPermission() != .auto) self.request_permission_mode = .confirm;
        self.managerRef().permission_engine.mode = if (self.request_permission_mode == .auto) .auto else .confirm;
        self.managerRef().live_permission.reset();
        const allowed = try self.captureOwnerScope(context.owner);
        if (self.attached_scope) |old| if (old.inventory) |ids| self.allocator.free(ids);
        self.attached_scope = allowed;
        self.managerRef().scope = allowed;
        try self.validateAttachmentScope(allowed, &input.attachments);
        try self.tool_bridge.beginRequest();
        self.request_tools = &.{};
        self.request_tools_len = 0;
        self.request_tool_tokens = 0;
        self.request_host_context = null;
        self.managerRef().tool_host = null;
        if (self.request_context) |*old| old.deinit(self.allocator);
        self.request_context = null;
        const rules = try @import("../../../ai/session_prompt.zig").build(self.allocator, self.request_execution_policy.execution_mode, &.{});
        self.request_context = .{ .text = rules, .tokens = @import("../../../ai/card.zig").estimateTokens(rules.len), .truncated = false };
        // 绑定是 tab（M10）；单卡 tab 与组 tab 的差别只在捕获的内容上。
        const held = allowed.contentOf();
        const tab = if (held == .session) self.tabForSession(held.session) else if (allowed.memberIds().len != 0) self.tabForSession(allowed.memberIds()[0]) else null;
        self.request_session = if (tab) |value| value.id else null;
        if (self.application_host) |app| if (self.assistantToolsAvailable(context.owner)) {
            const authority: @import("../../../ai/host_tools.zig").Context = .{ .conversation_id = context.fence.conversation, .task_id = context.task, .binding = context.owner, .content = held, .binding_revision = context.fence.binding, .grant_revision = self.request_policy_revision, .child_origin = context.child_origin };
            self.request_host_context = authority;
            // This turn's brokers (the worker's own, or the host's) show their requests in this host's view.
            self.approvalsRef().wake = &self.execution().wake_target;
            self.questionsRef().wake = &self.execution().wake_target;
            try self.approvalsRef().configure(authority, self.request_policy_revision);
            self.questionsRef().configure(authority);
            try self.inventory_approval.configure(authority, self.request_policy_revision);
            self.tool_bridge.configureFiles(self.file_application);
            self.tool_bridge.configurePolicy(self.managerRef().permission_engine, self.request_policy_revision);
            self.tool_bridge.execution_mode = self.request_execution_policy.execution_mode;
            self.tool_bridge.session_retention = self.request_execution_policy.session_retention;
            try self.tool_bridge.configureRouting(self.approvalsRef(), authority, input.text, if (tab) |value| value.content_owner.session else null);
            if (self.lifecycle_runtime == null) self.lifecycle_runtime = .{ .journal_owner = try @import("../../../ai/lifecycle_runtime.zig").ProcessJournal.acquire(.{ .data_root = self.data_root }), .controller = .{ .context = self, .invoke = lifecycleCall }, .approval = self.approvalsRef() };
            try self.prepareLifecycleTask(authority);
            self.authority_notice_revision = self.host_notice_revision;
            self.prepareHostCatalog(app);
            try self.tool_bridge.configureHost(.{ .context = authority, .handler_context = self, .invoke = queryHost, .invoke_worker = dispatchHostWorker, .contributions = self.host_catalog[0..self.host_catalog_len], .refresh = refreshHostAuthority, .acknowledge_notice = acknowledgeHostNotice, .accepted_result = acceptedHostResult });
            if (held == .group) try self.tool_bridge.prepareGroup(app, self.roster orelse return error.ContextUnavailable, allowed) else if (context.child_origin != null) try self.tool_bridge.prepareScope(app, allowed) else try self.tool_bridge.prepare(app, (tab orelse return error.StaleSession).content_owner.session);
            self.request_tools = try @import("../../../ai/plugin_tools.zig").providerDefinitions(self.tool_bridge.requestTable().?, self.request_config.?.arena.allocator());
            self.request_tools_len = self.request_tools.len;
            self.request_tool_tokens = try @import("../../../ai/local_text_request.zig").toolTokens(self.request_tools[0..self.request_tools_len]);
            const scoped_rules = try @import("../../../ai/session_prompt.zig").buildConfigured(self.allocator, self.request_execution_policy.execution_mode, self.request_tools[0..self.request_tools_len], .{ .context_mode = self.request_config.?.value.ai.child_context_mode, .reuse_policy = self.request_config.?.value.ai.child_reuse_policy });
            self.allocator.free(self.request_context.?.text);
            self.request_context.?.text = scoped_rules;

            self.managerRef().tool_host = self.tool_bridge.interface();
            self.managerRef().scope = self.tool_bridge.requestTable().?.captured_scope;
            try self.prepareRecordingAccess(authority);
            if (std.mem.allEqual(u8, &self.host_cursor_key, 0)) {
                @memcpy(self.host_cursor_key[0..16], &@import("../../../host/identity.zig").TaskId.generate().bytes);
                @memcpy(self.host_cursor_key[16..32], &@import("../../../host/identity.zig").TaskId.generate().bytes);
            }
            const controller = lookupLifecycleTask(self, authority.conversation_id, authority.task_id).?;
            const summary = try @import("../tools/host/ai_host_queries.zig").requestSummary(app, self.roster, .{ .execution_policy = controller.execution_policy, .permission_mode = self.request_permission_mode, .host_contributions = self.tool_bridge.host_binding.?.contributions }, self.host_cursor_key, authority, self.allocator);
            defer self.allocator.free(summary);
            const combined = try std.fmt.allocPrint(self.allocator, "{s}\n<host_session_facts>\n{s}\n</host_session_facts>\n", .{ self.request_context.?.text, summary });
            self.allocator.free(self.request_context.?.text);
            self.request_context.?.text = combined;
            self.request_context.?.tokens = @import("../../../ai/card.zig").estimateTokens(combined.len);
        };
        if (self.request_text) |old| self.allocator.free(old);
        self.request_text = try self.allocator.dupe(u8, input.wire);
        self.answer_only = false;
        self.request_failure = null;
        self.recovery_failed = false;
        self.retry_prefix_count = 0;
        self.request_stats = .{ .usage_reported = false };
        self.request_content_owner = if (held == .group) .{ .group = .{ .id = @fromBackingInt(@intCast(held.group)) } } else (tab orelse return error.StaleSession).content_owner;
        self.request_operation_id = if (process_state.process_notifications) |notifications| if (self.notification_window) |window| try notifications.reserveAiConversation(window, context.fence.conversation) else null else null;
        if (selected) try view.retainCurrentTurn() else {
            if (state.last_user_text) |text| {
                var message = try (HistoryMessage{ .user = true, .turn = state.current_turn, .text = text, .wire_text = state.last_user_wire, .attachments = state.last_user_attachments, .images = state.last_user_images }).clone(self.allocator);
                errdefer message.deinit(self.allocator);
                try state.history.append(self.allocator, message);
            }
            for (state.stream.cards.items) |card| if (card == .text) try state.history.append(self.allocator, .{ .user = false, .text = try self.allocator.dupe(u8, card.text) });
            state.stream.clearRetainingCapacity();
            state.current_turn.deinit(self.allocator);
        }
        var meta: @import("../../../ai/conversation_turn.zig").Turn = .{ .id = context.turn, .task_id = context.task, .sent_at_ms = @intCast(@max(0, @import("../../../platform/realtime.zig").milliseconds(self))), .started_mono_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) };
        meta.before = try @import("../../../ai/wire_history.zig").History.copy(self.allocator, self.shared_service.?.service.store.find(context.fence.conversation).?.history.messages, "");
        if (selected) {
            view.current_turn = meta;
            if (view.last_user_text) |old| view.allocator.free(old);
            view.last_user_text = try view.allocator.dupe(u8, input.text);
            if (view.last_user_wire) |old| view.allocator.free(old);
            view.last_user_wire = try view.allocator.dupe(u8, input.wire);
            if (view.last_user_attachments) |*old| old.deinit();
            view.last_user_attachments = try input.attachments.retain();
            if (view.last_user_images) |*old| old.deinit();
            view.last_user_images = try input.images.retain();
            view.controller.setPrompt(input.text);
            view.conversation_dirty = true;
            // The reader's own new question starts a new turn: follow it to the end again.
            if (view.tail_follow) |*follow| follow.reset();
        } else {
            state.current_turn = meta;
            if (state.last_user_text) |old| self.allocator.free(old);
            state.last_user_text = try self.allocator.dupe(u8, input.text);
            if (state.last_user_wire) |old| self.allocator.free(old);
            state.last_user_wire = try self.allocator.dupe(u8, input.wire);
            if (state.last_user_attachments) |*old| old.deinit();
            state.last_user_attachments = try input.attachments.retain();
            if (state.last_user_images) |*old| old.deinit();
            state.last_user_images = try input.images.retain();
        }
        // One automatic title per conversation: the first question becomes the fallback (and marks
        // the attempt), the request runs beside the reply and `PollHook` publishes it to the
        // original conversation. Child dialogs are not listed and take no title request; a restored
        // conversation that already has user turns is not renamed after a followup.
        const first_question = for (meta.before.messages) |message| {
            if (message.role == .user) break false;
        } else true;
        if (state.child_agent == null and first_question and state.beginTitle(input.text)) {
            view.conversation_titles.start(view.allocator, selected_config, state.conversation_id, input.text, controls.effort) catch |err| {
                std.log.debug("conversation title request unavailable: {s}", .{@errorName(err)});
            };
        }
        self.assistant_states.?.setPhase(state, .running);
        self.thread_state.store(1, .release);
        self.tool_bridge.events = &self.step_mailbox;
        self.tool_bridge.image_lookup = .{ .context = self, .find = findRetainedImage };
        self.tool_bridge.beginAutomationRun(&self.attached_runner.?.worker.?.cancel.cancelled);
    }
    fn prepareAttached(raw: *anyopaque, _: std.mem.Allocator, io: std.Io, _: @import("../../../ai/session_runtime.zig").Context) !@import("../../../ai/session_runtime.zig").Prepared {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.native_context.?.* = .{ .io = io };
        if (self.recording_access) |*access| access.backend.archive.io = io;
        self.native_client.?.* = AiClient.native(self.allocator, self.native_context.?, switch (self.native_binding.?.config.kind) {
            .anthropic => .anthropic,
            .openai_compat => .openai_compat,
            .ollama => .ollama,
        });
        self.native_binding.?.client = self.native_client.?;
        self.provider = self.native_binding.?.asProvider();
        const prepared_request = self.native_binding.?.config.chatRequest(.{ .model = self.model, .system = self.request_context.?.text, .messages = &.{}, .effort = self.request_effort, .thinking = self.request_thinking, .tools = self.request_tools[0..self.request_tools_len], .tool_table = self.tool_bridge.requestTable(), .tool_images = self.request_vision, .max_output = self.request_max_output });
        self.request_usage_fixed = try @import("../../../ai/context_usage.zig").Fixed.capture(prepared_request);
        return .{ .context = self, .destroy = finishPreparedAttached, .reasoning = &self.live_reasoning, .provider = self.provider, .request = prepared_request, .scope = if (self.answer_only) self.managerRef().tool_run.?.scope else self.managerRef().scope.?, .host = self.managerRef().tool_host, .policy = self.managerRef().permission_engine, .policy_revision = self.request_policy_revision, .limits = .{ .context_window = self.native_binding.?.config.context_window }, .compaction = self.native_binding.?.config, .observer = .{ .context = self, .reset = streamReset, .delta = streamDelta, .tool_rejected = streamToolRejected, .round_start = streamRoundStart, .context_usage = streamContextUsage, .input_consumed = streamInputConsumed } };
    }
    fn finishPreparedAttached(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.tool_bridge.endAutomationRun();
        if (self.extension_session) |*session| session.finish();
        if (self.recording_access) |*access| access.deinit();
        self.recording_access = null;
    }
    fn completeAttached(raw: *anyopaque, runner: *@import("../../../ai/session_runtime.zig").Runner) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.tool_bridge.endAutomationRun();
        self.request_stats = runner.stats;
        self.request_failure = runner.failure;
        if (runner.failure) |err| self.failure_label = if (self.native_context) |native| native.diagnostic.format(&self.failure_detail, err) else @errorName(err);
        const state: u8 = if (runner.worker.?.cancel.isCancelled()) 4 else if (runner.failure != null) 3 else 2;
        const view = self.attachedView();
        const previous = self.withAttachedView();
        defer view.execution_host = previous;
        // Saving can fail after finalization. Retrying persistence must never
        // finish the turn again, change its counters or rebuild its UI.
        if (!self.attached_finalized) {
            self.thread_state.store(state, .release);
            view.finalizeWorker(state);
            self.attached_finalized = true;
        }
        try view.saveConversationPresentation(self.request_conversation orelse return);
        var index: usize = 0;
        while (index < self.attached_inputs.items.len) {
            const receipt = runner.record.?.inbox.receipt(self.attached_inputs.items[index].id) orelse {
                index += 1;
                continue;
            };
            if (@import("../../../ai/session_input.zig").terminal(receipt.delivery)) {
                var consumed = self.attached_inputs.orderedRemove(index);
                consumed.deinit(self.allocator);
            } else index += 1;
        }
    }
    fn supersedeAttached(raw: *anyopaque, _: @import("../../../ai/session_runtime.zig").Context) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.approvalsRef().supersede();
        self.questionsRef().supersede();
        self.inventory_approval.supersede();
    }
    fn stopAttached(raw: *anyopaque, _: @import("../../../ai/session_runtime.zig").Context) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.inventory_approval.stop();
        const view = self.attachedView();
        if (view.compaction_agent) |agent| if (agent.eql(self.attached_runner.?.agent.id)) view.compaction.cancel();
        if (self.request_host_context) |context| {
            if (self.application_host) |app| app.cancelOwnedTask(context.task_id);
            if (self.execution_driver) |driver| driver.stopTask(context) catch {};
        }
    }
    fn resourceStamp(self: *AiHost) !u64 {
        const owner = self.attached_runner.?.agent.owner;
        const allowed = try self.captureOwnerScope(owner);
        defer self.allocator.free(allowed.inventory.?);
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, owner);
        if (allowed.contentOf() == .group) {
            const group = (self.roster orelse return error.StaleGroup).findById(std.math.cast(u32, allowed.contentOf().group) orelse return error.StaleGroup) orelse return error.StaleGroup;
            std.hash.autoHash(&hash, group.membership_revision);
        }
        for (allowed.memberIds()) |id| {
            const tab = self.tabForSession(id) orelse return error.StaleSession;
            std.hash.autoHash(&hash, tab.content_owner.session);
            if (tab.runtime) |remote| if (remote.reconnectSnapshot()) |snapshot| {
                std.hash.autoHash(&hash, snapshot.key);
                std.hash.autoHash(&hash, snapshot.phase == .active or snapshot.phase == .ready);
            };
        }
        return hash.final();
    }
    /// A resource change invalidates the attached environment (approvals superseded, route choice
    /// revoked). When it is the AI's own lifecycle work — a committed session -> group handoff or
    /// membership change, or the session a route choice's bound create is making joining the
    /// group — that trusted route choice is put back afterwards (same context only,
    /// `execution_routing.holdLive`); the environment change itself is unchanged.
    fn refreshAttachedEnvironment(self: *AiHost) !void {
        const carried = if (self.tool_bridge.route_broker) |broker| broker.execution_route.holdLive(self.lifecycle_transition) else null;
        self.lifecycle_transition = false;
        try self.invalidateAttachedEnvironment();
        if (carried) |held| if (self.tool_bridge.route_broker) |broker| broker.execution_route.restore(held);
    }
    fn invalidateAttachedEnvironment(self: *AiHost) !void {
        const shared_host = self.shared_service.?;
        const runner = self.attached_runner.?;
        const id = runner.agent.current orelse return;
        const ticket = try shared_host.service.store.fence(id);
        // 单卡 tab 的环境变化直接开新环境；组 tab 的成员变化走监管的环境切换。
        if ((self.ownerContent(runner.agent.owner) orelse return error.StaleSession) == .session) {
            _ = try shared_host.service.environmentChanged(ticket);
            return;
        }
        const next = try shared_host.service.store.environmentChanged(runner.agent.id);
        runner.commit_fence = next;
        const record = shared_host.service.store.find(id).?;
        record.inbox.lock();
        if (record.ending == null) record.inbox.closing = false;
        record.inbox.unlock();
        supersedeAttached(self, runner.context orelse return);
    }
    pub fn closeAttachedSession(self: *AiHost, owner: @import("../../../host/identity.zig").SessionHandle, release_content: bool) application_host_mod.CloseReceipt {
        // An entry point from input or another component: the pass handles what it changed.
        defer self.wake();
        const shared_host = self.shared_service orelse return .released;
        const previous = self.execution_host;
        defer self.execution_host = previous;
        var result: application_host_mod.CloseReceipt = .released;
        // 关闭的会话卡片所在的单卡 tab：绑定在它上面的对话随之结束（M10：归属是 tab）。
        const closing_tab: ?ai_attachments.Owner = if (self.tabForSession(@backingInt(owner.session_id))) |tab| tabOwner(tab) else null;
        for (shared_host.bridges.items) |bridge| {
            if (bridge.disposed) continue;
            const backend: *AiHost = @ptrCast(@alignCast(bridge.context));
            self.execution_host = backend;
            const receipt = self.executionCloseStep(owner, release_content);
            if (receipt != .released) result = if (receipt == .unknown) .unknown else if (result == .released) .awaiting else result;
            if (!release_content) {
                const stopped = backend.tool_bridge.stopOwner(owner);
                if (stopped != .released) result = if (stopped == .unknown) .unknown else if (result == .released) .awaiting else result;
                const runner = backend.attached_runner.?;
                if (closing_tab != null and runner.agent.owner.eql(closing_tab.?)) if (runner.agent.current) |id| {
                    const record = shared_host.service.store.find(id).?;
                    const operation = if (record.ending) |ending| ending.operation else @import("../../../host/identity.zig").HostOperationId.generate();
                    shared_host.service.endConversation(shared_host.service.store.fence(id) catch return .unknown, operation) catch return .unknown;
                    if (record.binding != null and result == .released) result = .awaiting;
                };
            }
        }
        return result;
    }
    /// The queue editor's state: the main panel keeps it in its own Scope, a child dialog's view its own.
    fn pendingEdit(self: *AiHost) ?*@import("../approvals/view/ai_pending_view.zig").Edit {
        if (self.pending_edit) |edit| return edit;
        return if (self.pending_view) |view| view.edit else null;
    }
    fn preservePendingEdit(self: *AiHost) !void {
        const edit = self.pendingEdit() orelse return;
        if (self.pending_view) |view| if (view.cancel_requested) return;
        const editing = edit.editing orelse (if (self.pending_view) |view| view.edit_requested else null) orelse return;
        const state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
        if (!state.conversation_id.eql(editing.receipt.fence.conversation)) return error.BindingChanged;
        const text = edit.text.peek();
        if (text.len != 0 and !std.mem.eql(u8, text, edit.original.peek())) {
            const draft = if (self.prompt.peek().len == 0) try self.allocator.dupe(u8, text) else try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ self.prompt.peek(), text });
            defer self.allocator.free(draft);
            self.prompt.set(draft);
            self.promptChanged(self.prompt.peek());
            self.setFeedback("未保存的排队编辑已保留到原会话草稿，未发送");
        }
        // The edit is over in the model; a mounted view closes its editor at its next update.
        if (self.pending_view) |view| view.finishEdit() else edit.editing = null;
    }
    fn saveConversationPresentation(self: *AiHost, id: u64) !void {
        const shared_host = self.shared_service orelse return;
        const state = (self.assistant_states orelse return).find(id) orelse return;
        const record = shared_host.service.store.find(state.conversation_id) orelse return;
        const displayed = self.display_conversation == id;
        const last_user = if (displayed) self.last_user_text else state.last_user_text;
        const current: ?HistoryMessage = if (last_user) |text| .{
            .user = true,
            .text = text,
            .turn = if (displayed) self.current_turn else state.current_turn,
            .wire_text = if (displayed) self.last_user_wire else state.last_user_wire,
            .attachments = if (displayed) self.last_user_attachments else state.last_user_attachments,
            .images = if (displayed) self.last_user_images else state.last_user_images,
        } else null;
        const history = if (displayed) self.history.items else state.history.items;
        // An unhydrated view must not erase retained historical display data.
        if (history.len == 0 and current == null and record.history.messages.len != 0) return;
        const bytes = try @import("../../../ai/conversation_presentation.zig").capture(self.allocator, history, current, if (displayed) self.controller.stream.cards.items else state.stream.cards.items);
        defer self.allocator.free(bytes);
        const baseline = if (displayed) self.wire_history.usage else state.wire_history.usage;
        try shared_host.service.store.savePresentationWithUsage(state.conversation_id, bytes, baseline);
    }
    pub fn saveDisplayedPresentation(self: *AiHost) !void {
        try self.saveConversationPresentation(self.display_conversation orelse return);
    }

    pub fn persistDisplayedDraft(self: *AiHost) !void {
        const shared_host = self.shared_service orelse return;
        const state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
        if (self.child_identity != null) {
            const record = self.childRecord() orelse return;
            if (!std.mem.eql(u8, record.draft orelse "", self.prompt.peek())) _ = try shared_host.service.store.setChildDraft(record.id, record.draft_revision, self.prompt.peek());
            return;
        }
        if (state.ended or state.closed or !state.selected) return;
        if (shared_host.service.store.find(state.conversation_id)) |record| if (record.ending != null) try self.preservePendingEdit();
        const text = self.prompt.peek();
        const record = shared_host.service.store.find(state.conversation_id) orelse blk: {
            if (text.len == 0 and self.wire_history.messages.len == 0) return;
            const migrated = try shared_host.service.store.migrateWithOrigin(state.conversation_id, state.owner, state.binding_revision, true, self.wire_history.messages, text, self.current_turn.id, state.initial_owner orelse state.owner);
            state.binding_revision = migrated.revision;
            break :blk migrated;
        };
        if (record.binding == null or std.mem.eql(u8, record.draft orelse "", text)) return;
        _ = try shared_host.service.store.setDraft(try shared_host.service.store.fence(record.id), record.draft_revision, text);
    }
    fn flushAttached(raw: *anyopaque) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.attachedView().persistDisplayedDraft();
    }
    fn pumpAttached(raw: *anyopaque) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const app = self.application_host orelse return;
        try flushAttached(raw);
        if (self.attached_runner.?.agent.role == .child and self.parentPermission() != .auto and self.request_permission_mode == .auto) {
            self.request_permission_mode = .confirm;
            self.managerRef().setPermissionMode(.confirm);
            self.tool_bridge.setPermissionMode(.confirm);
        }
        if (self.extension_session) |*session| {
            const active = session.active_server.load(.acquire);
            if (active != 0 and !self.extensionAllowed(session.frozen.servers[active - 1].id, true)) session.revoked.store(true, .release);
        }
        if (self.attached_runner.?.agent.current) |id| {
            const record = self.shared_service.?.service.store.find(id).?;
            if (record.ending == null) {
                const current = self.resourceStamp() catch {
                    const ticket = try self.shared_service.?.service.store.fence(id);
                    try self.shared_service.?.service.endConversation(ticket, @import("../../../host/identity.zig").HostOperationId.generate());
                    self.tool_bridge.pump(app);
                    self.execution_bridge.pump(app);
                    return;
                };
                if (self.resource_stamp) |previous_stamp| if (current != previous_stamp) try self.refreshAttachedEnvironment();
                self.resource_stamp = current;
                self.lifecycle_transition = false;
            }
        }
        // Every conversation's host authority, not only the displayed one's: a background
        // conversation's pending approval is withdrawn when its scope or the agent policy changes
        // (LIFECYCLE.md §5.2). The check reads this execution host and the shared store only.
        if (self.request_host_context) |context| self.validateHostContext(context) catch |err| {
            if (err != error.TransitionPending and !self.committedHandoffPending(context)) {
                self.approvalsRef().stop();
                self.questionsRef().stop();
                self.inventory_approval.stop();
            }
        };
        self.tool_bridge.pump(app);
        self.execution_bridge.pump(app);
        const view = self.attachedView();
        const previous = self.withAttachedView();
        defer view.execution_host = previous;
        try view.consumeLiveOutput();
        try view.consumeStepEvents();
        view.syncApprovalSteps();
        const settling = view.tickTaskFinish();
        // While the model works, a finish card follows the driver's evidence and the bridge (both
        // publish) and the reader's controls (callbacks). Once the model ended, settling waits for
        // resources to be released, which has no single publisher: that is a time.
        if (settling and view.settlingAfterModel()) view.wakeAt(16 * std.time.ns_per_ms);
        view.consumeInputHandoffs();
        try view.flushIdleHostNotices();
        view.publishSettledAiCompletions();
        // Every conversation's pending confirmation, not only the displayed one: a conversation
        // waiting in a background tab notifies under the same rules (idempotent per sequence).
        view.observeApprovalNotification();
    }
    fn attachedReleased(raw: *anyopaque, _: @import("../../../ai/session_runtime.zig").Context) bool {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.attached_runner.?.thread != null) return false;
        const view = self.attachedView();
        if (view.compaction_agent) |agent| if (agent.eql(self.attached_runner.?.agent.id) and view.compaction.job != null) return false;
        // The worker has joined. Keep only the cached Token count for the
        // composer before clear() frees the definitions' strings and schemas.
        self.request_tools = &.{};
        self.request_tools_len = 0;
        self.tool_bridge.clear() catch return false;
        if (self.execution_driver) |driver| if (self.request_host_context) |context| if (driver.taskEvidence(context.task_id)) |fact| if (!fact.input_grants_released or fact.pending_dispatch != 0) return false;
        return true;
    }
    fn disposeReadyAttached(raw: *anyopaque) bool {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.attached_runner.?.context) |context| {
            if (!attachedReleased(raw, context)) return false;
        }
        return self.executionShutdownReady();
    }
    fn releaseAttachedWorker(raw: *anyopaque) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const view = self.attachedView();
        const previous = self.withAttachedView();
        defer view.execution_host = previous;
        if (view.tickTaskFinish()) return error.ResourceCleanupPending;
        view.publishSettledAiCompletions();
        for (self.pending_ai_completions.items) |pending| if (pending != null) return error.ResourceCleanupPending;
        if (!self.executionShutdownReady()) return error.ResourceCleanupPending;
        // Final UI data lives in the conversation store, never in this factory.
        if (self.request_conversation) |id| try view.saveConversationPresentation(id);
        self.request_tools = &.{};
        self.request_tools_len = 0;
        const runner = self.attached_runner;
        const a = self.allocator;
        const shared_host = self.shared_service.?;
        // Accepted follow-up inputs belong to the conversation, including
        // their frozen settings and attachments. Worker teardown must not
        // discard the next queued submission before its capture starts.
        const inputs = self.attached_inputs;
        self.attached_inputs = .empty;
        self.destroyAttachedResources();
        const target = self.wake_target.target.load(.acquire);
        self.* = view.attachedSlot(a, shared_host);
        self.wireWakes();
        self.wake_target.bind(target);
        self.attached_runner = runner;
        self.attached_inputs = inputs;
    }
    fn destroyAttachedResources(self: *AiHost) void {
        if (self.extension_session) |*session| session.deinit();
        self.extension_session = null;
        if (self.recording_access) |*value| value.deinit();
        for (self.lifecycle_controllers.items) |controller| {
            controller.deinitAfterWorker();
            self.allocator.destroy(controller);
        }
        self.lifecycle_controllers.deinit(self.allocator);
        if (self.lifecycle_runtime) |runtime| runtime.journal_owner.release();
        if (self.task_finish) |*finish| finish.deinit();
        self.tool_bridge.deinit();
        self.execution_bridge.deinit();
        self.manager.deinit();
        self.controller.deinit();
        self.tool_results.deinit();
        self.stream_mailbox.deinit();
        self.step_mailbox.deinit();
        self.history_submissions.deinit(self.allocator);
        if (self.request_config) |*value| value.deinit();
        if (self.request_context) |*value| value.deinit(self.allocator);
        if (self.native_binding) |value| self.allocator.destroy(value);
        if (self.native_client) |value| self.allocator.destroy(value);
        if (self.native_context) |value| self.allocator.destroy(value);
        if (self.request_text) |value| self.allocator.free(value);
        for (self.attached_inputs.items) |*input| input.deinit(self.allocator);
        self.attached_inputs.deinit(self.allocator);
        if (self.attached_scope) |value| if (value.inventory) |ids| self.allocator.free(ids);
        if (self.request_attachments) |*value| value.deinit();
        if (self.request_images) |*value| value.deinit();
        self.request_image_refs.deinit(self.allocator);
    }
    fn destroyAttached(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.backend_owner) |view| if (view.execution_host == self) {
            view.execution_host = null;
        };
        self.destroyAttachedResources();
        self.allocator.destroy(self);
    }

    fn submit(self: *AiHost, text: []const u8) void {
        self.submitAttached(text, null) catch |err| self.refresh(@errorName(err));
    }
    fn queueAction(raw: *anyopaque, ticket: @import("../approvals/view/ai_pending_view.zig").Ticket, action: @import("../approvals/view/ai_pending_view.zig").Action, text: []const u8) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.pending_action != null) return error.CommandPending;
        self.pending_action = .{ .ticket = ticket, .action = action, .text = if (action == .save) try self.allocator.dupe(u8, text) else null };
        self.wake();
    }
    fn processQueueAction(self: *AiHost) !void {
        const action = self.pending_action orelse return;
        self.pending_action = null;
        defer if (action.text) |text| self.allocator.free(text);
        const shared_host = self.shared_service orelse return error.ContextUnavailable;
        const receipt = action.ticket.receipt;
        const state = self.assistant_states.?.find(self.display_conversation orelse return error.BindingChanged) orelse return error.BindingChanged;
        if (!state.conversation_id.eql(receipt.fence.conversation)) return error.BindingChanged;
        const current = try shared_host.service.store.fence(state.conversation_id);
        const record = try shared_host.service.store.validate(current);
        if (action.action == .inspect) {
            try self.showConversationHistory(state.id);
            return;
        }
        if (action.action == .copy_text) {
            record.inbox.lock();
            const entry = record.inbox.findLocked(receipt.id) orelse {
                record.inbox.unlock();
                return error.SubmissionNotFound;
            };
            const source_text = if (self.execution().attachedInput(receipt.id)) |frozen| frozen.text else |_| entry.payload.messages[0].content;
            const body = self.allocator.dupe(u8, source_text) catch |err| {
                record.inbox.unlock();
                return err;
            };
            record.inbox.unlock();
            defer self.allocator.free(body);
            const draft = if (self.prompt.peek().len == 0) try self.allocator.dupe(u8, body) else try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ self.prompt.peek(), body });
            defer self.allocator.free(draft);
            self.prompt.set(draft);
            self.promptChanged(self.prompt.peek());
            self.focusComposer();
            return;
        }
        if (record.ending != null or !record.inbox.admission) return error.ConversationEnding;
        if (action.action != .remove and action.action != .continue_queue and !current.eql(receipt.fence)) return error.BindingChanged;
        const runner = self.execution().attached_runner orelse return error.AgentNotFound;
        if (!runner.agent.id.eql(receipt.fence.agent)) return error.BindingChanged;
        record.inbox.lock();
        const version = record.inbox.queue_revision;
        record.inbox.unlock();
        if (version != action.ticket.queue_revision) return error.QueueChanged;
        switch (action.action) {
            .save => {
                const backend = self.execution();
                const frozen = try backend.attachedInput(receipt.id);
                const text = try backend.allocator.dupe(u8, action.text.?);
                errdefer backend.allocator.free(text);
                const wire = try ai_attachment_request.compose(backend.allocator, text, &frozen.attachments, @import("../../../ai/provider_http.zig").max_request_bytes);
                errdefer backend.allocator.free(wire);
                const allowed = try self.captureCurrentScope();
                defer self.allocator.free(allowed.inventory.?);
                try self.validateAttachmentScope(allowed, &frozen.attachments);
                var images: [ai_images.max_count]ai_images.ContentRef = undefined;
                for (frozen.images.items, 0..) |item, i| images[i] = item.reference;
                _ = try record.inbox.edit(receipt.id, receipt.revision, .{ .content = wire, .images = images[0..frozen.images.items.len] });
                backend.allocator.free(frozen.text);
                backend.allocator.free(frozen.wire);
                frozen.text = text;
                frozen.wire = wire;
                if (self.pending_view) |view| view.finishEdit();
            },
            .remove => {
                try record.inbox.cancelQueued(receipt.id, receipt.revision);
                if (self.pending_view) |view| view.scrollToTop();
            },
            .now => {
                _ = try shared_host.service.sendNow(receipt.fence, receipt.id, receipt.revision);
            },
            .continue_queue => try shared_host.service.continueQueue(current),
            .copy_text, .inspect => unreachable,
            .up, .down => {
                var ids: std.ArrayList(@import("../../../host/identity.zig").SubmissionId) = .empty;
                defer ids.deinit(self.allocator);
                var count: usize = 0;
                var selected: ?usize = null;
                record.inbox.lock();
                {
                    defer record.inbox.unlock();
                    for (record.inbox.entries.items) |entry| if (entry.receipt.delivery == .queued and entry.receipt.pause == null and entry.receipt.fence.eql(receipt.fence)) {
                        if (entry.receipt.id.eql(receipt.id)) selected = count;
                        try ids.append(self.allocator, entry.receipt.id);
                        count += 1;
                    };
                }
                const index = selected orelse return error.SubmissionNotReady;
                const other = if (action.action == .up) index -| 1 else @min(index + 1, count - 1);
                std.mem.swap(@import("../../../host/identity.zig").SubmissionId, &ids.items[index], &ids.items[other]);
                try record.inbox.reorder(version, ids.items);
                if (self.pending_view) |view| view.scrollToTop();
            },
        }
    }
    fn updatePending(self: *AiHost) !void {
        self.refreshSendHint();
        const view = self.pending_view orelse return;
        const shared_host = self.shared_service orelse return;
        const state = (self.assistant_states orelse return).find(self.display_conversation orelse return) orelse return;
        const record = shared_host.service.store.find(state.conversation_id);
        var items: std.ArrayList(@import("../approvals/view/ai_pending_view.zig").Item) = .empty;
        defer items.deinit(self.allocator);
        var revision: u64 = 0;
        var continuing = false;
        var hash = std.hash.Wyhash.init(0);
        if (record) |value| {
            value.inbox.lock();
            defer value.inbox.unlock();
            revision = value.inbox.queue_revision;
            for (value.inbox.entries.items) |entry| {
                if (entry.receipt.route == .steer) {
                    std.hash.autoHash(&hash, entry.receipt);
                    if (entry.receipt.delivery == .accepted and entry.receipt.pause == null) std.hash.autoHash(&hash, value.inbox.work_phase);
                }
                if (entry.receipt.archived or @import("../../../ai/session_input.zig").terminal(entry.receipt.delivery)) continue;
                if (entry.receipt.route == .steer) continue;
                var text = entry.payload.messages[0].content;
                var attachments = entry.payload.messages[0].images.len;
                if (self.execution().attachedInput(entry.receipt.id)) |frozen| {
                    text = frozen.text;
                    attachments += frozen.attachments.items.len;
                } else |_| {}
                try items.append(self.allocator, .{ .receipt = entry.receipt, .text = text, .attachments = attachments, .mutable = value.ending == null and value.inbox.admission });
                continuing = continuing or (value.ending == null and value.inbox.admission and entry.receipt.delivery == .queued and entry.receipt.pause != null and entry.receipt.fence.eql(value.inbox.fence));
            }
        }
        if (view.edit.editing) |edit| {
            var still_queued = false;
            for (items.items) |item| if (item.receipt.id.eql(edit.receipt.id) and item.receipt.delivery == .queued and item.mutable) {
                still_queued = true;
                break;
            };
            if (!still_queued) try self.preservePendingEdit();
        }
        const followup_hash = hash.final();
        if (self.followup_hash != followup_hash) {
            self.followup_hash = followup_hash;
            self.conversation_dirty = true;
        }
        _ = try view.update(items.items, revision, self.cx.viewport.height < 600, continuing);
    }
    fn captureAttachedInput(self: *AiHost, id: @import("../../../host/identity.zig").SubmissionId, submitted: []const u8, bundle: *const ai_attachments.Bundle, image_bundle: *const ai_images.Bundle, config: @import("../../../config/config.zig").Config, controls: *const @import("../../../ai/assistant_store.zig").Controls) !AttachedInput {
        const text = try self.allocator.dupe(u8, submitted);
        errdefer self.allocator.free(text);
        const wire = try ai_attachment_request.compose(self.allocator, submitted, bundle, @import("../../../ai/provider_http.zig").max_request_bytes);
        errdefer self.allocator.free(wire);
        var owned = try @import("../../../config/runtime_config.zig").Snapshot.init(self.allocator, config);
        errdefer owned.deinit();
        var attachments = try bundle.retain();
        errdefer attachments.deinit();
        var images = try image_bundle.retain();
        errdefer images.deinit();
        var selected = controls.*;
        selected.model = null;
        try selected.setModel(self.allocator, controls.model);
        errdefer selected.deinit(self.allocator);
        return .{ .id = id, .text = text, .wire = wire, .config = owned, .controls = selected, .attachments = attachments, .images = images };
    }
    fn submitAttached(self: *AiHost, text: []const u8, mode: ?@import("../../../ai/session_input.zig").Mode) !void {
        if (@import("../../../update/admission.zig").blocked()) return;
        if ((self.application_host orelse return error.ContextUnavailable).windowClosePending()) return error.WindowClosing;
        if (self.shared_service) |shared_host| if (shared_host.closing) return error.ApplicationClosing;
        if (self.compaction.job != null) return error.ContextCompactionRunning;
        const submitted = try self.allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
        defer self.allocator.free(submitted);
        const owner = self.currentBinding() orelse return error.MissingAssistantOwner;
        try self.syncOwner();
        const backend = try self.bindAttached(owner);
        const state = self.assistant_states.?.find(self.display_conversation orelse return error.ConversationNotFound).?;
        const shared_host = try self.shared();
        if (shared_host.service.store.find(state.conversation_id) == null) {
            // The displayed legacy history has been moved out of State. Import
            // that exact snapshot, preserving the original conversation ID.
            const record = try shared_host.service.store.migrateWithOrigin(state.conversation_id, state.owner, state.binding_revision, true, self.wire_history.messages, self.prompt.peek(), self.current_turn.id, state.initial_owner orelse state.owner);
            state.binding_revision = record.revision;
        }
        const ticket = try shared_host.service.store.fence(state.conversation_id);
        const attachments = try self.attachmentDraft(owner);
        var bundle = try attachments.freeze();
        defer bundle.deinit();
        const image_draft = try self.imageDraft(owner);
        var image_bundle = try image_draft.freeze();
        defer image_bundle.deinit();
        if (submitted.len == 0 and bundle.items.len == 0 and image_bundle.items.len == 0) return;
        const controls = try self.selectedControls();
        const runtime = self.runtime_config orelse return error.ContextUnavailable;
        var effective = runtime.value;
        effective.ai = self.effectiveAi();
        var input = try backend.captureAttachedInput(@import("../../../host/identity.zig").SubmissionId.generate(), submitted, &bundle, &image_bundle, effective, controls);
        var input_owned = true;
        errdefer if (input_owned) input.deinit(backend.allocator);
        const selected = try ai_provider_config.fromSettingsSelection(input.config.?.value.ai, input.controls.model);
        if (input.controls.effort) |effort| try ai_provider_config.validateEffort(input.config.?.value.ai, input.controls.model, effort);
        var refs: [ai_images.max_count]ai_images.ContentRef = undefined;
        for (image_bundle.items, 0..) |item, i| refs[i] = item.reference;
        const message: ai_provider.Message = .{ .content = input.wire, .images = refs[0..image_bundle.items.len] };
        try ai_attachment_request.checkContext(selected.chatRequest(.{ .model = selected.model, .system = "", .messages = &.{message} }), selected.context_window);
        try backend.attached_inputs.append(backend.allocator, input);
        input_owned = false;
        const id = input.id;
        const receipt = shared_host.service.submit(ticket, id, message, mode orelse effective.ai.follow_up_mode) catch |err| {
            var rejected = backend.attached_inputs.pop().?;
            rejected.deinit(backend.allocator);
            return err;
        };
        _ = receipt;
        self.prompt.set("");
        _ = try attachments.consumeSent(&bundle);
        _ = try image_draft.consumeSent(&image_bundle);
        if (self.attachments_view) |view| try view.update(attachments);
        if (self.images_view) |view| try view.update(image_draft);
        self.refresh("AI 请求中…");
    }

    /// Stop is deliberately cooperative: the provider transport checks the
    /// shared token before requests, while reading response frames and while
    /// retry backoff sleeps.  The UI thread never blocks waiting for network
    /// I/O; PollHook joins only after the worker publishes a terminal state.
    fn decideTool(ctx: *anyopaque, sequence: u64, hash: [32]u8, approved: bool) !void {
        const self: *AiHost = @ptrCast(@alignCast(ctx));
        if (self.execution().thread_state.load(.acquire) != 1) return error.StaleApproval;
        const owner = self.display_owner orelse return error.StaleApproval;
        const request = if (self.execution().request_host_context) |context| context.binding else self.execution().request_owner orelse return error.StaleApproval;
        if (!owner.eql(request) or !self.requestDisplayed()) return error.StaleApproval;
        try self.execution().tool_bridge.decide(sequence, hash, approved);
        self.wake();
    }

    fn stop(self: *AiHost) void {
        if (self.execution().thread_state.load(.acquire) != 1) return;
        if (!self.requestDisplayed()) return;
        if (self.shared_service) |shared_host| if (self.execution().attached_runner) |runner| if (runner.agent.current) |id| {
            shared_host.service.stop(shared_host.service.store.fence(id) catch return) catch |err| {
                self.setFeedback(@errorName(err));
                return;
            };
            self.refresh("AI 停止中…");
            return;
        };
        self.cancelRef().cancel();
        self.approvalsRef().stop();
        self.questionsRef().stop();
        self.execution().inventory_approval.stop();
        if (self.execution().request_host_context) |context| {
            if (self.application_host) |app| app.cancelOwnedTask(context.task_id);
            if (self.execution().execution_driver) |driver| driver.stopTask(context) catch {};
        }
        self.refresh("AI 停止中…");
    }

    /// Runs only on the same worker that owns the active Loop. The API-2
    /// reader has already revalidated the session and image-sharing approval.
    fn findRetainedImage(raw: *anyopaque, owner: @import("../../../host/identity.zig").SessionHandle, reference: []const u8) !ai_images.ContentRef {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const run = self.managerRef().tool_run orelse return error.ImageReferenceNotFound;
        return @import("../../../ai/image_offload.zig").find(run.messages.items, reference, owner);
    }

    /// UI-thread: consumes a finished worker run. Called from the poll hook
    /// only (thread_state release→acquire already ordered the card data).
    pub fn streamReset(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.execution().stream_mailbox.reset();
        self.execution().step_mailbox.push(.{ .kind = .reset, .phase = .assembling, .at_ms = 0 }) catch {};
    }
    pub fn streamRoundStart(raw: *anyopaque) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.execution().step_mailbox.push(.{ .kind = .round_start, .phase = .assembling, .at_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) }) catch {};
    }

    pub fn streamContextUsage(raw: *anyopaque, turn: u64, snapshot: @import("../../../ai/live_context_usage.zig").Snapshot) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.execution().context_usage_mailbox.publish(turn, snapshot);
    }

    pub fn streamInputConsumed(raw: *anyopaque, id: @import("../../../host/identity.zig").SubmissionId, text: []const u8) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.execution().step_mailbox.push(.{ .kind = .input, .submission = id, .detail = text, .phase = .succeeded, .at_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) });
    }
    pub fn streamToolRejected(raw: *anyopaque, call: ai_provider.ToolCall, detail: []const u8) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.execution().step_mailbox.push(.{ .call_id = call.id, .name = call.name, .detail = detail, .phase = if (std.mem.indexOf(u8, detail, "not_dispatched_due_to_new_input") != null) .skipped else if (self.cancelRef().isCancelled()) .cancelled else .failed, .at_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) });
    }

    pub fn streamDelta(raw: *anyopaque, delta: ai_provider.Delta) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const at_ms: u64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        if (delta == .text) {
            try self.execution().stream_mailbox.append(delta.text);
            try self.execution().step_mailbox.push(.{ .kind = .text, .detail = delta.text, .phase = .assembling, .at_ms = at_ms });
        }
        if (delta == .thinking) {
            try self.execution().stream_mailbox.appendThinking(delta.thinking);
            try self.execution().step_mailbox.push(.{ .kind = .thinking, .detail = delta.thinking, .phase = .assembling, .at_ms = at_ms });
        }
        if (delta == .tool_plan) {
            const plan = delta.tool_plan;
            const id = plan.call_id orelse return;
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, plan.arguments, .{}) catch null;
            defer if (parsed) |json| json.deinit();
            const command = if (parsed) |json| blk: {
                if (json.value == .object) for ([_][]const u8{ "command", "path" }) |key| if (json.value.object.get(key)) |value| if (value == .string) break :blk value.string;
                break :blk plan.arguments;
            } else plan.arguments;
            try self.execution().step_mailbox.push(.{ .kind = .plan, .call_id = id, .name = plan.name orelse "工具调用", .command = command, .detail = plan.arguments, .phase = .assembling, .at_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) });
        }
    }

    fn consumeLiveOutput(self: *AiHost) !void {
        const batch = (try self.execution().stream_mailbox.drain()) orelse return;
        defer self.allocator.free(batch.bytes);
        defer self.allocator.free(batch.thinking);
        const same_owner = self.requestDisplayed();
        const stream = if (same_owner) &self.controller.stream else if (self.assistant_states) |store| &(store.find(self.execution().request_conversation orelse return) orelse return).stream else return;
        if (batch.reset) {
            if (self.execution().answer_only) {
                // Only reset the current attempt, retaining earlier partials.
                var prefix = @import("../../../ai/card_stream.zig").Stream.init(self.allocator);
                defer prefix.deinit();
                for (stream.cards.items[0..@min(self.execution().retry_prefix_count, stream.count())]) |card| _ = try prefix.append(card);
                stream.clearRetainingCapacity();
                for (prefix.cards.items) |card| _ = try stream.append(card);
            } else stream.clearRetainingCapacity();
            if (same_owner) self.streaming_label = null;
        }
        if (batch.bytes.len > 0) {
            const index = if (self.execution().answer_only) self.execution().retry_prefix_count else 0;
            if (stream.cards.items.len <= index) {
                _ = try stream.append(.{ .text = batch.bytes });
            } else try stream.appendText(index, batch.bytes);
        }
        if (same_owner) {
            // New output for the displayed conversation (the “新消息” hint counts it).
            if (batch.bytes.len > 0 or batch.thinking.len > 0) self.live_output_serial +%= 1;
            if (self.live_timeline != null and !self.execution().answer_only) self.invalidateTimeline() else if (batch.bytes.len > 0 and batch.thinking.len == 0 and !batch.reset and self.live_card != null and !self.execution().answer_only) self.live_dirty = true else self.conversation_dirty = true;
            self.wake();
        }
    }

    fn refreshLiveMarkdown(self: *AiHost) !bool {
        if (!self.live_dirty) return false;
        self.live_dirty = false;
        const card = self.live_card orelse return false;
        const scope = self.conversation_scope orelse return false;
        const stream = &self.controller.stream;
        if (stream.cards.items.len == 0 or stream.cards.items[0] != .text) return false;
        if (self.cx.pressed_node) |node| if (node.isDescendantOf(card)) self.cx.cancelPointerInteractions(.explicit);
        if (self.cx.focus_manager.current_focus) |node| if (node.isDescendantOf(card)) self.cx.clearFocus();
        if (self.live_scope) |previous| previous.dispose();
        self.live_scope = null;
        while (card.children.items.len > 0) {
            const child = card.children.items[card.children.items.len - 1];
            self.cx.detachChild(card, child);
            self.cx.destroyDetached(child);
        }
        self.live_scope = try scope.childScope();
        const body = try self.markdownIn(self.live_scope.?, stream.cards.items[0].text, &self.current_turn);
        body.meta.ownership.meta.test_id = self.id_space.id("ai.response");
        try card.appendChild(self.allocator, body);
        return true;
    }

    fn consumeStepEvents(self: *AiHost) !void {
        const events = try self.execution().step_mailbox.drain();
        defer self.allocator.free(events);
        defer for (events) |event| event.deinit(self.allocator);
        if (events.len == 0) return;
        const same = self.requestDisplayed();
        const turn = if (same) &self.current_turn else &(self.assistant_states.?.find(self.execution().request_conversation orelse return) orelse return).current_turn;
        for (events) |event| {
            try turn.applyEvent(self.allocator, event);
        }
        try @import("../../../ai/step_groups.zig").sync(self.allocator, turn, self.effectiveAi().step_display == .expanded);
        if (same) {
            self.invalidateTimeline();
            self.wake();
        }
    }

    fn syncApprovalSteps(self: *AiHost) void {
        if (!self.requestDisplayed()) return;
        const host_pending = self.approvalsRef().snapshot();
        const tool_pending = self.execution().tool_bridge.pendingApproval();
        const question_pending = self.questionsRef().snapshot();
        for (self.current_turn.steps.items) |*step| {
            const waiting = if (host_pending) |pending| std.mem.eql(u8, pending.call.text(), step.call_id) else if (tool_pending) |pending| std.mem.eql(u8, pending.call_id, step.call_id) else if (question_pending) |pending| std.mem.eql(u8, pending.call.text(), step.call_id) else false;
            if (waiting) {
                if (step.phase != .approval) {
                    if (step.approval_started_ms == null) step.approval_started_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
                    step.phase = .approval;
                    self.invalidateTimeline();
                }
            }
        }
    }

    fn consumeResult(self: *AiHost) void {
        if (self.execution().request_text) |owned| {
            self.allocator.free(owned);
            self.execution().request_text = null;
        }
        self.clearRequestHistory();
        self.syncOwner() catch return;
        const same_owner = self.requestDisplayed();
        const stream = if (same_owner) &self.controller.stream else &(self.assistant_states.?.find(self.execution().request_conversation orelse return) orelse return).stream;
        stream.clearRetainingCapacity();
        for (self.managerRef().cards.cards.items) |card| {
            _ = stream.append(card) catch break;
        }
        if (same_owner) self.refresh("AI response");
    }

    fn retainToolResults(self: *AiHost) !bool {
        const run = self.managerRef().tool_run orelse return false;
        if (run.turn_id != self.managerRef().turn_id) return false;
        const sources = try self.execution().tool_bridge.resultSources(self.allocator);
        defer self.allocator.free(sources);
        if (self.requestDisplayed()) {
            const changed = try self.tool_results.capture(run, sources);
            const conversation = if (self.execution().request_host_context) |context| context.conversation_id else if (self.assistant_states) |states| (states.find(self.execution().request_conversation orelse return changed) orelse return changed).conversation_id else return changed;
            for (self.tool_results.records.items) |record| if (record.turn_id == run.turn_id and record.conversation_id == null) {
                record.conversation_id = conversation;
            };
            return changed;
        }
        const store = if (self.assistant_states) |v| v else return false;
        const state = store.find(self.execution().request_conversation orelse return false) orelse return false;
        if (state.tool_results == null) state.tool_results = @import("../../../ai/tool_results.zig").Store.init(self.allocator);
        const changed = try state.tool_results.?.capture(run, sources);
        for (state.tool_results.?.records.items) |record| if (record.turn_id == run.turn_id and record.conversation_id == null) {
            record.conversation_id = state.conversation_id;
        };
        return changed;
    }

    fn queryHost(raw: *anyopaque, invocation: @import("../../../ai/host_tools.zig").Invocation, allocator: std.mem.Allocator) !@import("../../../ai/host_tools.zig").Result {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.validateHostContext(invocation.context);
        const store = if (self.assistant_states) |value| value else return error.ContextUnavailable;
        const state = store.findConversation(invocation.context.conversation_id) orelse return error.ScopeChanged;
        if (state.closed or !state.owner.eql(invocation.context.binding) or state.binding_revision != invocation.context.binding_revision) return error.ScopeChanged;
        const app = self.application_host orelse return error.ContextUnavailable;
        if (app.workspace.app_config.agentPolicyRevision() != self.execution().request_policy_revision) return error.ScopeChanged;
        const controller = lookupLifecycleTask(self, invocation.context.conversation_id, invocation.context.task_id) orelse return error.ScopeChanged;
        if (std.mem.eql(u8, invocation.tool_id, @import("../../../ai/builtin_tools.zig").id)) {
            const request = try @import("../../../ai/builtin_tools.zig").parse(invocation.arguments);
            for (self.execution().tool_bridge.children.items) |child| {
                const reference = try @import("../../../ai/host_queries.zig").sessionRef(allocator, invocation.context, child.owner);
                defer allocator.free(reference);
                if (!std.mem.eql(u8, reference, request.reference)) continue;
                if (!controller.inBinding(child.owner)) return error.TargetNotAuthorized;
                const legacy = app.legacyForHandle(child.owner) orelse return error.StaleSession;
                const tab = app.workspace.sessionTab(legacy) orelse return error.StaleSession;
                if (tab.closing or tab.terminal == null) return error.ToolNotAvailable;
                const terminal_view = &tab.terminal.?;
                if (terminal_view.commandRecordOwner() == null or !terminal_view.commandRecordOwner().?.eql(child.owner)) return error.StaleSession;
                var help_buffer: [4096]u8 = undefined;
                const output = if (std.mem.eql(u8, request.command, "@dots")) @import("../../../shared/base/donation_qr.zig").hint else try @import("../../terminal/model/builtin_dispatch.zig").formatHelp(allocator, &help_buffer);
                // Allocate the receipt before changing the document.
                var result = try @import("../../../ai/builtin_tools.zig").result(invocation, allocator, request.command);
                errdefer result.deinit(allocator);
                const record = terminal_view.beginCommandRecord(request.command) orelse return error.WorkerBusy;
                if (!terminal_view.finishCommandRecord(child.owner, record, .success, output)) return error.CommandDisplayFailed;
                return result;
            }
            return error.TargetNotAuthorized;
        }
        if (@import("../../../ai/host_tool_catalog.zig").isNative(invocation.tool_id)) return self.invokeTabContext(app, invocation, allocator);
        if (@import("../../../ai/host_catalog.zig").supports(invocation.tool_id) and !@import("../../../ai/host_catalog.zig").isMutation(invocation.tool_id)) return @import("../tools/host/ai_host_catalog_controller.zig").execute(app, invocation, allocator);
        if (@import("../../../ai/batch_output.zig").supports(invocation.tool_id)) return self.execution().tool_bridge.readBatchOutput(app, invocation, allocator);
        if (@import("../../../ai/host_terminal_queries.zig").supports(invocation.tool_id)) {
            const handles = try allocator.alloc(@import("../../../host/identity.zig").SessionHandle, self.execution().tool_bridge.children.items.len);
            defer allocator.free(handles);
            for (self.execution().tool_bridge.children.items, 0..) |child, index| handles[index] = child.owner;
            return @import("../tools/host/ai_host_terminal_queries.zig").execute(app, self.roster, .{ .captured_scope = self.execution().tool_bridge.captured_scope orelse return error.ScopeChanged, .captured_handles = handles[0..self.execution().tool_bridge.children.items.len], .command_provider = if (self.execution().execution_driver) |driver| @import("../tools/host/ai_host_terminal_queries.zig").CommandProvider.from(@import("../../../ai/host_execution_driver.zig").Driver, driver) else null }, self.execution().host_cursor_key, invocation, allocator);
        }
        return @import("../tools/host/ai_host_queries.zig").execute(app, self.roster, state.initial_owner orelse state.owner, .{ .execution_policy = controller.execution_policy, .permission_mode = self.execution().request_permission_mode, .host_contributions = self.execution().tool_bridge.host_binding.?.contributions }, self.execution().host_cursor_key, invocation, allocator);
    }

    /// `host.tab_context`（M11）：第一个直接按 `ToolDef` 写的工具，走统一流水线
    /// （解析 → schema → 作用域 → 审批 → handler → 规范化 → 截断 → 返回）。作用域是本次对话冻结的
    /// tab 作用域；`card_refs` 里不属于本 tab 的引用由第 3 步拒绝（`CardNotInTab`）。
    fn invokeTabContext(self: *AiHost, app: *application_host_mod.ApplicationHost, invocation: @import("../../../ai/host_tools.zig").Invocation, allocator: std.mem.Allocator) !@import("../../../ai/host_tools.zig").Result {
        const Tool = @import("../tools/host/ai_tab_context.zig").Tool(application_host_mod.ApplicationHost, @import("../../workspace/model/group_model.zig").Roster);
        const pipeline = @import("../../../ai/tool_pipeline.zig");
        const captured = self.execution().tool_bridge.captured_scope orelse return error.ScopeChanged;
        if (!captured.owner.eql(invocation.context.binding)) return error.ScopeChanged;
        const window: u32 = if (self.execution().native_binding) |binding| binding.config.context_window else 200_000;
        var env: Tool.E = .{ .app = app, .roster = self.roster, .context = invocation.context, .scope = captured, .context_window = window, .file_host = if (self.file_application) |files| @ptrCast(files) else null };
        const def = Tool.definition();
        // 与注册表里登记的契约逐项相同（名称、描述、schema、审批、预算）。
        if (app.sessions.registry.tools.find(def.name)) |entry| if (!@import("../../../ai/tool_def.zig").ToolDef.sameContract(entry.def, def)) return error.ToolDefinitionConflict;
        const Scope = struct {
            fn check(raw: *anyopaque, _: *const @import("../../../ai/tool_def.zig").ToolDef, arguments: std.json.Value) anyerror!?[]const u8 {
                const value: *Tool.E = @ptrCast(@alignCast(raw));
                try Tool.validateScope(value, arguments, std.heap.page_allocator);
                return null;
            }
            fn hint(raw: *anyopaque) ?[]const u8 {
                const value: *Tool.E = @ptrCast(@alignCast(raw));
                return value.diagnostic();
            }
        };
        var response = try pipeline.invoke(allocator, &def, invocation.arguments_json, .{ .context = &env, .scope = Scope.check, .scope_hint = Scope.hint, .policy = self.execution().tool_bridge.permissionPolicy() });
        defer response.deinit(allocator);
        // 规范化后的成功结果是 `{status, content:[{type:"structured", text}], truncated}`；给模型的是其中的结构化概览本身。
        const text = blk: {
            if (response.status != .succeeded) break :blk try allocator.dupe(u8, response.body);
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response.body, .{});
            defer parsed.deinit();
            const content = parsed.value.object.get("content") orelse break :blk try allocator.dupe(u8, response.body);
            if (content != .array or content.array.items.len != 1) break :blk try allocator.dupe(u8, response.body);
            break :blk try allocator.dupe(u8, content.array.items[0].object.get("text").?.string);
        };
        errdefer allocator.free(text);
        const blocks = try allocator.alloc(@import("../../../ai/host_tools.zig").Block, 1);
        blocks[0] = .{ .structured = text };
        return .{ .status = response.status, .blocks = blocks, .receipt = .{ .conversation_id = invocation.context.conversation_id, .task_id = invocation.context.task_id, .operation_id = invocation.operation_id, .binding_revision = invocation.context.binding_revision } };
    }

    fn controllerScheduler(raw: *anyopaque, context: *anyopaque, callback: *const fn (*anyopaque) anyerror!void, cancel: ?*ai_provider.CancelToken) !void {
        const bridge: *@import("../tools/host/ai_tools.zig").Bridge = @ptrCast(@alignCast(raw));
        return bridge.callController(context, callback, cancel);
    }
    fn lifecycleCall(raw: *anyopaque, call: *@import("../../../ai/lifecycle_runtime.zig").Call) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const controller = self.execution().lifecycle_controller orelse return error.ToolNotAvailable;
        const handle = controller.handle();
        return handle.invoke(handle.context, call);
    }
    fn prepareLifecycleTask(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) !void {
        const Controller = @import("../tools/host/ai_lifecycle_controller.zig").Controller;
        const controller = try self.allocator.create(Controller);
        errdefer self.allocator.destroy(controller);
        controller.* = try Controller.init(.{ .allocator = self.allocator, .app = self.application_host orelse return error.ContextUnavailable, .roster = self.roster orelse return error.ContextUnavailable, .store = self.assistant_states.?, .bridge = &self.execution().tool_bridge, .authority = context, .execution_policy = self.execution().request_execution_policy, .notice_revision = self.execution().host_notice_revision, .callbacks = .{ .context = self, .on_handoff = handoffCommitted, .on_membership_changed = membershipCommitted } });
        errdefer controller.deinitAfterWorker();
        try self.execution().lifecycle_controllers.append(self.allocator, controller);
        self.execution().lifecycle_controller = controller;
        if (self.execution().execution_backend == null) self.execution().execution_backend = try @import("../tools/host/ai_execution_backend.zig").Context.init(.{ .app = self.application_host.?, .roster = self.roster.?, .store = self.assistant_states.?, .lookup_context = self, .lookup_task = lookupLifecycleTask, .approval = self.approvalsRef(), .secret_host = .{ .context = self, .request = requestHostSecret } });
        try self.execution().execution_backend.?.captureTask(controller);
        if (self.execution().execution_driver == null) {
            // A restored conversation's new worker starts with the receipts of its own earlier,
            // released worker (read-only; see `retainSettledExecutions`).
            var seed: std.ArrayList(@import("../../../ai/host_execution.zig").Retained) = .empty;
            defer seed.deinit(std.heap.c_allocator);
            for (self.attachedView().retained_executions.items) |item| if (item.receipt.context.conversation_id.eql(context.conversation_id)) try seed.append(std.heap.c_allocator, item.receipt);
            self.execution().execution_driver = try @import("../../../ai/host_execution_driver.zig").Driver.startAdopting(std.heap.c_allocator, self.execution().lifecycle_runtime.?.journal_owner, .{ .context = &self.execution().execution_bridge, .call = controllerScheduler }, self.execution().execution_backend.?.backend(), seed.items);
            self.execution().execution_driver.?.ui_wake = &self.execution().wake_target;
            try self.adoptRetainedExecutions(context.conversation_id);
        }
        if (self.execution().task_finish == null) self.execution().task_finish = @import("../cards/view/ai_task_finish.zig").Controller.init(self.allocator);
        try self.execution().task_finish.?.registerTask(context);
    }
    fn lookupLifecycleTask(raw: *anyopaque, conversation: @import("../../../host/identity.zig").ConversationId, task: @import("../../../host/identity.zig").TaskId) ?*@import("../tools/host/ai_lifecycle_controller.zig").Controller {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        for (self.execution().lifecycle_controllers.items) |controller| if (controller.authority.conversation_id.eql(conversation) and controller.authority.task_id.eql(task)) return controller;
        return null;
    }
    fn prepareRecordingAccess(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) !void {
        const app = self.application_host orelse return error.ContextUnavailable;
        if (self.execution().recording_access == null) {
            var archive = self.execution().recording_archive orelse return;
            archive.io = if (self.execution().ai_io) |io| io.io() else archive.io;
            self.execution().recording_access = try @import("../tools/host/ai_recording_query_access.zig").Access.init(self.allocator, archive, context);
        } else try self.execution().recording_access.?.beginQuiescentCapture(context);
        try self.execution().recording_access.?.captureUi(app, self.roster, &self.execution().tool_bridge);
        try self.execution().recording_access.?.captureClosedReceipts(app);
    }
    /// 宿主工具表从统一工具注册表的快照里按本次请求的条件筛出（tool_registry.zig、
    /// host_tool_catalog.select）。快照由组合根随插件注册表一起发布。
    fn prepareHostCatalog(self: *AiHost, app: *application_host_mod.ApplicationHost) void {
        const catalog = @import("../../../ai/host_tool_catalog.zig");
        const target = self.execution();
        const Lifecycle = struct {
            fn available(raw: *anyopaque, id: []const u8) bool {
                const controller: *@import("../tools/host/ai_lifecycle_controller.zig").Controller = @ptrCast(@alignCast(raw));
                return controller.available(id);
            }
        };
        target.host_catalog_len = catalog.select(&app.sessions.registry.tools, .{
            .queries_only = target.tool_bridge.queries_only,
            .child_gateway = if (target.request_host_context) |authority| authority.child_origin == null else false,
            .extension = if (target.extension_session) |session| .{ .skills = session.frozen.skills.len != 0, .servers = session.frozen.servers.len != 0 } else null,
            .execution = target.execution_driver != null,
            .lifecycle = if (target.lifecycle_controller) |controller| .{ .context = controller, .available = Lifecycle.available } else null,
        }, &target.host_catalog);
    }
    fn handoffCommitted(raw: *anyopaque, conversation: @import("../../../host/identity.zig").ConversationId, owner: ai_attachments.Owner, _: u64, notice_revision: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // AI 建组把对话交接给新的组 tab（M10）；组 tab 已经发布，内容按它派生。
        const group = (self.uiOwner().ownerContent(owner) orelse return).group;
        self.execution().lifecycle_transition = true;
        self.execution().request_owner = owner;
        self.execution().request_content_owner = .{ .group = .{ .id = @fromBackingInt(@intCast(group)) } };
        self.execution().host_notice_revision = @max(self.execution().host_notice_revision, notice_revision);
        if (self.assistant_states) |store| if (self.display_conversation) |id| if (store.find(id)) |state| if (state.conversation_id.eql(conversation)) {
            self.display_owner = owner;
        };
        self.execution().tool_bridge.bindingChanged(owner, .{ .group = group });
        self.conversation_dirty = true;
        self.composer_hash = null;
        self.wake();
    }
    fn membershipCommitted(raw: *anyopaque, _: @import("../../../host/identity.zig").ConversationId, group: @import("../../../host/identity.zig").GroupOwner, _: u64, notice_revision: u64) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        self.execution().lifecycle_transition = true;
        self.execution().host_notice_revision = @max(self.execution().host_notice_revision, notice_revision);
        const workspace = self.uiOwner().workspace orelse return;
        const tab = workspace.groupTabId(@intCast(@backingInt(group.id))) orelse return;
        self.execution().tool_bridge.bindingChanged(.{ .tab = @backingInt(tab) }, .{ .group = @backingInt(group.id) });
        self.conversation_dirty = true;
        self.wake();
    }
    /// Deliver switch candidates at the existing tool-round boundary. No
    /// input is injected by detection, and no unsolicited AI task is created.
    fn shellSwitchNotices(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context, allocator: std.mem.Allocator) ![]u8 {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const Notice = struct { session_ref: []const u8, sequence: u64, pending: bool, kind: []const u8, command: []const u8, shell_id: ?[]const u8, shell_revision: u64, prompt_ready: ?bool };
        var notices: std.ArrayList(Notice) = .empty;
        const app = self.application_host orelse return allocator.dupe(u8, "[]");
        const controller = lookupLifecycleTask(self, context.conversation_id, context.task_id) orelse return allocator.dupe(u8, "[]");
        for (app.workspace.tabs.items) |tab| {
            if (tab.content_owner != .session or !controller.inBinding(tab.content_owner.session)) continue;
            const runtime = tab.runtime orelse continue;
            const service = runtime.terminalService() catch continue;
            const snapshot = service.executionSnapshot() catch continue;
            if (snapshot.shell_switch.sequence == 0) continue;
            try notices.append(a, .{ .session_ref = try @import("../../../ai/host_queries.zig").sessionRef(a, context, tab.content_owner.session), .sequence = snapshot.shell_switch.sequence, .pending = snapshot.shell_switch.pending, .kind = @tagName(snapshot.shell_switch.kind), .command = try a.dupe(u8, snapshot.shell_switch.text()), .shell_id = if (snapshot.shell.id) |id| try a.dupe(u8, &id) else null, .shell_revision = snapshot.shell.revision, .prompt_ready = snapshot.shell.prompt_ready });
        }
        return std.json.Stringify.valueAlloc(allocator, notices.items, .{});
    }
    fn refreshHostAuthority(raw: *anyopaque, bridge: *@import("../tools/host/ai_tools.zig").Bridge, previous: *const @import("../../../ai/plugin_tools.zig").RequestTable, allocator: std.mem.Allocator, cancel: ?*ai_provider.CancelToken) !?@import("../../../ai/tool_loop.zig").AuthorityRefresh {
        const Refresh = struct {
            host: *AiHost,
            bridge: *@import("../tools/host/ai_tools.zig").Bridge,
            previous: @import("../../../ai/host_tools.zig").Context,
            allocator: std.mem.Allocator,
            result: ?@import("../../../ai/tool_loop.zig").AuthorityRefresh = null,
            fn run(context: *anyopaque) !void {
                const value: *@This() = @ptrCast(@alignCast(context));
                const self = value.host;
                const app = self.application_host orelse return error.ContextUnavailable;
                const binding_context = (value.bridge.host_binding orelse return error.ScopeChanged).context;
                if (!binding_context.eql(value.previous)) return error.ScopeChanged;
                if (app.workspace.app_config.agentPolicyRevision() != self.execution().request_policy_revision) return error.ScopeChanged;
                const store = if (self.assistant_states) |items| items else return error.ConversationNotFound;
                const state = store.findConversation(value.previous.conversation_id) orelse return error.ConversationNotFound;
                if (state.closed or state.ended) return error.ScopeChanged;
                const shell_notices = try self.shellSwitchNotices(value.previous, value.allocator);
                defer value.allocator.free(shell_notices);
                const shell_hash = @import("../../../host/terminal_execution.zig").digest(shell_notices);
                const shell_changed = (shell_notices.len > 2 or self.execution().shell_notice_hash != null) and (self.execution().shell_notice_hash == null or !std.mem.eql(u8, &self.execution().shell_notice_hash.?, &shell_hash));
                var changed = !state.owner.eql(value.previous.binding) or state.binding_revision != value.previous.binding_revision or self.execution().host_notice_revision > self.execution().authority_notice_revision;
                changed = changed or shell_changed or value.bridge.capabilityFingerprint(app) != value.bridge.capability_fingerprint;
                // 绑定 tab 的内容按当前工作区派生（M10）；组 tab 的会话组没了等同于组被移除。
                const held = self.ownerContent(state.owner) orelse return if (value.previous.contentOf() == .group) error.GroupRemoved else error.StaleSession;
                if (held == .group) {
                    const group = (self.roster orelse return error.ContextUnavailable).findById(@intCast(held.group)) orelse return error.GroupRemoved;
                    changed = changed or group.membership_revision != value.bridge.roster_revision;
                }
                if (!changed) return;
                var next_context = value.previous;
                next_context.binding = state.owner;
                next_context.content = held;
                next_context.binding_revision = state.binding_revision;
                const captured = try self.captureOwnerScope(state.owner);
                defer self.allocator.free(captured.inventory.?);
                if (self.execution().host_notice_revision <= self.execution().authority_notice_revision) self.execution().host_notice_revision = try @import("../../../host/identity.zig").advance(self.execution().authority_notice_revision +| @intFromBool(self.execution().authority_notice_revision == 0));
                const controller = lookupLifecycleTask(self, next_context.conversation_id, next_context.task_id) orelse return error.ScopeChanged;
                controller.notice_revision = @max(controller.notice_revision, self.execution().host_notice_revision);
                try controller.refreshAuthority(next_context);
                self.prepareHostCatalog(app);
                var next = @import("../tools/host/ai_tools.zig").Bridge.init(value.bridge.allocator);
                defer next.deinit();
                next.queries_only = value.bridge.queries_only;
                next.configureFiles(self.file_application);
                next.configurePolicy(value.bridge.permissionPolicy().engine, value.bridge.policy_revision);
                next.execution_mode = value.bridge.execution_mode;
                next.session_retention = value.bridge.session_retention;
                next.route_broker = value.bridge.route_broker;
                var binding = value.bridge.host_binding orelse return error.InvalidHostAuthority;
                binding.context = next_context;
                binding.contributions = self.execution().host_catalog[0..self.execution().host_catalog_len];
                try next.configureHost(binding);
                if (held == .group) try next.prepareGroup(app, self.roster.?, captured) else if (next_context.child_origin != null) try next.prepareScope(app, captured) else {
                    const tab = self.tabForSession(held.session) orelse return error.StaleSession;
                    try next.prepare(app, tab.content_owner.session);
                }
                try value.bridge.replacePrepared(&next);
                var table = try @import("../../../ai/plugin_tools.zig").cloneTable(value.bridge.requestTable().?, value.allocator);
                errdefer table.deinit();
                const wire = try @import("../../../ai/plugin_tools.zig").providerDefinitions(&table, table.arena.allocator());
                const system = try @import("../../../ai/session_prompt.zig").buildConfigured(value.allocator, self.execution().request_execution_policy.execution_mode, wire, .{ .context_mode = self.execution().request_config.?.value.ai.child_context_mode, .reuse_policy = self.execution().request_config.?.value.ai.child_reuse_policy });
                errdefer value.allocator.free(system);
                const handoff_buffer = try value.allocator.alloc(PendingHostNotice, self.execution().pending_host_notices.items.len);
                defer value.allocator.free(handoff_buffer);
                const pending_handoffs = self.pendingInputNotices(next_context.conversation_id, handoff_buffer);
                const Handoff = struct { conversation_id: @import("../../../host/identity.zig").ConversationId, task_id: @import("../../../host/identity.zig").TaskId, revision: u64, text: []const u8 };
                const handoffs = try value.allocator.alloc(Handoff, pending_handoffs.len);
                defer value.allocator.free(handoffs);
                for (pending_handoffs, 0..) |*handoff, index| handoffs[index] = .{ .conversation_id = handoff.context.conversation_id, .task_id = handoff.context.task_id, .revision = handoff.revision, .text = handoff.content() };
                const notice = try std.json.Stringify.valueAlloc(value.allocator, .{ .host_context_notice = true, .conversation_id = next_context.conversation_id, .task_id = next_context.task_id, .current_binding = next_context.binding, .binding_revision = next_context.binding_revision, .notice_revision = self.execution().host_notice_revision, .membership_revision = value.bridge.roster_revision, .input_handoffs = handoffs[0..pending_handoffs.len], .shell_switches_json = shell_notices, .instruction = "宿主状态已更新。以本轮更新后的系统提示词、工具表及每项工具的目标范围为准；历史能力不代表当前能力。shell_switches_json 仅是已提交的切层候选与层级数据，不证明切层成功，也不授权输入。仅在对应工具仍可用时按系统提示词处理。未知结果需观察核验，不补造退出码、不重发已发送操作。用户接管只归还对应终端输入权，不中断本轮或已运行命令。绑定或成员变化后取得当前引用，历史调用保持原所属和调用ID。" }, .{});
                errdefer value.allocator.free(notice);
                self.managerRef().scope = value.bridge.requestTable().?.captured_scope;
                self.execution().request_tools = try @import("../../../ai/plugin_tools.zig").providerDefinitions(value.bridge.requestTable().?, self.execution().request_config.?.arena.allocator());
                self.execution().request_tools_len = self.execution().request_tools.len;
                self.execution().request_tool_tokens = try @import("../../../ai/local_text_request.zig").toolTokens(self.execution().request_tools[0..self.execution().request_tools_len]);
                self.execution().request_host_context = next_context;
                try self.prepareRecordingAccess(next_context);
                if (self.execution().task_finish) |*finish| try finish.registerTask(next_context);
                self.approvalsRef().wake = &self.execution().wake_target;
                self.questionsRef().wake = &self.execution().wake_target;
                try self.approvalsRef().configure(next_context, self.execution().request_policy_revision);
                self.questionsRef().configure(next_context);
                self.approvalsRef().updatePermissionPolicy(value.bridge.permissionPolicy().engine);
                try self.execution().inventory_approval.configure(next_context, self.execution().request_policy_revision);
                self.execution().authority_notice_revision = self.execution().host_notice_revision;
                self.execution().shell_notice_hash = shell_hash;
                self.composer_hash = null;
                self.conversation_dirty = true;
                value.result = .{ .table = table, .notice = notice, .notice_revision = self.execution().host_notice_revision, .system = system };
            }
        };
        var refresh_state: Refresh = .{ .host = @ptrCast(@alignCast(raw)), .bridge = bridge, .previous = previous.host_context orelse return null, .allocator = allocator };
        try bridge.callController(&refresh_state, Refresh.run, cancel);
        return refresh_state.result;
    }
    fn acknowledgeHostNotice(raw: *anyopaque, revision: u64, cancel: ?*ai_provider.CancelToken) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const runtime = if (self.execution().lifecycle_runtime) |*value| value else return;
        try runtime.acknowledgeNotice(self.execution().request_host_context orelse return, revision);
        const Acknowledge = struct {
            host: *AiHost,
            revision: u64,
            fn run(context: *anyopaque) !void {
                const ack: *@This() = @ptrCast(@alignCast(context));
                const current = ack.host.execution().request_host_context orelse return;
                for (ack.host.execution().pending_host_notices.items) |*item| if (item.*) |notice| if (notice.context.conversation_id.eql(current.conversation_id) and notice.revision <= ack.revision) {
                    item.* = null;
                };
            }
        };
        var ack: Acknowledge = .{ .host = self, .revision = revision };
        try self.execution().tool_bridge.callController(&ack, Acknowledge.run, cancel);
    }
    fn captureSubmittedHistory(self: *AiHost, conversation_id: @import("../../../host/identity.zig").ConversationId) void {
        const driver = self.execution().execution_driver orelse return;
        const workspace = self.workspace orelse return;
        for (workspace.tabs.items) |tab| {
            if (tab.content_owner != .session or tab.terminal == null) continue;
            var commands = driver.commandIndex(self.allocator, conversation_id, tab.content_owner.session) catch continue;
            defer commands.deinit(self.allocator);
            for (commands.records) |command| {
                const execution_id = command.execution_id orelse continue;
                const submitted = self.history_submissions.getOrPut(self.allocator, execution_id) catch continue;
                if (submitted.found_existing) continue;
                tab.terminal.?.observeSubmittedCommand(command.submitted_command);
            }
        }
    }

    fn acceptedHostResult(raw: *anyopaque, context: @import("../../../ai/host_tools.zig").Context, name: []const u8, result: *const @import("../../../ai/host_tools.zig").Result, cancel: ?*ai_provider.CancelToken) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const active = self.execution().request_host_context orelse return error.ScopeChanged;
        if (!active.conversation_id.eql(context.conversation_id) or !active.task_id.eql(context.task_id)) return error.ScopeChanged;
        // This callback follows the entire closed call/result batch. The
        // worker blocks on this explicit exchange while UI deep-copies facts;
        // Poll must never inspect a concurrently mutable Loop.
        if (self.managerRef().tool_run) |run| {
            const Capture = struct {
                host: *AiHost,
                context: @import("../../../ai/host_tools.zig").Context,
                run: *const @import("../../../ai/tool_loop.zig").Loop,
                fn apply(raw_capture: *anyopaque) !void {
                    const capture: *@This() = @ptrCast(@alignCast(raw_capture));
                    const backend = capture.host;
                    const owner = backend.attachedView();
                    const previous = backend.withAttachedView();
                    defer owner.execution_host = previous;
                    const states = if (owner.assistant_states) |value| value else return error.ConversationNotFound;
                    const state = states.findConversation(capture.context.conversation_id) orelse return error.ConversationNotFound;
                    const current = if (capture.run.tool_table) |table| table.host_context orelse return error.InvalidHostAuthority else return error.InvalidHostAuthority;
                    if (!current.conversation_id.eql(capture.context.conversation_id) or !current.task_id.eql(capture.context.task_id)) return error.ScopeChanged;
                    const sources = try owner.execution().tool_bridge.resultSources(owner.allocator);
                    defer owner.allocator.free(sources);
                    const displayed = owner.display_conversation == state.id;
                    if (!displayed and state.tool_results == null) state.tool_results = @import("../../../ai/tool_results.zig").Store.init(owner.allocator);
                    const destination = if (displayed) &owner.tool_results else &state.tool_results.?;
                    if (try destination.capture(capture.run, sources)) {
                        if (displayed) owner.uiOwner().invalidateTimeline();
                        owner.wake();
                    }
                }
            };
            var capture: Capture = .{ .host = self, .context = context, .run = run };
            try self.execution().tool_bridge.callController(&capture, Capture.apply, cancel);
        }
        if (result.status != .succeeded) return;
        var decoded: [64]u8 = undefined;
        const logical = @import("../../../ai/plugin_tools.zig").decodeName(&decoded, name) catch return;
        if (std.mem.eql(u8, logical, @import("../../../ai/child_gateway.zig").tool_id)) try @import("../../../ai/child_gateway.zig").acknowledge(self.attached_runner.?.task_root.?, result, self.allocator);
        if (std.mem.eql(u8, logical, "host.run_in_terminal") or std.mem.eql(u8, logical, "host.wait_execution") or std.mem.eql(u8, logical, "host.get_execution")) {
            const CaptureRecording = struct {
                host: *AiHost,
                context: @import("../../../ai/host_tools.zig").Context,
                fn run(raw_capture: *anyopaque) !void {
                    const capture: *@This() = @ptrCast(@alignCast(raw_capture));
                    try capture.host.validateHostContext(capture.context);
                    capture.host.captureSubmittedHistory(capture.context.conversation_id);
                    try capture.host.prepareRecordingAccess(capture.context);
                }
            };
            var capture: CaptureRecording = .{ .host = self, .context = context };
            try self.execution().tool_bridge.callController(&capture, CaptureRecording.run, cancel);
        }
        if (!std.mem.eql(u8, logical, "host.close_session")) return;
        for (result.blocks) |block| {
            if (block != .structured) continue;
            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, block.structured, .{});
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            const required = parsed.value.object.get("result_acknowledgement_required") orelse continue;
            if (required != .bool or !required.bool) continue;
            const reference = parsed.value.object.get("operation_ref") orelse return error.InvalidHostToolResult;
            if (reference != .string) return error.InvalidHostToolResult;
            const operation = try @import("../../../ai/host_lifecycle.zig").operationId(context, reference.string);
            const runtime = if (self.execution().lifecycle_runtime) |*value| value else return error.ToolNotAvailable;
            try runtime.acknowledgeResult(.{ .context = &self.execution().tool_bridge, .call = controllerScheduler }, context, operation);
        }
    }
    fn validateHostContext(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) !void {
        const app = self.application_host orelse return error.ContextUnavailable;
        const binding = self.execution().tool_bridge.host_binding orelse return error.ScopeChanged;
        if (!binding.context.eql(context) or app.workspace.app_config.agentPolicyRevision() != self.execution().request_policy_revision) return error.ScopeChanged;
        const store = if (self.assistant_states) |value| value else return error.ContextUnavailable;
        const state = store.findConversation(context.conversation_id) orelse return error.ScopeChanged;
        if (self.shared_service) |service| if (service.service.store.find(context.conversation_id)) |record| if (record.transition != null) return error.TransitionPending;
        if (context.child_origin != null or state.child_agent != null) {
            _ = try (self.shared_service orelse return error.ScopeChanged).service.validateAuthority(context);
        }
        if (state.closed or state.ended or !state.owner.eql(context.binding) or state.binding_revision != context.binding_revision or !self.attachmentOwnerExists(state.owner)) return error.ScopeChanged;
    }
    fn committedHandoffPending(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) bool {
        // commit_group publishes the new owner on the UI thread before the
        // blocked worker can close its result pair and refresh the tool table.
        // Preserve the exact choice through that interval; dispatch gates still
        // reject the old context. All other authority changes revoke normally.
        if (context.contentOf() != .session or self.execution().host_notice_revision <= self.execution().authority_notice_revision) return false;
        const app = self.application_host orelse return false;
        if (app.workspace.app_config.agentPolicyRevision() != self.execution().request_policy_revision) return false;
        const binding = self.execution().tool_bridge.host_binding orelse return false;
        if (!binding.context.eql(context)) return false;
        const pending = self.execution().tool_bridge.pending_binding orelse return false;
        const store = if (self.assistant_states) |value| value else return false;
        const state = store.findConversation(context.conversation_id) orelse return false;
        return !state.closed and self.execution().tool_bridge.pending_content != null and self.execution().tool_bridge.pending_content.? == .group and state.owner.eql(pending) and state.binding_revision == context.binding_revision +| 1 and state.initial_owner != null and state.initial_owner.?.eql(context.binding);
    }
    fn installChildExecution(raw: *anyopaque, record: *@import("../../../ai/session_lifecycle.zig").Record, root: *@import("../../../ai/task_budget.zig").Root, fact: @import("../../../ai/task_budget.zig").Fact, submission: @import("../../../host/identity.zig").SubmissionId, text: []const u8) !*@import("../../../ai/session_runtime.zig").Runner {
        const parent: *AiHost = @ptrCast(@alignCast(raw));
        const shared_host = parent.shared_service.?;
        const agent_id = record.child.?.info.agent;
        const a = std.heap.c_allocator;
        if (shared_host.closing) return error.ApplicationClosing;
        const existing_bridge = shared_host.bridgeFor(agent_id);
        if (existing_bridge == null) try shared_host.bridges.ensureUnusedCapacity(shared_host.allocator, 1);
        const backend: *AiHost = if (existing_bridge) |bridge| @ptrCast(@alignCast(bridge.context)) else try a.create(AiHost);
        if (existing_bridge == null) backend.* = parent.attachedView().attachedSlot(a, shared_host);
        var adopted = false;
        errdefer if (existing_bridge == null and !adopted) {
            backend.destroyAttachedResources();
            a.destroy(backend);
        };
        const state = try shared_host.presentations.createChildPresentation(record, record.binding.?.owner);
        state.binding_revision = record.revision;
        state.ended = false;
        state.closed = false;
        var controls = state.controls;
        // Frozen child config wins; the remaining defaults come from this
        // parent's captured generation, never from a later composer edit.
        const source = try parent.attachedInput(parent.attached_runner.?.context.?.submission);
        const life = @import("../../../ai/session_lifecycle.zig");
        if (record.child_settings == null) {
            var initial = life.child.Settings.fromInfo(record.child.?.info);
            initial.thinking = source.controls.thinking;
            initial.session_retention = source.controls.session_retention;
            initial.permission = source.controls.permission orelse .confirm;
            initial.execution_mode = source.controls.execution_mode orelse .auto;
            initial.targets = shared_host.service.store.agent(record.child.?.info.agent).?.targets;
            const allowed = try parent.attachedView().captureOwnerScope(record.binding.?.owner);
            defer if (allowed.inventory) |ids| parent.attachedView().allocator.free(ids);
            try shared_host.service.store.updateChildSettings(try shared_host.service.store.fence(record.child.?.info.owning_parent_conversation), record.child.?.info.agent, record.child_settings_revision, initial, allowed);
        }
        const prefs = life.Store.childPreferences(record);
        controls = source.controls;
        controls.model = prefs.model;
        controls.effort = prefs.effort;
        controls.permission = prefs.permission;
        controls.thinking = prefs.thinking;
        controls.session_retention = prefs.session_retention;
        controls.execution_mode = prefs.execution_mode;
        if (state.controls.model == null) try state.controls.setModel(shared_host.presentations.allocator, prefs.model);
        state.controls.effort = prefs.effort;
        state.controls.permission = prefs.permission;
        state.controls.thinking = prefs.thinking;
        state.controls.session_retention = prefs.session_retention;
        state.controls.execution_mode = prefs.execution_mode;
        var empty_text: ai_attachments.Bundle = .{ .allocator = a, .owner = record.binding.?.owner, .draft_epoch = 1, .items = &.{} };
        var empty_images: ai_images.Bundle = .{ .allocator = a, .owner = record.binding.?.owner, .draft_epoch = 1, .items = &.{} };
        var frozen = try backend.captureAttachedInput(submission, text, &empty_text, &empty_images, parent.request_config.?.value, &controls);
        errdefer frozen.deinit(a);
        // Validate saved selection on every reuse; never silently replace it.
        _ = try ai_provider_config.fromSettingsSelection(frozen.config.?.value.ai, frozen.controls.model);
        if (frozen.controls.effort) |effort| try ai_provider_config.validateEffort(frozen.config.?.value.ai, frozen.controls.model, effort);
        try backend.attached_inputs.ensureUnusedCapacity(a, 1);
        const runner = try shared_host.service.adoptChild(record, .{ .context = backend, .capture = captureAttached, .prepare = prepareAttached, .completed = completeAttached, .local_released = attachedReleased, .supersede = supersedeAttached, .stop = stopAttached, .release_worker = releaseAttachedWorker }, root, fact);
        backend.attached_runner = runner;
        adopted = true;
        if (existing_bridge == null) try shared_host.register(.{ .agent = agent_id, .window = parent.application_host.?.window_id, .context = backend, .pump = pumpAttached, .released = disposeReadyAttached, .destroy = destroyAttached, .flush = flushAttached });
        backend.attached_inputs.appendAssumeCapacity(frozen);
        return runner;
    }
    fn dispatchChildGateway(self: *AiHost, bridge: *@import("../tools/host/ai_tools.zig").Bridge, invocation: @import("../../../ai/host_tools.zig").Invocation, allocator: std.mem.Allocator, cancel: ?*ai_provider.CancelToken) !@import("../../../ai/host_tools.zig").Result {
        const gateway = @import("../../../ai/child_gateway.zig");
        const parsed = try gateway.parse(allocator, invocation.arguments);
        defer parsed.deinit();
        const request = parsed.value;
        var history: @import("../../../ai/wire_history.zig").History = .{};
        defer history.deinit();
        var inherited: ?@import("../../../ai/session_lifecycle.zig").Store.Inherited = null;
        if (request.action == .create and @import("../../../ai/child_agent.zig").resolve(.{ .context_mode = self.request_config.?.value.ai.child_context_mode, .reuse_policy = self.request_config.?.value.ai.child_reuse_policy }, request.context_mode, request.reusable).context_mode == .inherit) {
            const loop = self.managerRef().tool_run orelse return error.NoStableCheckpoint;
            var targets: [32]@import("../../../host/identity.zig").SessionHandle = undefined;
            var ids: [32]u64 = undefined;
            for (request.session_refs.?, 0..) |reference, i| {
                const handle = for (bridge.children.items) |child| {
                    const current = try @import("../../../ai/host_queries.zig").sessionRef(allocator, invocation.context, child.owner);
                    defer allocator.free(current);
                    if (std.mem.eql(u8, reference, current)) break child.owner;
                } else return error.TargetNotAuthorized;
                targets[i] = handle;
                ids[i] = @backingInt(handle.session_id);
            }
            var child_scope = loop.scope;
            child_scope.inventory = ids[0..request.session_refs.?.len];
            history = try loop.snapshotForChild(allocator, invocation.call_id, child_scope, targets[0..request.session_refs.?.len]);
            inherited = .{ .source = .{ .conversation = invocation.context.conversation_id, .content_revision = self.attached_runner.?.record.?.content_revision, .turn = invocation.turn_id, .message_count = history.messages.len }, .messages = history.messages };
        }
        const Call = struct {
            host: *AiHost,
            invocation: @import("../../../ai/host_tools.zig").Invocation,
            request: gateway.Request,
            inherited: ?@import("../../../ai/session_lifecycle.zig").Store.Inherited,
            allocator: std.mem.Allocator,
            result: ?@import("../../../ai/host_tools.zig").Result = null,
            has_events: bool = false,
            fn run(raw: *anyopaque) !void {
                const self_call: *@This() = @ptrCast(@alignCast(raw));
                const value = self_call.host;
                try value.validateHostContext(self_call.invocation.context);
                const allowed = try value.captureOwnerScope(self_call.invocation.context.binding);
                defer value.allocator.free(allowed.inventory.?);
                var handles: [@import("../../../ai/tool_scope.zig").max_targets]@import("../../../host/identity.zig").SessionHandle = undefined;
                if (allowed.memberIds().len > handles.len) return error.TooManyToolTargets;
                for (allowed.memberIds(), 0..) |session_id, i| handles[i] = (value.tabForSession(session_id) orelse return error.StaleSession).content_owner.session;
                const root = value.attached_runner.?.task_root.?;
                root.lock();
                self_call.has_events = for (root.facts[0..root.count]) |fact| {
                    if (fact.parent != null and fact.event_sequence > self_call.request.after_sequence) break true;
                } else false;
                root.mutex.unlock();
                const source = try value.attachedInput(value.attached_runner.?.context.?.submission);
                if (self_call.request.action == .create) {
                    const selection = self_call.request.model orelse source.controls.model;
                    _ = try ai_provider_config.fromSettingsSelection(value.request_config.?.value.ai, selection);
                    if (self_call.request.effort orelse source.controls.effort) |effort| try ai_provider_config.validateEffort(value.request_config.?.value.ai, selection, effort);
                }
                var skill_ids: [32][]const u8 = undefined;
                var skill_count: usize = 0;
                var mcp_ids: [16][]const u8 = undefined;
                var mcp_count: usize = 0;
                if (value.extension_session) |session| {
                    for (session.frozen.skills) |skill| if (skill.enabled and value.extensionAllowed(skill.id, false)) {
                        skill_ids[skill_count] = skill.id;
                        skill_count += 1;
                    };
                    for (session.frozen.servers) |server| if (server.enabled and value.extensionAllowed(server.id, true)) {
                        mcp_ids[mcp_count] = server.id;
                        mcp_count += 1;
                    };
                }
                self_call.result = try gateway.execute(.{ .service = &value.shared_service.?.service, .authority = self_call.invocation.context, .live = allowed, .handles = handles[0..allowed.memberIds().len], .inherited = self_call.inherited, .factory = .{ .context = value, .defaults = .{ .context_mode = value.request_config.?.value.ai.child_context_mode, .reuse_policy = value.request_config.?.value.ai.child_reuse_policy }, .model = source.controls.model orelse .{ .provider_id = value.request_config.?.value.ai.default_provider, .model_id = value.model }, .effort = source.controls.effort, .skill_ids = skill_ids[0..skill_count], .mcp_ids = mcp_ids[0..mcp_count], .install = installChildExecution } }, self_call.invocation, self_call.request, self_call.allocator);
            }
        };
        var call: Call = .{ .host = self, .invocation = invocation, .request = request, .inherited = inherited, .allocator = allocator };
        const started = (@import("../../../ai/retry.zig").Clock{}).now();
        const root = self.attached_runner.?.task_root.?;
        const task = self.attached_runner.?.context.?.task;
        // Waiting releases model slots and pauses only this branch's local
        // budget; the root clock continues while any sibling is doing work.
        const human_wait = if (request.action == .wait_events) ai_provider.CancelToken.beginUserWait(cancel) else ai_provider.CancelToken.UserWait{ .token = null };
        defer human_wait.end();
        if (request.action == .wait_events) try root.state(task, .waiting_children, "");
        defer if (request.action == .wait_events) root.state(task, .running, "") catch {};
        while (true) {
            try bridge.callController(&call, Call.run, cancel);
            if (request.action != .wait_events or call.has_events or (@import("../../../ai/retry.zig").Clock{}).now() - started >= @as(i128, request.wait_ms) * std.time.ns_per_ms) return call.result.?;
            call.result.?.deinit(allocator);
            call.result = null;
            if (cancel) |token| if (token.isCancelled()) return error.Cancelled;
            (@import("../../../ai/retry.zig").Clock{}).sleep(10 * std.time.ns_per_ms);
        }
    }
    fn extensionAllowed(self: *AiHost, key: []const u8, mcp: bool) bool {
        const live = (self.backend_owner orelse self).runtime_config orelse return false;
        const frozen = self.extension_session orelse return false;
        if (mcp) {
            for (frozen.frozen.servers) |selected| if (selected.enabled and std.mem.eql(u8, key, selected.id)) {
                for (live.value.ai.extensions.servers) |current| if (current.enabled and std.mem.eql(u8, current.id, key)) return @import("../../../config/settings_schema.zig").same(selected, current);
            };
        } else {
            for (frozen.frozen.skills) |selected| if (selected.enabled and std.mem.eql(u8, key, selected.id)) {
                for (live.value.ai.extensions.skills) |current| if (current.enabled and std.mem.eql(u8, current.id, key)) return true;
            };
        }
        return false;
    }
    fn dispatchExtensionGateway(self: *AiHost, bridge: *@import("../tools/host/ai_tools.zig").Bridge, invocation: @import("../../../ai/host_tools.zig").Invocation, a: std.mem.Allocator, cancel: ?*ai_provider.CancelToken) !@import("../../../ai/host_tools.zig").Result {
        const session = if (self.extension_session) |*value| value else return error.ToolNotAvailable;
        const Context = struct {
            host: *AiHost,
            bridge: *@import("../tools/host/ai_tools.zig").Bridge,
            invocation: @import("../../../ai/host_tools.zig").Invocation,
            allocator: std.mem.Allocator,
            key: []const u8 = "",
            mcp: bool = false,
            server: @import("../../../config/ai_extensions.zig").Server = undefined,
            fn validate(raw: *anyopaque) !void {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                try ctx.host.validateHostContext(ctx.invocation.context);
                if (ctx.key.len != 0 and !ctx.host.extensionAllowed(ctx.key, ctx.mcp)) return error.ExtensionRevoked;
            }
            fn check(raw: *anyopaque, key: []const u8, mcp: bool, token: ?*ai_provider.CancelToken) !void {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                ctx.key = key;
                ctx.mcp = mcp;
                try ctx.bridge.callController(ctx, validate, token);
                if (token) |t| if (t.isCancelled()) return error.CancelledBeforeDispatch;
            }
            fn question(raw: *anyopaque, allocator: std.mem.Allocator, text: []const u8, options: []const @import("../../../ai/mcp_interaction.zig").Option, custom: bool, token: ?*ai_provider.CancelToken) !@import("../../../ai/user_interaction.zig").Answer {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                try check(raw, ctx.server.id, true, token);
                var arena = std.heap.ArenaAllocator.init(allocator);
                defer arena.deinit();
                const call = try @import("../../../ai/mcp_interaction.zig").invocation(arena.allocator(), ctx.invocation, "host.request_user_input", .{ .question = text, .options = options, .allow_custom = custom });
                const ticket = try ctx.host.questionsRef().begin(call, allocator);
                const answer = try ctx.host.questionsRef().wait(ticket, token);
                try check(raw, ctx.server.id, true, token);
                return answer;
            }
            fn review(raw: *anyopaque, allocator: std.mem.Allocator, method: []const u8, params: std.json.Value, token: ?*ai_provider.CancelToken) !void {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                try check(raw, ctx.server.id, true, token);
                var arena = std.heap.ArenaAllocator.init(allocator);
                defer arena.deinit();
                const call = try @import("../../../ai/mcp_interaction.zig").invocation(arena.allocator(), ctx.invocation, ctx.invocation.tool_id, .{ .server_id = ctx.server.id, .method = method, .params = params });
                const detail = try std.json.Stringify.valueAlloc(arena.allocator(), call.arguments, .{ .whitespace = .indent_2 });
                const permit = try ctx.host.approvalsRef().beginSubject(call, .{ .human_review = true, .kind = .mcp, .target = ctx.server.name, .detail = detail, .impact = method }, ctx.host.request_policy_revision, allocator);
                defer ctx.host.approvalsRef().finish(permit);
                try ctx.host.approvalsRef().waitForDecision(permit, token);
                try check(raw, ctx.server.id, true, token);
            }
            fn sample(raw: *anyopaque, allocator: std.mem.Allocator, params: std.json.Value, token: ?*ai_provider.CancelToken) ![]u8 {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                const binding = ctx.host.native_binding orelse return error.ProviderUnavailable;
                return @import("../../../ai/mcp_sampling.zig").generate(allocator, ctx.host.provider, binding.config.model, 0, params, token);
            }
            fn open(raw: *anyopaque, url: []const u8, token: ?*ai_provider.CancelToken) !void {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                try @import("../../../config/ai_extensions.zig").text(url, 8192, false);
                const uri = std.Uri.parse(url) catch return error.InvalidMcpEndpoint;
                if (uri.host == null or uri.user != null or uri.password != null or (!std.mem.eql(u8, uri.scheme, "https") and !(std.mem.eql(u8, uri.scheme, "http") and (std.mem.eql(u8, uri.host.?.percent_encoded, "localhost") or std.mem.eql(u8, uri.host.?.percent_encoded, "127.0.0.1") or std.mem.eql(u8, uri.host.?.percent_encoded, "[::1]"))))) return error.InvalidMcpEndpoint;
                const Open = struct {
                    url: [:0]const u8,
                    extern fn macos_open_url([*:0]const u8) c_int;
                    fn run(value: *anyopaque) !void {
                        const opened: *@This() = @ptrCast(@alignCast(value));
                        if (macos_open_url(opened.url) != 1) return error.BrowserOpenFailed;
                    }
                };
                const z = try ctx.allocator.dupeSentinel(u8, url, 0);
                defer ctx.allocator.free(z);
                var browser_open: Open = .{ .url = z };
                try ctx.bridge.callController(&browser_open, Open.run, token);
            }
            fn request(raw: *anyopaque, server: @import("../../../config/ai_extensions.zig").Server, allocator: std.mem.Allocator, method: []const u8, params: std.json.Value, token: ?*ai_provider.CancelToken) ![]u8 {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                ctx.server = server;
                if (std.mem.eql(u8, method, "host/mcp_continue") or std.mem.eql(u8, method, "host/mcp_continue_url")) {
                    try check(raw, server.id, true, token);
                    if (ctx.invocation.dispatch_fence) |fence| try fence.check();
                    if (std.mem.eql(u8, method, "host/mcp_continue_url")) try review(raw, allocator, "网页操作完成后继续 MCP 请求", params, token);
                    return allocator.dupe(u8, "{}");
                }
                return @import("../../../ai/mcp_interaction.zig").handle(.{ .context = raw, .question = question, .review = review, .sample = sample, .open = open }, allocator, server, method, params, token);
            }
            fn approve(raw: *anyopaque, call: @import("../../../ai/host_tools.zig").Invocation, server: @import("../../../config/ai_extensions.zig").Server, remote_tool: ?[]const u8, token: ?*ai_provider.CancelToken) !void {
                const ctx: *@This() = @ptrCast(@alignCast(raw));
                const detail = try std.json.Stringify.valueAlloc(ctx.allocator, .{
                    .server = server.name,
                    .transport = server.transport,
                    .program = if (server.transport == .stdio) server.program else "",
                    .args = server.args,
                    .cwd = server.cwd,
                    .endpoint = if (server.transport == .http) server.endpoint else "",
                    .remote_tool = remote_tool,
                    .request = call.arguments,
                }, .{ .whitespace = .indent_2 });
                defer ctx.allocator.free(detail);
                const permit = try ctx.host.approvalsRef().beginSubject(call, .{ .kind = .mcp, .target = server.name, .detail = detail, .impact = "启动已配置的 MCP 服务，或按上方参数执行所选工具；结果来自外部服务。" }, ctx.host.request_policy_revision, ctx.allocator);
                defer ctx.host.approvalsRef().finish(permit);
                try ctx.host.approvalsRef().waitForDecision(permit, token);
            }
        };
        const Cancellation = struct {
            parent: ?*ai_provider.CancelToken,
            session: *@import("../../../ai/extension_gateway.zig").Session,
            fn poll(raw: *const anyopaque) bool {
                const ctx: *const @This() = @ptrCast(@alignCast(raw));
                return ctx.session.revoked.load(.acquire) or (if (ctx.parent) |token| token.isCancelled() else false);
            }
            fn wait(raw: *const anyopaque, active: bool) void {
                const ctx: *const @This() = @ptrCast(@alignCast(raw));
                if (ctx.parent) |token| if (token.source) |source| if (source.user_wait) |notify| notify(source.context, active);
            }
        };
        var ctx: Context = .{ .host = self, .bridge = bridge, .invocation = invocation, .allocator = a };
        const cancellation: Cancellation = .{ .parent = cancel, .session = session };
        var token: ai_provider.CancelToken = .{ .source = .{ .context = &cancellation, .poll = Cancellation.poll, .user_wait = Cancellation.wait } };
        return session.invoke(self.native_context.?.io, .{ .context = &ctx, .check = Context.check, .approve = Context.approve, .request = Context.request }, self.lifecycle_runtime.?.journal_owner, invocation, &token, a) catch |err| rejectedHostInvocation(invocation, a, err);
    }
    fn dispatchHostWorker(raw: *anyopaque, bridge: *@import("../tools/host/ai_tools.zig").Bridge, invocation: @import("../../../ai/host_tools.zig").Invocation, allocator: std.mem.Allocator, cancel: ?*ai_provider.CancelToken) !@import("../../../ai/host_tools.zig").Result {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (self.attached_runner) |runner| if (runner.observation_only) {
            const table = self.tool_bridge.requestTable() orelse return error.ToolNotAvailable;
            const entry = for (table.entries) |item| {
                if (std.mem.eql(u8, item.definition.id, invocation.tool_id)) break item;
            } else return error.ToolNotAvailable;
            if (entry.definition.effect != .read_state and entry.definition.effect != .observe_image) return rejectedHostInvocation(invocation, allocator, error.ObservationOnlyTask);
        };
        if (@import("../../../ai/extension_gateway.zig").supports(invocation.tool_id)) return self.dispatchExtensionGateway(bridge, invocation, allocator, cancel);
        if (std.mem.eql(u8, invocation.tool_id, @import("../../../ai/child_gateway.zig").tool_id)) return self.dispatchChildGateway(bridge, invocation, allocator, cancel);
        if (@import("../../../ai/user_interaction.zig").supports(invocation.tool_id)) {
            const Validate = struct {
                host: *AiHost,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                fn run(context: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(context));
                    try value.host.validateHostContext(value.invocation.context);
                }
            };
            var validation: Validate = .{ .host = self, .invocation = invocation };
            try bridge.callController(&validation, Validate.run, cancel);
            if (cancel) |token| if (token.isCancelled()) return error.CancelledBeforeDispatch;
            const ticket = try self.questionsRef().begin(invocation, allocator);
            const answer = try self.questionsRef().wait(ticket, cancel);
            try bridge.callController(&validation, Validate.run, cancel);
            return @import("../../../ai/user_interaction.zig").result(invocation, answer, allocator);
        }
        if (self.execution().recording_access) |*access| access.expireIdle();
        if (@import("../../../ai/host_terminal_queries.zig").supports(invocation.tool_id)) {
            const request = try @import("../../../ai/host_terminal_queries.zig").parse(invocation.tool_id, invocation.arguments);
            if (request.source == .recording) {
                const Validate = struct {
                    host: *AiHost,
                    invocation: @import("../../../ai/host_tools.zig").Invocation,
                    fn run(raw_query: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_query));
                        try value.host.validateHostContext(value.invocation.context);
                        const access = if (value.host.execution().recording_access) |*item| item else return error.TargetNotAuthorized;
                        const candidate = try access.candidateIdentity(value.invocation);
                        const controller = lookupLifecycleTask(value.host, value.invocation.context.conversation_id, value.invocation.context.task_id) orelse return error.ScopeChanged;
                        if (!controller.inBinding(candidate.owner) and !controller.permitsHistoricalRecording(candidate.owner, candidate.id, candidate.generation)) return error.TargetNotAuthorized;
                    }
                };
                var validation: Validate = .{ .host = self, .invocation = invocation };
                try bridge.callController(&validation, Validate.run, cancel);
                if (cancel) |token| if (token.isCancelled()) return error.CancelledBeforeDispatch;
                var result = try self.execution().recording_access.?.execute(invocation, allocator);
                bridge.callController(&validation, Validate.run, cancel) catch |err| {
                    result.deinit(allocator);
                    return rejectedHostInvocation(invocation, allocator, err);
                };
                return result;
            }
        }
        if (std.mem.eql(u8, invocation.tool_id, @import("../../../ai/builtin_tools.zig").id)) return bridge.queryHost(invocation, allocator, cancel);
        if (@import("../../../ai/batch_output.zig").supports(invocation.tool_id)) return bridge.queryHost(invocation, allocator, cancel);
        if (@import("../../../ai/host_queries.zig").supports(invocation.tool_id)) return bridge.queryHost(invocation, allocator, cancel);
        // 直接按 ToolDef 写的宿主工具（host.tab_context）在 UI 线程的宿主网关里走统一流水线。
        if (@import("../../../ai/host_tool_catalog.zig").isNative(invocation.tool_id)) return bridge.queryHost(invocation, allocator, cancel);
        if (@import("../../../ai/host_terminal_queries.zig").supports(invocation.tool_id)) return bridge.queryHost(invocation, allocator, cancel);
        if (@import("../../../ai/host_catalog.zig").supports(invocation.tool_id)) {
            if (!@import("../../../ai/host_catalog.zig").isMutation(invocation.tool_id)) return bridge.queryHost(invocation, allocator, cancel);
            const catalog_runtime = @import("../../../ai/host_catalog_runtime.zig");
            var prepared = @import("../tools/host/ai_host_catalog_controller.zig").prepare(invocation, allocator) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            defer prepared.deinit(allocator);
            const runtime = if (self.execution().lifecycle_runtime) |*value| value else return error.ToolNotAvailable;
            var operation = catalog_runtime.begin(runtime.journal_owner, invocation, allocator) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            defer operation.deinit(allocator);
            if (operation.handle.reused) {
                const Replay = struct {
                    host: *AiHost,
                    operation: *const catalog_runtime.Operation,
                    invocation: @import("../../../ai/host_tools.zig").Invocation,
                    allocator: std.mem.Allocator,
                    result: ?@import("../../../ai/host_tools.zig").Result = null,
                    fn run(raw_replay: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_replay));
                        try value.host.validateHostContext(value.invocation.context);
                        const app = value.host.application_host orelse return error.ContextUnavailable;
                        value.result = try value.operation.replay(&app.workspace.registry, value.invocation, value.allocator);
                    }
                };
                var replay: Replay = .{ .host = self, .operation = &operation, .invocation = invocation, .allocator = allocator };
                bridge.callController(&replay, Replay.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
                return replay.result orelse error.InvalidControllerReceipt;
            }
            const subject = prepared.subject();
            const permit = bridge.requestHostRoute(invocation, subject, allocator, cancel) catch |err| {
                operation.failed(err) catch {};
                return operation.failureResult(invocation, err, allocator);
            };
            defer self.approvalsRef().finish(permit);
            operation.dispatched() catch |err| {
                operation.failed(err) catch {};
                return operation.failureResult(invocation, err, allocator);
            };
            const SaveHost = struct {
                host: *AiHost,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                operation: @import("../../../host/identity.zig").HostOperationId,
                permit: @import("../../../ai/host_approval.zig").Permit,
                subject: @import("../../../ai/host_approval.zig").Subject,
                allocator: std.mem.Allocator,
                result: ?@import("../../../ai/host_tools.zig").Result = null,
                fn run(raw_save: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(raw_save));
                    try value.host.validateHostContext(value.invocation.context);
                    if (value.host.approvalsRef().authorizeSubject(value.permit, value.invocation, value.subject, value.host.execution().request_policy_revision) != .allow) return error.ScopeChanged;
                    var approved = value.invocation;
                    approved.approval_sequence = value.permit.sequence;
                    value.result = try @import("../tools/host/ai_host_catalog_controller.zig").executeOperation(value.host.application_host orelse return error.ContextUnavailable, approved, value.allocator, value.operation);
                }
            };
            var save: SaveHost = .{ .host = self, .invocation = invocation, .operation = operation.handle.operation_ref, .permit = permit, .subject = subject, .allocator = allocator };
            bridge.callController(&save, SaveHost.run, cancel) catch |err| {
                operation.failed(err) catch {};
                return operation.failureResult(invocation, err, allocator);
            };
            var result = save.result orelse return error.InvalidControllerReceipt;
            const asset = catalog_runtime.createdOwner(result, invocation.context) catch |err| {
                result.deinit(allocator);
                operation.failed(err) catch {};
                return operation.failureResult(invocation, err, allocator);
            };
            operation.succeeded(asset) catch |err| {
                result.deinit(allocator);
                operation.failed(err) catch {};
                return operation.failureResult(invocation, err, allocator);
            };
            return result;
        }
        if (@import("../../../ai/host_lifecycle.zig").supports(invocation.tool_id)) {
            const LifecycleScope = struct {
                host: *AiHost,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                fn run(raw_lifecycle: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(raw_lifecycle));
                    try value.host.validateHostContext(value.invocation.context);
                    const controller = lookupLifecycleTask(value.host, value.invocation.context.conversation_id, value.invocation.context.task_id) orelse return error.ScopeChanged;
                    try controller.validateRequestScope(value.invocation.context, try @import("../../../ai/host_lifecycle.zig").parse(value.invocation));
                }
            };
            var lifecycle_scope: LifecycleScope = .{ .host = self, .invocation = invocation };
            bridge.callController(&lifecycle_scope, LifecycleScope.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            const runtime = if (self.execution().lifecycle_runtime) |*value| value else return error.ToolNotAvailable;
            return runtime.execute(.{ .context = bridge, .call = controllerScheduler }, invocation, allocator, cancel);
        }
        if (@import("../../../ai/host_execution.zig").supports(invocation.tool_id)) {
            const ScopePreflight = struct {
                host: *AiHost,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                fn run(raw_scope: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(raw_scope));
                    try value.host.validateHostContext(value.invocation.context);
                    const backend = if (value.host.execution().execution_backend) |*item| item else return error.ToolNotAvailable;
                    try backend.validateInvocationScope(value.invocation);
                }
            };
            var scope_preflight: ScopePreflight = .{ .host = self, .invocation = invocation };
            bridge.callController(&scope_preflight, ScopePreflight.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            const driver = self.execution().execution_driver orelse return error.ToolNotAvailable;
            if (std.mem.eql(u8, invocation.tool_id, "host.attach_shell")) {
                const Attachment = struct {
                    backend: *@import("../tools/host/ai_execution_backend.zig").Context,
                    invocation: @import("../../../ai/host_tools.zig").Invocation,
                    prepared: ?@import("../tools/host/ai_execution_backend.zig").AttachmentPrepared = null,
                    permit: ?@import("../../../ai/host_approval.zig").Permit = null,
                    allocator: std.mem.Allocator,
                    result: ?@import("../../../ai/host_tools.zig").Result = null,
                    progress: ?@import("../../../ai/host_tools.zig").Result = null,
                    timed_out: bool = false,
                    fn preflight(raw_attach: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_attach));
                        value.prepared = try value.backend.preflightAttachment(value.invocation);
                    }
                    fn dispatch(raw_attach: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_attach));
                        value.result = try value.backend.dispatchAttachment(value.invocation, value.prepared.?, value.permit.?, value.allocator);
                    }
                    fn poll(raw_attach: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_attach));
                        value.progress = try value.backend.pollAttachment(value.invocation, value.prepared.?, value.allocator, value.timed_out);
                    }
                };
                var attachment: Attachment = .{ .backend = if (self.execution().execution_backend) |*backend| backend else return error.ToolNotAvailable, .invocation = invocation, .allocator = allocator };
                bridge.callController(&attachment, Attachment.preflight, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
                const permit = try self.approvalsRef().requestSubject(invocation, attachment.prepared.?.subject, self.execution().request_policy_revision, allocator, cancel);
                defer self.approvalsRef().finish(permit);
                attachment.permit = permit;
                bridge.callController(&attachment, Attachment.dispatch, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
                const wait_ms: i64 = if (invocation.arguments.object.get("wait_ms")) |value| value.integer else 0;
                if (wait_ms > 0) {
                    const deadline = @import("../../../platform/realtime.zig").monotonicNs() + @as(i128, wait_ms) * std.time.ns_per_ms;
                    while (true) {
                        attachment.timed_out = @import("../../../platform/realtime.zig").monotonicNs() >= deadline;
                        bridge.callController(&attachment, Attachment.poll, cancel) catch break;
                        if (attachment.progress) |progress| {
                            if (attachment.result) |*initial_result| initial_result.deinit(allocator);
                            return progress;
                        }
                        if (attachment.timed_out) break;
                        @import("../../../ai/retry.zig").wait(50, cancel) catch break;
                    }
                }
                return attachment.result orelse return error.InvalidControllerReceipt;
            }
            if (std.mem.eql(u8, invocation.tool_id, "host.get_execution") or std.mem.eql(u8, invocation.tool_id, "host.wait_execution")) {
                var result = driver.executeAlloc(invocation, allocator, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
                bridge.callController(&scope_preflight, ScopePreflight.run, cancel) catch |err| {
                    result.deinit(allocator);
                    return rejectedHostInvocation(invocation, allocator, err);
                };
                return result;
            }
            if (std.mem.eql(u8, invocation.tool_id, "host.send_execution_input")) {
                // Secret input uses its own native collector. Plain input has
                // one exact, fresh approval and never carries an execution route.
                if (invocation.arguments == .object and invocation.arguments.object.get("host_secret_request") != null) return driver.executeAlloc(invocation, allocator, cancel);
                const InputPreflight = struct {
                    backend: *@import("../tools/host/ai_execution_backend.zig").Context,
                    invocation: @import("../../../ai/host_tools.zig").Invocation,
                    allocator: std.mem.Allocator,
                    prepared: ?@import("../tools/host/ai_execution_backend.zig").InputPrepared = null,
                    fn run(raw_input: *anyopaque) !void {
                        const value: *@This() = @ptrCast(@alignCast(raw_input));
                        value.prepared = try value.backend.preflightInput(value.invocation, value.allocator);
                    }
                };
                var input: InputPreflight = .{ .backend = if (self.execution().execution_backend) |*backend| backend else return error.ToolNotAvailable, .invocation = invocation, .allocator = allocator };
                bridge.callController(&input, InputPreflight.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
                defer input.prepared.?.deinit();
                const permit = try self.approvalsRef().requestSubject(invocation, input.prepared.?.subject, self.execution().request_policy_revision, allocator, cancel);
                defer self.approvalsRef().finish(permit);
                var approved = invocation;
                approved.approval_sequence = permit.sequence;
                return driver.executeAlloc(approved, allocator, cancel);
            }
            if (!std.mem.eql(u8, invocation.tool_id, "host.run_in_terminal")) return driver.executeAlloc(invocation, allocator, cancel);
            var prepared = @import("../tools/host/ai_execution_backend.zig").prepare(invocation, allocator) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            defer prepared.deinit();
            const target_value = prepared.invocation.arguments.object.get("session_ref") orelse return error.InvalidArguments;
            if (target_value != .string) return error.InvalidArguments;
            const target = try @import("../../../ai/host_terminal_queries.zig").resolveSession(invocation.context, target_value.string);
            const RoutePreflight = struct {
                host: *AiHost,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                target: @import("../../../host/identity.zig").SessionHandle,
                proposed: @import("../../../ai/execution_routing.zig").Route = .current_terminal,
                fn run(raw_route: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(raw_route));
                    try value.host.validateHostContext(value.invocation.context);
                    const app = value.host.application_host orelse return error.ContextUnavailable;
                    if (app.lifecycle_supervisor.resource(value.target)) |entry| {
                        if (entry.request.context.eql(value.invocation.context) and entry.snapshot.ownership == .created_task and entry.snapshot.state == .ready) {
                            const owner = lookupLifecycleTask(value.host, value.invocation.context.conversation_id, value.invocation.context.task_id) orelse return error.ScopeChanged;
                            owner.adoptRouteSession(value.invocation.context, entry.request.operation_ref, entry.snapshot);
                            value.proposed = .new_terminal;
                        }
                    }
                }
            };
            var route: RoutePreflight = .{ .host = self, .invocation = invocation, .target = target };
            bridge.callController(&route, RoutePreflight.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            if (try bridge.prepareHostRoute(prepared.invocation, &prepared.subject, target, route.proposed, allocator)) |changed| return changed;
            const Preflight = struct {
                backend: *@import("../tools/host/ai_execution_backend.zig").Context,
                prepared: *@import("../tools/host/ai_execution_backend.zig").Prepared,
                evidence: @import("../tools/host/ai_execution_backend.zig").ApprovalEvidence = .{},
                fn run(context: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(context));
                    value.evidence = try value.backend.preflight(value.prepared.invocation, value.prepared.command, value.prepared.command_hash);
                }
            };
            var preflight: Preflight = .{ .backend = if (self.execution().execution_backend) |*backend| backend else return error.ToolNotAvailable, .prepared = &prepared };
            bridge.callController(&preflight, Preflight.run, cancel) catch |err| return rejectedHostInvocation(invocation, allocator, err);
            prepared.subject.impact = preflight.evidence.text();
            const permit = try bridge.requestHostRoute(prepared.invocation, prepared.subject, allocator, cancel);
            defer self.approvalsRef().finish(permit);
            if (try bridge.hostRouteChange(prepared.invocation, prepared.subject, permit, allocator)) |changed| return changed;
            prepared.invocation.approval_sequence = permit.sequence;
            defer bridge.consumeHostRoute(prepared.invocation, target, prepared.command);
            bridge.hostExecutionStarted(prepared.invocation);
            return driver.executeAlloc(prepared.invocation, allocator, cancel);
        }
        if (@import("../../../ai/fetch_url.zig").supports(invocation.tool_id)) {
            const Validate = struct {
                host: *AiHost,
                context: @import("../../../ai/host_tools.zig").Context,
                fn run(context: *anyopaque) !void {
                    const value: *@This() = @ptrCast(@alignCast(context));
                    try value.host.validateHostContext(value.context);
                }
            };
            var validation: Validate = .{ .host = self, .context = invocation.context };
            try bridge.callController(&validation, Validate.run, cancel);
            if (invocation.arguments != .object) return error.InvalidArguments;
            const url = invocation.arguments.object.get("url") orelse return error.InvalidArguments;
            if (url != .string) return error.InvalidArguments;
            const revision = self.execution().request_policy_revision;
            const permit = try self.approvalsRef().request(invocation, url.string, revision, allocator, cancel);
            defer self.approvalsRef().finish(permit);
            const Grant = struct {
                broker: *@import("../../../ai/host_approval.zig").Broker,
                permit: @import("../../../ai/host_approval.zig").Permit,
                invocation: @import("../../../ai/host_tools.zig").Invocation,
                fn authorize(context: *anyopaque, current: @import("../../../ai/host_tools.zig").Context, policy_revision: u64, exact_url: []const u8) @import("../../../ai/fetch_url.zig").Decision {
                    const grant: *@This() = @ptrCast(@alignCast(context));
                    if (!current.eql(grant.invocation.context)) return .scope_changed;
                    return grant.broker.authorize(grant.permit, grant.invocation, exact_url, policy_revision);
                }
            };
            var grant: Grant = .{ .broker = self.approvalsRef(), .permit = permit, .invocation = invocation };
            return @import("../../../ai/fetch_url.zig").execute(.{ .context = invocation.context, .network_policy_revision = revision, .userdata = &grant, .authorize = Grant.authorize, .io = if (self.execution().ai_io) |io| io.io() else null }, invocation, allocator, cancel);
        }
        return error.ToolNotAvailable;
    }
    fn rejectedHostInvocation(invocation: @import("../../../ai/host_tools.zig").Invocation, allocator: std.mem.Allocator, failure: anyerror) !@import("../../../ai/host_tools.zig").Result {
        const host = @import("../../../ai/host_tools.zig");
        const recover_shell = failure == error.ShellPromptNotObserved or failure == error.IntegrationUnavailable or failure == error.ShellContextChanged;
        const next_tool = if (recover_shell) try @import("../../../ai/plugin_tools.zig").toolHints(allocator, &.{ "host.read_terminal", "host.get_session", "host.attach_shell" }) else null;
        defer if (next_tool) |hint| allocator.free(hint);
        const body = try std.json.Stringify.valueAlloc(allocator, .{ .error_code = @errorName(failure), .message = @import("../../../ai/step_failure.zig").explanation(@errorName(failure)), .next_tool = next_tool, .side_effect_started = false, .local_released = true, .remote_effect_unknown = false }, .{});
        errdefer allocator.free(body);
        const blocks = try allocator.alloc(host.Block, 1);
        blocks[0] = .{ .structured = body };
        return .{ .status = if (failure == error.CancelledBeforeDispatch) .cancelled_unsent else .rejected, .blocks = blocks, .receipt = .{ .conversation_id = invocation.context.conversation_id, .task_id = invocation.context.task_id, .operation_id = invocation.operation_id, .binding_revision = invocation.context.binding_revision } };
    }
    fn composerInteractionAction(raw: *anyopaque, ticket: @import("../composer/view/ai_composer_interaction_view.zig").Ticket, action: @import("../composer/view/ai_composer_interaction_view.zig").Action) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        if (!self.requestDisplayed() or self.execution().thread_state.load(.acquire) != 1) return error.StaleApproval;
        switch (ticket) {
            .tool => |value| switch (action) {
                .approve, .reject => try decideTool(raw, value.sequence, value.hash, action == .approve),
                else => return error.InvalidInteractionAction,
            },
            .host => |value| switch (action) {
                .approve, .reject => try decideHostApproval(raw, value.sequence, value.hash, action == .approve),
                .route => |route| try chooseHostRoute(raw, value.sequence, value.hash, route),
                else => return error.InvalidInteractionAction,
            },
            .question => |value| switch (action) {
                .answer => |answer| {
                    try self.validateHostContext(value.context);
                    try self.questionsRef().answer(value, answer.option_id, answer.text);
                },
                else => return error.InvalidInteractionAction,
            },
        }
        self.wake();
    }
    fn updateComposerInteraction(self: *AiHost) !bool {
        const V = @import("../composer/view/ai_composer_interaction_view.zig");
        const view = self.composer_interaction orelse return false;
        var snapshot: ?V.Snapshot = null;
        var options: [@import("../../../ai/user_interaction.zig").max_options]V.Option = undefined;
        // Value snapshots stay alive until update() copies their display data.
        const host_pending = self.approvalsRef().snapshot();
        const tool_pending = self.execution().tool_bridge.pendingApproval();
        const question_pending = self.questionsRef().snapshot();
        var title_owned: ?[]u8 = null;
        defer if (title_owned) |owned| self.allocator.free(owned);
        var target_owned: ?[]u8 = null;
        defer if (target_owned) |owned| self.allocator.free(owned);
        var detail_owned: ?[]u8 = null;
        defer if (detail_owned) |owned| self.allocator.free(owned);
        if (host_pending) |*pending| {
            // Resolve opaque host references for display using the captured live
            // owners. The exact original reference remains bound to approval.
            var target = pending.target.text();
            var target_owner: ?@import("../../../host/identity.zig").SessionHandle = null;
            if (pending.kind == .terminal_command and std.mem.startsWith(u8, target, "s1:")) {
                for (self.execution().tool_bridge.children.items) |child| {
                    const reference = try @import("../../../ai/host_queries.zig").sessionRef(self.allocator, pending.context, child.owner);
                    defer self.allocator.free(reference);
                    if (!std.mem.eql(u8, reference, target)) continue;
                    target_owner = child.owner;
                    break;
                }
            } else if (pending.kind == .terminal_command and std.mem.startsWith(u8, target, "x1:")) {
                // Execution input / control: show the terminal the execution runs in.
                if (self.execution().execution_backend) |*backend| target_owner = backend.executionOwner(pending.context, target);
            }
            if (target_owner) |owner| {
                if (self.application_host) |app| if (app.legacyForHandle(owner)) |legacy| if (app.workspace.sessionTab(legacy)) |tab| {
                    target_owned = try std.fmt.allocPrint(self.allocator, "{s} · #{d}", .{ tab.titleSlice(), @backingInt(owner.session_id) });
                    target = target_owned.?;
                };
            }
            // Never show an opaque host reference when no live tab resolves it.
            if (target_owned == null and (std.mem.startsWith(u8, target, "s1:") or std.mem.startsWith(u8, target, "x1:"))) target = "终端会话";
            snapshot = .{
                .ticket = .{ .host = .{ .sequence = pending.sequence, .hash = pending.arguments_hash } },
                .title = switch (pending.kind) {
                    .network_url => "确认访问网址",
                    .mcp => "确认 MCP 操作",
                    .lifecycle => "确认会话操作",
                    .terminal_command => "确认执行命令",
                },
                .target = target,
                .detail = pending.detail.text(),
                .impact = pending.impact.text(),
                .route = if (pending.route) |*route| route.choice.route else null,
                .route_selectable = if (pending.route) |*route| route.selectable else false,
                .route_reason = if (pending.route) |*route| route.reason.text() else "",
            };
        } else if (tool_pending) |pending| {
            title_owned = try @import("../cards/model/ai_tool_titles.zig").action(self.allocator, pending.tool_id orelse "run_command", pending.command);
            target_owned = if (pending.group) try self.allocator.dupe(u8, pending.target) else try std.fmt.allocPrint(self.allocator, "{s} · #{d}{s}{s}", .{ pending.target, @backingInt(pending.owner.session_id), if (pending.cwd != null) " · " else "", pending.cwd orelse "" });
            if (pending.tool_id) |name| if (std.mem.eql(u8, name, "file.write_text") or std.mem.eql(u8, name, "file.edit_text")) {
                detail_owned = try @import("../../../ai/terminal_file_tools.zig").approvalText(self.allocator, name, pending.command);
            };
            snapshot = .{ .ticket = .{ .tool = .{ .sequence = pending.sequence, .hash = pending.arguments_hash } }, .title = title_owned.?, .target = target_owned.?, .detail = detail_owned orelse pending.command, .impact = if (pending.group) "上述全部目标各执行一次；写入及业务影响尚未核实。" else "写入及业务影响尚未核实。" };
        } else if (question_pending) |*pending| {
            for (pending.options[0..pending.option_count], 0..) |*option, index| options[index] = .{ .id = option.id.text(), .label = option.label.text(), .description = option.description.text() };
            snapshot = .{ .ticket = .{ .question = pending.ticket }, .title = pending.question.text(), .options = options[0..pending.option_count], .allow_custom = pending.allow_custom };
        }
        const was_expanded = view.expanded();
        const was_pending = view.pendingVisible();
        const changed = try view.update(snapshot);
        view.setVisible(self.requestDisplayed());
        const expanded = view.expanded();
        var resized = false;
        if (self.composer_controls) |controls| controls.setInteraction(expanded);
        // The decision panel takes the composer's place (Pencil Kaf7E A7 / A11): the compound
        // Textarea (attachments header, tool-row footer) hides while it is open.
        if (self.composer_input) |input| {
            const was_shown = self.composer.?.field_shown.peek();
            self.composer.?.setFieldShown(!expanded);
            resized = was_shown == expanded;
            if (expanded) if (self.uiOwner().cx.focus_manager.current_focus) |focused| if (focused.isDescendantOf(input.wrapper)) self.uiOwner().cx.clearFocus();
        }
        if (self.tail_follow) |*follow| {
            var padding = follow.scroll.content.style.padding;
            padding.bottom = if (view.pendingVisible()) 32 else 0;
            follow.scroll.content.setStyleInline(self.allocator, .{ .padding = padding });
        }
        return resized or changed or was_expanded != expanded or was_pending != view.pendingVisible();
    }

    fn decideHostApproval(raw: *anyopaque, sequence: u64, hash: [32]u8, approved: bool) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (!self.requestDisplayed()) return error.StaleHostApproval;
        const pending = self.approvalsRef().snapshot() orelse return error.StaleHostApproval;
        try self.validateHostContext(pending.context);
        if (pending.sequence != sequence) return error.StaleHostApproval;
        try self.approvalsRef().decide(sequence, hash, approved);
        try self.execution().step_mailbox.push(.{ .call_id = pending.call.text(), .phase = if (approved) .approved else .rejected, .at_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)) });
        self.wake();
    }
    fn chooseHostRoute(raw: *anyopaque, sequence: u64, hash: [32]u8, route: @import("../../../ai/execution_routing.zig").Route) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        if (!self.requestDisplayed()) return error.StaleHostApproval;
        const pending = self.approvalsRef().snapshot() orelse return error.StaleHostApproval;
        try self.validateHostContext(pending.context);
        if (pending.sequence != sequence) return error.StaleHostApproval;
        try self.approvalsRef().chooseRoute(sequence, hash, route);
        self.wake();
    }
    fn secretRequest(binding: @import("../../../ai/host_secret_store.zig").Binding) @import("../../../host/terminal_execution.zig").InputRequest {
        return .{ .grant = binding.grant, .wait_sequence = binding.wait_sequence, .input_sequence = binding.input_sequence, .kind = .host_secret };
    }
    fn requestHostSecret(raw: *anyopaque, invocation: @import("../../../ai/host_tools.zig").Invocation, handle: @import("../../../host/identity.zig").SessionHandle, request: @import("../../../host/terminal_execution.zig").InputRequest) !@import("../../../host/terminal_execution.zig").InputReceipt {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        if (self.backend_owner) |view| {
            const previous = self.withAttachedView();
            defer view.execution_host = previous;
            return requestHostSecret(view, invocation, handle, request);
        }
        try self.validateHostContext(invocation.context);
        if (!self.requestDisplayed()) return error.HostSecretUnavailable;
        if (self.secret_controller == null) self.secret_controller = .{ .authority = .{ .context = self, .validate = validateHostSecret, .submit = submitHostSecret, .cancel = cancelHostSecret } };
        if (self.secret_controller.?.pending != null) return error.HostSecretBusy;
        const backend = if (self.execution().execution_backend) |*value| value else return error.HostSecretUnavailable;
        const service = try backend.preflightSecret(invocation.context, handle, request);
        const receipt = try service.executionSecret(.{ .begin = request });
        errdefer _ = backend.cancelSecret(invocation.context, handle, request) catch {};
        const binding: @import("../../../ai/host_secret_store.zig").Binding = .{ .context = invocation.context, .handle = handle, .grant = request.grant, .wait_sequence = request.wait_sequence, .input_sequence = request.input_sequence };
        try self.secret_controller.?.begin(binding, @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)), @import("../approvals/view/ai_host_secret_view.zig").palette());
        self.wake();
        return receipt;
    }
    fn validateHostSecret(raw: *anyopaque, binding: @import("../../../ai/host_secret_store.zig").Binding) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try self.validateHostContext(binding.context);
        if (!self.requestDisplayed() or self.cancelRef().isCancelled()) return error.ScopeChanged;
        const backend = if (self.execution().execution_backend) |*value| value else return error.HostSecretUnavailable;
        _ = try backend.validateSecret(binding.context, binding.handle, secretRequest(binding));
    }
    fn submitHostSecret(raw: *anyopaque, binding: @import("../../../ai/host_secret_store.zig").Binding, bytes: []const u8) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        try validateHostSecret(raw, binding);
        const backend = if (self.execution().execution_backend) |*value| value else return error.HostSecretUnavailable;
        const service = try backend.validateSecret(binding.context, binding.handle, secretRequest(binding));
        _ = try service.executionSecret(.{ .submit = .{ .request = secretRequest(binding), .bytes = bytes } });
    }
    fn cancelHostSecret(raw: *anyopaque, binding: @import("../../../ai/host_secret_store.zig").Binding) void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const previous = self.execution_host;
        defer self.execution_host = previous;
        if (self.attachedForTask(binding.context)) |backend| self.execution_host = backend;
        if (self.execution().execution_backend) |*backend| _ = backend.cancelSecret(binding.context, binding.handle, secretRequest(binding)) catch {};
    }
    fn pollHostSecret(self: *AiHost) void {
        const controller = if (self.secret_controller) |*value| value else return;
        if (controller.pending) |pending| {
            if (pending.submitted) if (self.execution().execution_backend) |*backend| {
                const snapshot = backend.observeSecret(pending.binding.context, pending.binding.handle, secretRequest(pending.binding)) catch null;
                if (snapshot) |facts| if (facts.owner.eql(pending.binding.handle) and facts.execution_id != null and facts.execution_id.?.eql(pending.binding.grant.execution_id) and facts.execution_fence == pending.binding.grant.fence and facts.execution_input_epoch == pending.binding.grant.input_epoch and (facts.grant == null or std.meta.eql(facts.grant.?, pending.binding.grant))) if (facts.input_receipt) |receipt| {
                    if (receipt.kind == .host_secret and receipt.stage == .consumed and receipt.wait_sequence == pending.binding.wait_sequence and receipt.input_sequence == pending.binding.input_sequence) controller.consumed(pending.binding) catch {};
                };
            };
        }
        controller.poll(@intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)));
        // The native secret collector has no callback: polled while a request is pending.
        if (controller.pending != null) self.wakeAt(16 * std.time.ns_per_ms);
    }
    fn deferAiCompletion(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context, owner: @import("../../../host/identity.zig").ContentOwner, operation: u64, turn: u64, completion: @import("../../../host/notification_host.zig").AiCompletion) !void {
        var pending: PendingAiCompletion = .{ .context = context, .owner = owner, .operation = operation, .turn = turn, .completion = completion };
        pending.detail_len = @min(completion.details.detail.len, pending.detail.len);
        while (pending.detail_len > 0 and !std.unicode.utf8ValidateSlice(completion.details.detail[0..pending.detail_len])) pending.detail_len -= 1;
        @memcpy(pending.detail[0..pending.detail_len], completion.details.detail[0..pending.detail_len]);
        pending.completion.details.detail = "";
        for (self.execution().pending_ai_completions.items) |*slot| if (slot.* == null) {
            slot.* = pending;
            return;
        };
        try self.execution().pending_ai_completions.append(self.execution().allocator, pending);
    }
    fn publishSettledAiCompletions(self: *AiHost) void {
        const notifications = process_state.process_notifications orelse return;
        const finish = if (self.execution().task_finish) |*value| value else return;
        for (self.execution().pending_ai_completions.items) |*slot| if (slot.*) |*pending| {
            const receipt = finish.receiptFor(pending.context) orelse continue;
            var completion = pending.completion;
            completion.details.detail = pending.detail[0..pending.detail_len];
            completion.resources_released = true; // Exact finish receipt requires real slot/input/reference settlement.
            if (receipt.remote_effect_unknown) {
                completion.result = .unverified;
                completion.final_answer = false;
            }
            notifications.activity.setForeground(@import("../../../platform/menu_bar.zig").active());
            notifications.publishAi(pending.owner, pending.operation, pending.turn, completion) catch {
                // The notification host refused it now: try again (a time, not a publication).
                self.wakeAt(250 * std.time.ns_per_ms);
                continue;
            };
            slot.* = null;
        };
    }

    fn decideTaskFinish(raw: *anyopaque, task: @import("../../../host/identity.zig").TaskId, revision: u64, decision: @import("../cards/view/ai_task_finish.zig").Decision) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const finish = if (self.execution().task_finish) |*value| value else return error.NotFound;
        try finish.decide(task, revision, decision);
        self.wake();
    }
    fn controlTaskFinish(raw: *anyopaque, task: @import("../../../host/identity.zig").TaskId, revision: u64, control: @import("../cards/view/ai_task_finish.zig").Control) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        // An input callback: the pass handles what it changed (LIFECYCLE.md §5.1).
        defer self.wake();
        const store = if (self.assistant_states) |value| value else return error.ConversationNotFound;
        const state = store.find(self.display_conversation orelse return error.ConversationNotFound) orelse return error.ConversationNotFound;
        _ = lookupLifecycleTask(self, state.conversation_id, task) orelse return error.ScopeChanged;
        const finish = if (self.execution().task_finish) |*value| value else return error.NotFound;
        try finish.control(task, revision, control);
        if (control == .stop) if (self.execution().request_host_context) |context| if (context.conversation_id.eql(state.conversation_id) and context.task_id.eql(task) and self.execution().thread_state.load(.acquire) == 1) {
            self.cancelRef().cancel();
            self.approvalsRef().stop();
            self.questionsRef().stop();
            self.execution().inventory_approval.stop();
            if (self.application_host) |app| app.cancelOwnedTask(task);
        };
        self.wake();
    }
    fn controlTaskFinishTarget(raw: *anyopaque, task: @import("../../../host/identity.zig").TaskId, revision: u64, target: @import("../../../host/identity.zig").SessionHandle, execution_id: @import("../../../host/identity.zig").ExecutionId) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const store = if (self.assistant_states) |value| value else return error.ConversationNotFound;
        const state = store.find(self.display_conversation orelse return error.ConversationNotFound) orelse return error.ConversationNotFound;
        const controller = lookupLifecycleTask(self, state.conversation_id, task) orelse return error.ScopeChanged;
        if (!controller.inBinding(target)) return error.TargetNotAuthorized;
        const finish = if (self.execution().task_finish) |*value| value else return error.NotFound;
        try finish.controlTarget(task, revision, target, execution_id);
        // This action changes one terminal's input ownership. Provider cancel,
        // Task finishing and other terminals are deliberately independent.
        self.wake();
    }
    pub fn takeoverTerminal(raw: *anyopaque, task: @import("../../../host/identity.zig").TaskId, target: @import("../../../host/identity.zig").SessionHandle, execution_id: @import("../../../host/identity.zig").ExecutionId) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        const controller = for (self.execution().lifecycle_controllers.items) |item| {
            if (item.authority.task_id.eql(task)) break item;
        } else return error.ScopeChanged;
        const store = if (self.assistant_states) |value| value else return error.ConversationNotFound;
        _ = store.findConversation(controller.authority.conversation_id) orelse return error.ConversationNotFound;
        const finish = if (self.execution().task_finish) |*value| value else return error.NotFound;
        try finish.controlCurrentTarget(task, target, execution_id);
        self.wake();
    }
    fn performExecutionAction(raw: *anyopaque, action: @import("../cards/view/ai_execution_result_view.zig").Action, target: @import("../../../ai/tool_results.zig").ExecutionActionTarget) !void {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        _ = lookupLifecycleTask(self, target.conversation_id, target.task_id) orelse return error.ScopeChanged;
        if (self.pending_execution_action != null) return error.OperationBusy;
        // Navigation can rebuild the containing transcript. Apply it at the
        // safe poll point, after this action's native event has returned.
        self.pending_execution_action = .{ .action = action, .target = target };
        self.wake();
    }
    fn applyExecutionAction(self: *AiHost) !void {
        const pending = self.pending_execution_action orelse return;
        self.pending_execution_action = null;
        const target = pending.target;
        const controller = lookupLifecycleTask(self, target.conversation_id, target.task_id) orelse return error.ScopeChanged;
        const app = self.application_host orelse return error.ContextUnavailable;
        if (!controller.inBinding(target.session)) return error.TargetNotAuthorized;
        const legacy = app.legacyForHandle(target.session) orelse return error.StaleSession;
        const tab = app.workspace.sessionTab(legacy) orelse return error.StaleSession;
        if (!tab.content_owner.eql(.{ .session = target.session }) or tab.generation != target.session.generation or tab.closing) return error.StaleSession;
        switch (pending.action) {
            .view_terminal => {
                const index = app.workspace.tabIndex(legacy) orelse return error.StaleSession;
                app.workspace.selectTab(index);
                self.collapse();
                if (tab.terminal) |view| self.cx.setFocus(if (view.terminal_surface) |surface| surface.root else view.root);
            },
            .stop => {
                const driver = self.execution().execution_driver orelse return error.ToolNotAvailable;
                const reference = target.reference();
                try driver.requestStopExecution(controller.authority, &reference);
            },
            .takeover => {
                const finish = if (self.execution().task_finish) |*value| value else return error.NotFound;
                try finish.controlCurrentTarget(target.task_id, target.session, target.execution_id);
            },
        }
        self.wake();
    }
    fn noticeTurn(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) ?*@import("../../../ai/conversation_turn.zig").Turn {
        const store = if (self.assistant_states) |value| value else return null;
        const state = store.findConversation(context.conversation_id) orelse return null;
        const displayed = self.display_conversation == state.id;
        const current = if (displayed) &self.current_turn else &state.current_turn;
        if (current.task_id) |task| if (task.eql(context.task_id)) return current;
        const history = if (displayed) &self.history else &state.history;
        for (history.items) |*message| if (message.turn) |*turn| if (turn.task_id) |task| if (task.eql(context.task_id)) return turn;
        return null;
    }
    fn attachedForTask(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context) ?*AiHost {
        const shared_host = self.shared_service orelse return null;
        for (shared_host.bridges.items) |bridge| {
            if (bridge.disposed) continue;
            const backend: *AiHost = @ptrCast(@alignCast(bridge.context));
            if (lookupLifecycleTask(backend, context.conversation_id, context.task_id) != null) return backend;
        }
        return null;
    }
    fn recordInputHandoff(self: *AiHost, context: @import("../../../ai/host_tools.zig").Context, target: @import("../../../host/identity.zig").SessionHandle, execution_id: ?@import("../../../host/identity.zig").ExecutionId) !void {
        const previous = self.execution_host;
        defer self.execution_host = previous;
        if (self.attachedForTask(context)) |backend| self.execution_host = backend;
        const controller = lookupLifecycleTask(self, context.conversation_id, context.task_id) orelse return;
        if (!controller.inBinding(target)) return;
        const turn = self.noticeTurn(context) orelse return error.TaskTurnNotFound;
        for (turn.host_notices.items) |notice| if (notice.target.eql(target) and std.meta.eql(notice.execution_id, execution_id)) return;
        var free: ?usize = null;
        for (self.execution().pending_host_notices.items, 0..) |item, index| if (item == null) {
            free = index;
            break;
        };
        if (free == null) try self.execution().pending_host_notices.append(self.execution().allocator, null);
        const slot = free orelse (self.execution().pending_host_notices.items.len - 1);
        const app = self.application_host orelse return error.ContextUnavailable;
        const label = if (app.legacyForHandle(target)) |legacy| if (app.workspace.sessionTab(legacy)) |tab| tab.titleSlice() else "终端" else "终端";
        var next: PendingHostNotice = .{ .context = context, .revision = try @import("../../../host/identity.zig").advance(@max(@as(u64, 1), self.execution().host_notice_revision)), .text = undefined, .len = 0 };
        next.len = (try std.fmt.bufPrint(&next.text, "你已接管终端「{s}」。此操作不会中断 AI 助手或正在运行的命令；需要中断命令时请按 Ctrl+C。AI 再次控制此终端需要重新申请权限。", .{label})).len;
        const text = try self.allocator.dupe(u8, next.content());
        errdefer self.allocator.free(text);
        try turn.appendNotice(self.allocator, .{ .revision = next.revision, .target = target, .execution_id = execution_id, .text = text }, @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)));
        self.execution().pending_host_notices.items[slot] = next;
        self.execution().host_notice_revision = next.revision;
        self.conversation_dirty = true;
        self.wake();
    }
    fn pendingInputNotices(self: *AiHost, conversation: @import("../../../host/identity.zig").ConversationId, buffer: []PendingHostNotice) []PendingHostNotice {
        var count: usize = 0;
        for (self.execution().pending_host_notices.items) |item| if (item) |notice| if (notice.context.conversation_id.eql(conversation) and count < buffer.len) {
            buffer[count] = notice;
            count += 1;
        };
        return buffer[0..count];
    }
    fn flushIdleHostNotices(self: *AiHost) !void {
        const store = if (self.assistant_states) |value| value else return;
        for (self.execution().pending_host_notices.items) |*item| if (item.*) |notice| {
            if (self.execution().thread_state.load(.acquire) != 0) if (self.execution().request_host_context) |context| if (context.conversation_id.eql(notice.context.conversation_id)) continue;
            const state = store.findConversation(notice.context.conversation_id) orelse continue;
            const destination = store.wireHistoryFor(state.id, self.display_conversation, &self.wire_history) orelse continue;
            var messages: std.ArrayList(ai_provider.Message) = .empty;
            defer messages.deinit(self.allocator);
            try messages.appendSlice(self.allocator, destination.messages);
            const content = try std.json.Stringify.valueAlloc(self.allocator, .{ .host_input_handoff = true, .conversation_id = notice.context.conversation_id, .task_id = notice.context.task_id, .notice_revision = notice.revision, .text = notice.content() }, .{});
            defer self.allocator.free(content);
            try messages.append(self.allocator, .{ .role = .user, .content = content });
            const next = try @import("../../../ai/wire_history.zig").History.copy(self.allocator, messages.items, "");
            destination.deinit();
            destination.* = next;
            item.* = null;
        };
    }
    fn consumeInputHandoffs(self: *AiHost) void {
        if (self.application_host) |app| {
            var buffer: [128]application_host_mod.OwnedInputEvent = undefined;
            for (app.drainOwnedInputEvents(&buffer)) |event| if (event.phase == .released) self.recordInputHandoff(event.context, event.handle, event.execution_id) catch |err| self.setFeedback(@errorName(err));
        }
        if (self.execution().task_finish) |*finish| {
            var buffer: [128]@import("../cards/view/ai_task_finish.zig").ControlEvent = undefined;
            for (finish.drainControlEvents(&buffer)) |event| if (event.phase == .released) self.recordInputHandoff(event.context, event.handle, event.execution_id) catch |err| self.setFeedback(@errorName(err));
        }
    }
    fn taskFinishGates(raw: *anyopaque, context: @import("../../../ai/host_tools.zig").Context) ?@import("../cards/view/ai_task_finish.zig").Gates {
        const self: *AiHost = @ptrCast(@alignCast(raw));
        var released = false;
        for (self.execution().released_task_contexts.items) |value| if (value.conversation_id.eql(context.conversation_id) and value.task_id.eql(context.task_id)) {
            released = true;
            break;
        };
        if (!released) return null;
        if (self.execution().request_host_context) |current| if (current.task_id.eql(context.task_id)) {
            const quiet = self.execution().tool_bridge.quiescent() orelse return null;
            return .{ .pending_tool_slots = @intFromBool(!quiet or self.execution().worker_thread != null or self.execution().thread_state.load(.acquire) != 0), .pending_approvals = @intFromBool(self.approvalsRef().snapshot() != null or self.execution().inventory_approval.snapshot() != null or self.execution().tool_bridge.pendingApproval() != null or self.questionsRef().snapshot() != null), .active_references = @intFromBool(self.execution().request_attachments != null or self.execution().request_images != null), .resource_references_transferred = released };
        };
        return .{ .resource_references_transferred = true };
    }
    /// A finish card whose model has ended and whose settlement is not recorded yet.
    fn settlingAfterModel(self: *AiHost) bool {
        const finish = if (self.execution().task_finish) |*value| value else return false;
        for (finish.tasks.items) |task| if (task.model_ended and task.receipt == null) return true;
        return false;
    }
    fn tickTaskFinish(self: *AiHost) bool {
        const finish = if (self.execution().task_finish) |*value| value else return false;
        const app = self.application_host orelse return false;
        const source: ?@import("../cards/view/ai_task_finish.zig").ExecutionSource = if (self.execution().execution_driver) |driver| @import("../cards/view/ai_task_finish.zig").ExecutionSource.fromDriver(driver) else null;
        const pending = finish.tick(app, source, .{ .context = self, .read = taskFinishGates }) catch |err| {
            self.setFeedback(@errorName(err));
            return true;
        };
        if (self.requestDisplayed()) if (self.task_finish_holder) |holder| if (self.assistant_states) |store| if (self.display_conversation) |id| if (store.find(id)) |state| {
            const buffer = self.allocator.alloc(@import("../cards/view/ai_task_finish.zig").Snapshot, finish.tasks.items.len) catch return true;
            defer self.allocator.free(buffer);
            const snapshots = finish.snapshotsForConversation(state.conversation_id, buffer) catch &.{};
            const has_visible = for (snapshots) |snapshot| {
                if (snapshot.visible) break true;
            } else false;
            const awaiting_decision = self.approvalsRef().snapshot() != null or self.execution().tool_bridge.pendingApproval() != null or self.questionsRef().snapshot() != null;
            holder.setDisplay(if (has_visible and !awaiting_decision) .flex else .none);
            for (self.task_finish_views.items) |entry| {
                const visible = for (snapshots) |snapshot| {
                    if (snapshot.context.task_id.eql(entry.task) and snapshot.visible) break snapshot;
                } else null;
                entry.view.update(visible) catch {};
            }
            for (snapshots) |snapshot| {
                if (!snapshot.visible) continue;
                const existing = for (self.task_finish_views.items) |entry| {
                    if (entry.task.eql(snapshot.context.task_id)) break true;
                } else false;
                if (existing) continue;
                const view = blk: {
                    const view = @import("../cards/view/ai_task_finish.zig").View.mount(self.cx, self.contentScope() orelse break :blk null, .{ .context = self, .on_decision = decideTaskFinish, .on_control = controlTaskFinish, .on_control_target = controlTaskFinishTarget }) catch break :blk null;
                    self.task_finish_views.append(self.allocator, .{ .task = snapshot.context.task_id, .view = view }) catch break :blk null;
                    holder.appendChild(self.allocator, view.root) catch break :blk null;
                    break :blk view;
                } orelse continue;
                view.update(snapshot) catch {};
            }
        };
        return pending;
    }

    fn wireHistoryFailureLabel(err: anyerror) []const u8 {
        return if (err == error.ToolTranscriptLimit) "对话上下文已达上限，请新建 AI 会话继续" else "无法保留完整对话上下文，请新建 AI 会话继续";
    }

    fn retainWireHistory(self: *AiHost, completed: bool) !void {
        const run = self.managerRef().tool_run orelse return;
        if (run.turn_id != self.managerRef().turn_id) return;
        if (run.compaction_failure != null and run.round_index == 0) return;
        const store = if (self.assistant_states) |value| value else return;
        const conversation = store.find(self.execution().request_conversation orelse return) orelse return;
        if (run.tool_table) |table| {
            const context = table.host_context orelse return error.InvalidHostAuthority;
            if (!context.conversation_id.eql(conversation.conversation_id)) return error.ToolOwnerChanged;
        } else {
            const owner = self.execution().request_owner orelse return;
            if (!owner.eql(run.scope.owner)) return error.ToolOwnerChanged;
        }
        const destination = store.wireHistoryFor(self.execution().request_conversation orelse return, self.display_conversation, &self.wire_history) orelse return;
        // Only the real completed provider answer is appended. Display cards,
        // recovery markers and model claims never become synthetic tool results.
        var next = @import("../../../ai/wire_history.zig").History.copy(self.allocator, run.messages.items, if (completed) self.managerRef().round_text.items else "") catch |err| {
            destination.failure = err;
            return err;
        };
        const usage = @import("../../../ai/context_usage.zig");
        self.execution().request_usage_fixed = usage.Fixed.capture(run.request) catch .{};
        if (self.managerRef().last_context_usage) |sample| if (self.execution().native_binding) |binding| {
            if (sample.fixed.fingerprint == self.execution().request_usage_fixed.fingerprint and sample.matches(next.messages)) next.usage = .{ .sample = sample, .model_key = usage.modelKey(binding.config) };
        };
        if (next.usage == null) if (destination.usage) |previous| if (self.execution().native_binding) |binding| {
            if (previous.model_key == usage.modelKey(binding.config) and previous.sample.fixed.fingerprint == self.execution().request_usage_fixed.fingerprint and previous.sample.matches(next.messages)) next.usage = previous;
        };
        destination.deinit();
        destination.* = next;
        if (self.requestDisplayed()) if (self.shared_service) |shared_host| if (shared_host.service.store.find(conversation.conversation_id)) |record| {
            self.display_content_revision = record.content_revision;
        };
    }

    fn restoreCompactionInput(self: *AiHost) !void {
        const store = if (self.assistant_states) |value| value else return;
        const id = self.execution().request_conversation orelse return;
        const saved = store.find(id) orelse return;
        if (saved.closed) return;
        const displayed = self.requestDisplayed();
        const question = (if (displayed) self.last_user_text else saved.last_user_text) orelse return;
        const previous = if (displayed) self.prompt.peek() else saved.draft orelse "";
        const restored = if (previous.len == 0) try self.allocator.dupe(u8, question) else if (std.mem.endsWith(u8, previous, question)) try self.allocator.dupe(u8, previous) else try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ previous, question });
        if (displayed) {
            defer self.allocator.free(restored);
            self.prompt.set(restored);
        } else {
            if (saved.draft) |old| self.allocator.free(old);
            saved.draft = restored;
        }
        // Never overwrite attachments added while the request was in flight.
        // Original bundles remain on the failed user message in every case.
        const attachments = if (displayed) self.last_user_attachments else saved.last_user_attachments;
        if (attachments) |bundle| if (store.attachmentDraftFor(id)) |draft| {
            if (draft.items.items.len == 0 and draft.pending.items.len == 0 and draft.candidates.items.len == 0) try draft.restore(&bundle);
            if (displayed) if (self.attachments_view) |view| try view.update(draft);
        };
        const images = if (displayed) self.last_user_images else saved.last_user_images;
        if (images) |bundle| if (store.imageDraftFor(id)) |draft| {
            if (draft.items.items.len == 0) try draft.restore(&bundle);
            if (displayed) if (self.images_view) |view| try view.update(draft);
        };
        if (displayed) self.promptChanged(self.prompt.peek());
    }

    fn finalizeWorker(self: *AiHost, worker_state: u8) void {
        const state = worker_state;
        if (self.execution().worker_thread) |thread| {
            thread.join();
            self.execution().worker_thread = null;
        }
        if (self.execution().recording_access) |*access| access.deinit();
        self.execution().recording_access = null;
        self.retainWireHistory(state == 2 and self.managerRef().saw_done) catch |err| {
            self.execution().failure_label = wireHistoryFailureLabel(err);
            if (self.workspace) |workspace| workspace.status(self.execution().failure_label);
        };
        const retained_results = self.retainToolResults() catch |err| failed: {
            self.execution().failure_label = @errorName(err);
            if (self.workspace) |workspace| workspace.status(self.execution().failure_label);
            break :failed false;
        };
        if (retained_results) self.conversation_dirty = true;
        if (self.execution().request_attachments) |*bundle| bundle.deinit();
        self.execution().request_attachments = null;
        if (self.execution().request_images) |*bundle| bundle.deinit();
        self.execution().request_images = null;
        self.execution().request_image_refs.clearRetainingCapacity();
        if (process_state.process_notifications) |notifications| if (self.execution().request_operation_id) |operation| if (self.execution().request_content_owner) |owner| {
            var final_answer = false;
            for (self.managerRef().cards.cards.items) |card| if (card == .text and card.text.len > 0) {
                final_answer = true;
                break;
            };
            const uncertain = if (self.managerRef().tool_run) |run| uncertain_result: {
                if (run.uncertain) break :uncertain_result true;
                for (run.records.items) |record| if (record.generic_results) |results| {
                    for (results) |result| if (result.receipt.remote_effect_unknown or result.status == .outcome_unknown) break :uncertain_result true;
                };
                break :uncertain_result false;
            } else false;
            if (uncertain) if (self.notification_window) |window| {
                // Only a real remote-effect receipt grants this escalation;
                // ordinary provider/read failures remain in the transcript.
                const effect_unknown = if (self.managerRef().tool_run) |run| check: {
                    for (run.records.items) |record| {
                        if (record.outcome) |outcome| for (outcome.targets) |target| {
                            if (target.remote_effect_unknown) break :check true;
                        };
                        if (record.generic_results) |results| for (results) |result| {
                            if (result.receipt.remote_effect_unknown) break :check true;
                        };
                    }
                    break :check false;
                } else false;
                if (effect_unknown) _ = notifications.publish(.{
                    .definition_id = "host.ai_unknown",
                    .owner = .{ .window_id = @backingInt(window), .content = owner },
                    .operation_id = operation,
                    .attempt_id = self.managerRef().turn_id,
                    .event_revision = 1,
                    .phase = .outcome_unknown,
                    .severity = .warning,
                    .title = "AI 执行结果需要核查",
                    .detail = "已有远端操作派发，当前无法确认其实际效果。请回到原执行卡核查。",
                    .attention = .{ .kind = .outcome_unknown, .requires_action = true, .time_sensitive = true },
                    .actions = &.{.{ .kind = .locate_owner, .label = "查看对话" }},
                }) catch |err| {
                    applog.warn(.app, "unknown effect notification: {s}", .{@errorName(err)});
                };
            };
            const resources_released = if (self.managerRef().tool_run) |run| released: {
                for (run.records.items) |record| {
                    if (record.outcome) |outcome| {
                        for (outcome.targets) |target| if (!target.local_released) break :released false;
                    } else if (record.generic_results) |results| {
                        for (results) |result| if (!result.receipt.local_released) break :released false;
                    } else if (record.host_result) |result| {
                        if (!result.receipt.local_released) break :released false;
                    } else if (record.dispatched) break :released false;
                }
                break :released true;
            } else true;
            const completion: @import("../../../host/notification_host.zig").AiCompletion = .{ .result = if (uncertain) .unverified else if (state == 4) .cancelled else if (state == 2 and self.managerRef().saw_done) .succeeded else .failed, .resources_released = resources_released, .final_answer = state == 2 and self.managerRef().saw_done and final_answer and !uncertain, .details = .{ .detail = if (state == 3) self.execution().failure_label else "" } };
            if (self.execution().request_host_context) |context| {
                self.deferAiCompletion(context, owner, operation, self.managerRef().turn_id, completion) catch |err| {
                    if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
                };
            } else {
                notifications.activity.setForeground(@import("../../../platform/menu_bar.zig").active());
                notifications.publishAi(owner, operation, self.managerRef().turn_id, completion) catch |err| {
                    if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
                };
            }
            self.execution().request_operation_id = null;
        };
        if (self.managerRef().tool_run) |run| {
            if (self.workspace) |workspace| for (run.records.items) |record| {
                if (!std.mem.eql(u8, record.name, "run_command")) continue;
                if (record.outcome) |outcome| for (outcome.targets) |target| {
                    if (target.remote_effect_unknown) {
                        if (self.execution().tool_bridge.sourceOwner(target.session_id)) |original| workspace.receiveGroupRemoteEffectUnknown(original);
                    }
                };
            };
            for (run.messages.items) |message| if (message.tool_call_id) |id| {
                @import("../../../ai/tool_trace.zig").emit(.{ .event = "tool_feedback", .turn_id = run.turn_id, .round_index = run.round_index, .call_id = id, .content = message.content });
            };
        }
        // A producer may append between the poll's first drain and its terminal
        // release-store. Join, drain again, and empty the channel before reuse.
        self.consumeLiveOutput() catch |err| {
            self.execution().failure_label = @errorName(err);
        };
        self.consumeStepEvents() catch {};
        const completed_turn = if (self.requestDisplayed()) &self.current_turn else &(self.assistant_states.?.find(self.execution().request_conversation orelse return) orelse return).current_turn;
        completed_turn.finishSegment(@intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)));
        completed_turn.ended_at_ms = @intCast(@max(0, @import("../../../platform/realtime.zig").milliseconds(self)));
        for (completed_turn.steps.items) |*step| if (step.ended_ms == null) {
            step.phase = if (state == 4) .cancelled else .failed;
            step.ended_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        };
        completed_turn.elapsed_ms = @as(u64, @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms))) -| completed_turn.started_mono_ms;
        completed_turn.request_count = (if (self.execution().answer_only) completed_turn.request_count orelse 0 else @as(u64, 0)) +| self.execution().request_stats.request_count;
        if (self.execution().request_stats.usage_reported and (state == 2 or state == 4) and (!self.execution().answer_only or completed_turn.input_tokens != null)) {
            completed_turn.input_tokens = (if (self.execution().answer_only) completed_turn.input_tokens orelse 0 else @as(u64, 0)) +| self.execution().request_stats.input_tokens;
            completed_turn.output_tokens = (if (self.execution().answer_only) completed_turn.output_tokens orelse 0 else @as(u64, 0)) +| self.execution().request_stats.output_tokens;
        } else {
            completed_turn.input_tokens = null;
            completed_turn.output_tokens = null;
        }
        if (completed_turn.thinking.items.len > 0 and completed_turn.thinking_ended_ms == null) completed_turn.thinking_ended_ms = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        if (self.allocator.dupe(u8, if (state == 2) self.managerRef().round_text.items else "")) |answer| {
            self.allocator.free(completed_turn.answer);
            completed_turn.answer = answer;
        } else |_| {}
        const completed_wire = if (self.requestDisplayed()) &self.wire_history else &self.assistant_states.?.find(self.execution().request_conversation.?).?.wire_history;
        if (@import("../../../ai/wire_history.zig").History.copy(self.allocator, completed_wire.messages, "")) |after| {
            completed_turn.after.deinit();
            completed_turn.after = after;
        } else |_| {}
        self.execution().stream_mailbox.discard();
        self.execution().thread_state.store(0, .release);
        if (self.execution().request_host_context) |context| {
            const recorded = for (self.execution().released_task_contexts.items) |prior| {
                if (prior.task_id.eql(context.task_id)) break true;
            } else false;
            if (!recorded) self.execution().released_task_contexts.append(self.execution().allocator, context) catch |err| self.setFeedback(@errorName(err));
            if (self.execution().task_finish) |*finish| finish.modelEnded(context, if (state == 4) .cancelled else if (state == 2 and self.managerRef().saw_done) .completed else .failed) catch |err| self.setFeedback(@errorName(err));
        }
        if (self.assistant_states) |store| if (self.execution().request_conversation) |id| {
            if (store.find(id)) |saved| store.setPhase(saved, if (state == 4) .stopped else if (state == 2) .done else .failed);
        };
        self.execution().recovery_failed = state == 3;
        const compaction_interrupted = if (self.managerRef().tool_run) |run| run.compaction_failure != null else false;
        if ((state == 3 or state == 4) and compaction_interrupted) {
            self.restoreCompactionInput() catch |err| applog.warn(.ai, "restore compaction draft: {s}", .{@errorName(err)});
        }
        if (state == 3) {
            if (self.execution().request_text) |owned| {
                self.allocator.free(owned);
                self.execution().request_text = null;
            }
            self.clearRequestHistory();
            self.consumeResult();
            if (self.requestDisplayed()) self.refresh(self.execution().failure_label);
        } else {
            self.consumeResult();
            if (state == 4 and self.requestDisplayed()) self.refresh("AI 已停止");
        }
        if (self.assistant_states) |store| if (self.execution().request_conversation) |id| {
            if (store.find(id)) |saved| if (saved.closed) {
                store.remove(id);
                self.execution().request_conversation = null;
            };
        };
        // Completion of a closed/background conversation also releases the
        // shared request slot. Refresh the displayed composer so its send
        // control does not retain the previous request's hidden/busy state.
        if (!self.requestDisplayed()) self.refresh("AI 助手");
    }

    /// Whether the conversation waiting for confirmation is on screen (same facts as the window's
    /// `result_presented` for AI): window active, the request's conversation displayed in an open,
    /// expanded assistant panel.
    fn approvalSourceShown(self: *AiHost) bool {
        return self.cx.window_active and self.requestDisplayed() and self.controller.model.visible and self.controller.model.expanded;
    }

    fn observeApprovalNotification(self: *AiHost) void {
        const notifications = process_state.process_notifications orelse return;
        const approval = self.execution().tool_bridge.pendingApproval();
        const host_approval = self.approvalsRef().snapshot();
        const inventory_approval = self.execution().inventory_approval.snapshot();
        const question = self.questionsRef().snapshot();
        const sequence: ?u64 = if (question) |pending| pending.ticket.sequence | (@as(u64, 1) << 61) else if (host_approval) |pending| pending.sequence | (@as(u64, 1) << 63) else if (inventory_approval) |pending| pending.ticket.sequence | (@as(u64, 1) << 62) else if (approval) |pending| pending.sequence else null;
        if (self.execution().approval_notification) |old| {
            if (sequence != null and self.execution().request_operation_id == old.operation_id and sequence.? == old.attempt_id) {
                // Published while the reader was looking at this conversation, the host judged the
                // source visible and did not list it. Once its tab goes to the background (or the
                // assistant / window is no longer shown), publish a new revision so the host
                // re-evaluates the same pending fact under the existing rules.
                const listed = if (notifications.coordinator.factFor(old)) |record| record.listed else false;
                if (listed or self.approvalSourceShown()) return;
                var again = old;
                again.event_revision += 1;
                _ = notifications.publish(again) catch return;
                self.execution().approval_notification = again;
                return;
            }
            var resolved = old;
            resolved.event_revision += 1;
            resolved.phase = .succeeded;
            resolved.attention.resolved = true;
            resolved.title = "AI 确认等待已结束";
            _ = notifications.publish(resolved) catch return;
            self.execution().approval_notification = null;
        }
        const pending_sequence = sequence orelse return;
        const operation = self.execution().request_operation_id orelse return;
        const owner = self.execution().request_content_owner orelse return;
        const window = self.notification_window orelse return;
        const event: @import("../../../host/notification_coordinator.zig").NotificationEvent = .{
            .definition_id = "host.ai_attention",
            .owner = .{ .window_id = @backingInt(window), .content = owner },
            .operation_id = operation,
            .attempt_id = pending_sequence,
            .event_revision = 1,
            .phase = .accepted,
            .severity = .warning,
            .title = "AI 任务正在等待确认",
            .detail = "任务需要你在原对话中确认后才能继续。",
            .attention = .{ .kind = .task_blocked, .requires_action = true, .time_sensitive = true },
            .actions = &.{.{ .kind = .locate_owner, .label = "查看对话" }},
        };
        _ = notifications.publish(event) catch return;
        self.execution().approval_notification = event;
    }

    /// UI-thread poll: one after-layout hook, self-scheduling only while a
    /// request is in flight.
    /// What the frame gate compares (LIFECYCLE.md §5.1). O(1): a few revisions, flags and rects.
    fn gateFacts(self: *AiHost) @import("frame_gate.zig").Facts {
        var layout = std.hash.Wyhash.init(0);
        const nodes = [_]?*ui.Node{ if (self.workspace) |workspace| workspace.terminal_area else null, self.card_box, self.content_node, if (self.composer_node) |node| node.parent else null };
        for (nodes) |candidate| if (candidate) |node| {
            const r = node.globalRect();
            std.hash.autoHash(&layout, .{ @as(u32, @bitCast(r.x)), @as(u32, @bitCast(r.y)), @as(u32, @bitCast(r.w)), @as(u32, @bitCast(r.h)) });
        };
        const phase = if (self.card) |card| card.phase() else null;
        return .{
            .publication = @import("../../../ai/publication.zig").revision(),
            .environment = @import("../../../host/environment.zig").revision(),
            .config = if (self.runtime_config) |runtime| runtime.value.config_revision else 0,
            .theme = self.theme_watch.pending(),
            .now_ns = @import("../../../platform/realtime.zig").monotonicNs(),
            .card_phase = if (phase) |value| @intFromEnum(value) +% 1 else 0,
            .card_flying = if (phase) |value| value == .expanding or value == .collapsing else false,
            .layout = layout.final(),
            .focus = if (self.cx.focus_manager.getFocused()) |node| @intFromPtr(node) else 0,
            .window_active = self.cx.window_active,
        };
    }
    /// A frame without a pass: only what is per frame by nature (LIFECYCLE.md §5.1 “逐帧”): the
    /// tail follow while it glides, while the reader scrolls, or when the content height moved under
    /// it. Nothing else of the AI runs (a child dialog's test ids come from the `IdSpace` its Scope
    /// mounts under, and session phases / bound count are published by the store, not walked here).
    fn frameOnly(self: *AiHost) ui.AfterLayoutResult {
        const budget = &@import("../../../shared/ui/surface/lifecycle_budget.zig").counters;
        if (self.tail_follow) |*follow| {
            const content_h = follow.scroll.content.globalRect().h;
            if (self.follow_busy or follow.scroll.state.input_serial != follow.input_serial or content_h != self.follow_content_h) {
                budget.ai_frame_steps += 1;
                self.stepFollow(follow);
            }
        }
        return .done;
    }
    fn stepFollow(self: *AiHost, follow: *@import("../pane/view/ai_tail_follow.zig").Follow) void {
        self.follow_content_h = follow.scroll.content.globalRect().h;
        self.follow_busy = false;
        if ((self.attachments_view == null or !self.attachments_view.?.isPreviewOpen()) and (self.images_view == null or !self.images_view.?.isPreviewOpen())) {
            if (follow.updateAt(self.cx.frame_time_ms)) {
                self.follow_busy = true;
                self.wake();
            }
        }
        if (self.new_messages) |hint| hint.setShown(follow.hintShown());
    }
    /// The execution host's bridges have work only their pump observes: pump again at that time.
    fn wakeForBridges(self: *AiHost, execution_host: *AiHost) void {
        const now: i64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        for ([_]*@import("../tools/host/ai_tools.zig").Bridge{ &execution_host.tool_bridge, &execution_host.execution_bridge }) |bridge| if (bridge.pumpDueMs()) |due| {
            self.wakeAt(@as(u64, @intCast(@max(1, due - now))) * std.time.ns_per_ms);
        };
    }

    pub const PollHook = struct {
        host: *AiHost,

        /// Registers `host`'s frame hook until `scope` is disposed, together with its rest probe
        /// (lifecycle_budget: whether its next frame would run a pass).
        pub fn install(host: *AiHost, scope: *ui.Scope) !void {
            // The frame gate reads the watch even when the conversation has been unmounted.
            try host.theme_watch.bind(host.cx, scope);
            const hook = try host.allocator.create(PollHook);
            hook.* = .{ .host = host };
            host.cx.addAfterLayoutHook(hook, PollHook.run) catch |err| {
                host.allocator.destroy(hook);
                return err;
            };
            const budget = @import("../../../shared/ui/surface/lifecycle_budget.zig");
            budget.addRestProbe(.{ .context = hook, .state = restState }) catch |err| {
                host.cx.removeAfterLayoutHook(hook);
                host.allocator.destroy(hook);
                return err;
            };
            scope.onCleanup(PollHook, hook, PollHook.cleanup) catch |err| {
                hook.cleanup();
                return err;
            };
        }

        pub fn cleanup(self: *PollHook) void {
            @import("../../../shared/ui/surface/lifecycle_budget.zig").removeRestProbe(self);
            self.host.cx.removeAfterLayoutHook(self);
            self.host.allocator.destroy(self);
        }

        /// Whether the next frame would run a pass (an input changed since the last one: a
        /// publication, the environment, a rerun request, the card in flight, …: the gate's reason),
        /// and how far off the deadline a step asked for is.
        fn restState(ctx: *anyopaque) @import("../../../shared/ui/surface/lifecycle_budget.zig").RestState {
            const self: *PollHook = @ptrCast(@alignCast(ctx));
            const host = self.host;
            const facts = host.gateFacts();
            return .{
                .due = if (host.gate.due(facts)) |reason| @tagName(reason) else null,
                .deadline_in_ns = if (host.gate.deadline_ns) |at| at - facts.now_ns else null,
            };
        }

        pub fn run(ctx: *anyopaque, _: u8, last_round: bool) ui.AfterLayoutResult {
            const self: *PollHook = @ptrCast(@alignCast(ctx));
            const host = self.host;
            const budget = &@import("../../../shared/ui/surface/lifecycle_budget.zig").counters;
            budget.ai_hook_runs += 1;
            const started = @import("../../../platform/realtime.zig").monotonicNs();
            var passed = true;
            defer {
                const spent: u64 = @intCast(@max(0, @import("../../../platform/realtime.zig").monotonicNs() - started));
                if (passed) budget.ai_pass_ns += spent else budget.ai_idle_ns += spent;
            }
            // LIFECYCLE.md §5.1: the pass runs only on a frame where one of its inputs changed (and
            // in that frame's later layout rounds). Every other frame does the per-frame work only.
            const frame = host.cx.frame_count;
            if (!host.gate.running(frame)) {
                const facts = host.gateFacts();
                const reason = host.gate.due(facts) orelse {
                    passed = false;
                    return host.frameOnly();
                };
                host.gate.begin(facts, frame);
                budget.ai_passes += 1;
                budget.ai_pass_reasons[@intFromEnum(reason)] += 1;
            }
            budget.ai_pass_rounds += 1;
            // Measure the composer area against the layout that just finished, before this pass
            // changes the queue / decision panel (those changes lay out again and come back here).
            const composer_area_changed = host.layoutComposerArea();
            // LIFECYCLE.md §4: commit the presented state before this frame changes the tree.
            host.updatePresentation();
            if (host.shared_service) |shared_host| {
                shared_host.pump() catch |err| host.setFeedback(@errorName(err));
                // A runner's progress is published by its worker and its journal write; only a
                // persistence failure's retry is a time (5 s back-off).
                for (shared_host.service.runners.items) |runner| {
                    const delay = runner.persistenceRetryDelayNs();
                    if (delay != 0) host.wakeAt(delay);
                }
            }

            if (host.assistant_states) |store| {
                if (host.conversation_titles.poll(store)) {
                    if (host.last_user_text == null and host.history.items.len == 0) host.conversation_dirty = true;
                    if (host.sessions_view) |view| if (view.open.peek()) {
                        host.list_requested = true;
                    };
                }
            }
            host.processQueueAction() catch |err| {
                if (host.pending_view) |view| view.fail(@errorName(err));
            };
            host.updatePending() catch |err| host.setFeedback(@errorName(err));
            host.processChildren() catch |err| host.setFeedback(@errorName(err));
            host.processConversationActions();
            host.updateCloseConfirmation() catch |err| host.setFeedback(@errorName(err));
            host.processMessageAction() catch |err| host.setFeedback(@errorName(err));
            host.syncDock();
            host.openRequestedSettings();
            var composer_resized = false;
            if (host.composer) |composer| {
                // The attachment header row (Textarea `header_visible`) shows only while there
                // are attachments, and while a candidate's preview is pending: the view dismisses
                // its preview whenever an ancestor is hidden.
                const shown = if (host.attachments_view) |view| view.height() > 0 or view.candidate != null or view.pending_candidate != null else false;
                if (composer.setHeaderShown(shown)) composer_resized = true;
            }
            if (host.application_host) |application| {
                host.execution().tool_bridge.pump(application);
                if (host.transcript_images) |store| {
                    if (store.tick(application)) host.conversation_dirty = true;
                    // A remote image read is observed through its SSH execution snapshot only.
                    if (store.busy()) host.wakeAt(16 * std.time.ns_per_ms);
                }
                host.execution().execution_bridge.pump(application);
                host.wakeForBridges(host.execution());
            }
            if (host.execution().request_host_context) |context| host.validateHostContext(context) catch |err| {
                // A pending handoff closes new dispatch. Its already approved
                // lifecycle call must retain its permit while children drain.
                if (err != error.TransitionPending and !host.committedHandoffPending(context)) {
                    host.approvalsRef().stop();
                    host.questionsRef().stop();
                    host.execution().inventory_approval.stop();
                }
            };
            host.observeApprovalNotification();
            if (host.execution().thread_state.load(.acquire) == 1) if (host.assistant_states) |store| if (host.execution().request_conversation) |id| {
                if (store.find(id)) |state| store.setPhase(state, if (host.execution().tool_bridge.pendingApproval() != null or host.approvalsRef().snapshot() != null or host.execution().inventory_approval.snapshot() != null or host.questionsRef().snapshot() != null) .approval else .running);
            };
            composer_resized = (host.updateComposerInteraction() catch false) or composer_resized;
            host.pollHostSecret();
            const colors = app_theme.current();
            if (host.theme_watch.take()) {
                host.painted_colors = colors;
                host.refresh("AI 助手");
            }
            const previous_owner = host.display_owner;
            host.applyExecutionAction() catch |err| host.setFeedback(@errorName(err));
            // An untouched terminal does not need AI history. Explicit AI
            // entry points initialize it; existing/background owners keep syncing.
            if (host.shared_service != null or host.controller.model.visible) host.syncOwner() catch {};
            host.applyVerification() catch |err| host.setFeedback(@errorName(err));
            host.pumpAttachments() catch |err| host.refresh(@errorName(err));
            host.pumpImages() catch |err| host.refresh(@errorName(err));
            if (host.remote_picker) |picker| {
                picker.safeTick() catch |err| host.refresh(@errorName(err));
                if (picker.open_state and host.display_owner != null and picker.owner != null and !picker.owner.?.eql(host.display_owner.?)) picker.close();
                if (picker.open_state) if (host.attachment_preview_holder) |holder| holder.setDisplay(.flex);
            }
            if (previous_owner != null and host.display_owner != null and !@import("../../../ai/tool_scope.zig").Owner.eql(previous_owner.?, host.display_owner.?)) host.refresh("AI · 当前助手");
            if (host.runtime_config) |runtime| if (host.painted_config_revision != runtime.value.config_revision) {
                host.painted_config_revision = runtime.value.config_revision;
                host.composer_hash = null;
                host.refresh("AI 助手");
            };
            host.refreshComposer() catch |err| {
                // A composer failure changes feedback, not transcript content.
                // Rebuilding here retries the same error in every layout round.
                host.setFeedback(@errorName(err));
            };
            host.consumeLiveOutput() catch |err| {
                host.cancelRef().cancel();
                host.refresh(@errorName(err));
            };
            host.consumeStepEvents() catch |err| host.refresh(@errorName(err));
            host.syncApprovalSteps();
            const state = host.execution().thread_state.load(.acquire);
            if (state >= 2) host.finalizeWorker(state);
            host.applyRecovery();
            const settlement_pending = host.tickTaskFinish();
            host.consumeInputHandoffs();
            host.flushIdleHostNotices() catch |err| host.setFeedback(@errorName(err));
            host.publishSettledAiCompletions();
            // As in `pumpAttached`: only a finish card whose model ended waits on a time.
            if (settlement_pending and host.settlingAfterModel()) host.wakeAt(33 * std.time.ns_per_ms);
            host.updateLauncher();
            host.updateMotionProbe();
            if (host.recoveryVisible()) {
                const seconds = (host.managerRef().cooldownRemainingMs() + 999) / 1000;
                if (seconds != host.recovery_cooldown_seconds) {
                    host.recovery_cooldown_seconds = seconds;
                    host.conversation_dirty = true;
                }
                if (seconds != 0) host.wakeAt(1000 * 1_000_000);
            }
            composer_resized = composer_area_changed or composer_resized;
            const rebuild = host.conversation_dirty;
            if (rebuild) {
                host.conversation_dirty = false;
                const snap = host.controller.snapshot(content_snapshot_origin, content_snapshot_region);
                host.rebuildConversation(&snap);
            }
            const live_updated = if (!rebuild) host.refreshLiveMarkdown() catch false else false;
            const bubbles_resized = host.resizeConversationBubbles();
            // The reader's captured state goes back onto a transcript that is built and laid out.
            const restoring = if (!rebuild and !bubbles_resized) host.stepViewRestore() else false;
            if (host.tail_follow) |*follow| {
                // A reply arriving while the reader is away from the end lights the “新消息” hint.
                follow.noteReplies(host.history.items.len +% host.live_output_serial, false);
                if (!rebuild and !live_updated and !composer_resized and !bubbles_resized and !restoring) {
                    host.stepFollow(follow);
                } else if (follow.following) {
                    // Content changed this round, so following waits for a settled layout (the
                    // frame-only path follows on the next frame: the content height changed).
                    host.follow_busy = true;
                    host.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
                }
            }
            if (host.new_messages) |hint| hint.setShown(if (host.tail_follow) |follow| follow.hintShown() else false);
            const result: ui.AfterLayoutResult = if (rebuild or live_updated or composer_resized or bubbles_resized or restoring) .needs_layout else .done;
            // A frame was requested during the pass (a step changed what an earlier step reads; the
            // old loop re-ran every step on that frame): run the pass again on it.
            if ((result == .done or last_round) and host.cx.needs_redraw) host.gate.rerun = true;
            return result;
        }
    };

    fn executionCloseStep(self: *AiHost, handle: @import("../../../host/identity.zig").SessionHandle, release_content: bool) @import("../../shell/host/application_host.zig").CloseReceipt {
        const driver = self.execution().execution_driver orelse return .released;
        const backend = if (self.execution().execution_backend) |*value| value else return .released;
        const contexts = self.allocator.alloc(@import("../../../ai/host_tools.zig").Context, backend.admissions.items.len) catch return .unknown;
        defer self.allocator.free(contexts);
        const count = backend.beginClose(handle, contexts) catch return .unknown;
        if (count == 0) return .released;
        if (driver.targetEvidence(handle)) |fact| {
            // User-authorized protocol close may terminate a foreground
            // program. Waiting for its recording before initiating that close
            // deadlocks an already handed-off terminal. Keep the original
            // Service alive through release_content until the real close has
            // settled its recording and the Driver has persisted that fact.
            if (fact.input_grants_released and fact.pending_dispatch == 0 and (!release_content or fact.recordings_settled)) return .released;
        }
        const sent = for (self.execution().execution_close_sent.items) |prior| {
            if (prior.eql(handle)) break true;
        } else false;
        if (!sent) {
            for (contexts[0..count]) |context| driver.stopTarget(context, handle) catch return .awaiting;
            self.execution().execution_close_sent.append(self.execution().allocator, handle) catch return .awaiting;
        }
        self.uiOwner().wakeAt(33 * std.time.ns_per_ms);
        return .awaiting;
    }

    /// Keep the released worker's settled executions (with their admissions) on the view host.
    fn retainSettledExecutions(self: *AiHost, settled: []@import("../../../ai/host_execution.zig").Retained) void {
        const a = std.heap.c_allocator;
        defer a.free(settled);
        const view = self.attachedView();
        for (settled) |*item| {
            const admission = if (self.execution().execution_backend) |*backend| backend.admissionFor(item.id) else null;
            if (admission == null) {
                item.deinit(a);
                continue;
            }
            if (view.retained_executions.items.len >= retained_execution_limit) {
                var oldest = view.retained_executions.orderedRemove(0);
                oldest.receipt.deinit(a);
            }
            view.retained_executions.append(a, .{ .receipt = item.*, .admission = admission.? }) catch {
                item.deinit(a);
                continue;
            };
        }
    }
    /// Hand a conversation's retained admissions to its new worker's backend (the receipts went to
    /// the new driver at start).
    fn adoptRetainedExecutions(self: *AiHost, conversation: @import("../../../host/identity.zig").ConversationId) !void {
        const a = std.heap.c_allocator;
        const view = self.attachedView();
        const backend = if (self.execution().execution_backend) |*value| value else return;
        for (view.retained_executions.items) |item| if (item.receipt.context.conversation_id.eql(conversation)) try backend.adoptAdmission(item.admission);
        // The driver copied the receipts at start; drop this conversation's entries here (the
        // driver retains them again when this worker is released).
        var index: usize = 0;
        while (index < view.retained_executions.items.len) {
            if (!view.retained_executions.items[index].receipt.context.conversation_id.eql(conversation)) {
                index += 1;
                continue;
            }
            var removed = view.retained_executions.orderedRemove(index);
            removed.receipt.deinit(a);
        }
    }

    pub fn executionShutdownReady(self: *AiHost) bool {
        const driver = self.execution().execution_driver orelse {
            if (self.execution().execution_backend) |*backend| backend.deinit();
            self.execution().execution_backend = null;
            return true;
        };
        driver.requestShutdown();
        if (!driver.shutdownReady()) return false;
        const settled = driver.finishRetaining() catch return false;
        self.execution().execution_driver = null;
        self.retainSettledExecutions(settled);
        if (self.execution().execution_backend) |*backend| backend.deinit();
        self.execution().execution_backend = null;
        self.execution().execution_bridge.shutdown(self.application_host);
        return true;
    }

    pub fn cleanup(self: *AiHost) void {
        self.launcher_seen.deinit(self.allocator);
        if (self.pending_action) |action| if (action.text) |text| self.allocator.free(text);
        self.pending_action = null;
        if (self.lifecycle_command) |*command| command.deinit();
        self.lifecycle_command = null;

        if (self.child_identity == null) if (self.shared_service) |shared_host| if (self.application_host) |app| {
            shared_host.releaseWindow(app.window_id) catch {
                applog.warn(.app, "AI owners are still draining; retaining their view adapter", .{});
                return;
            };
        };
        self.execution_host = null;
        self.request_cancel.cancel();
        self.host_approval.stop();
        self.user_interaction.stop();
        self.inventory_approval.clear();
        if (self.transcript_images) |store| {
            store.cancel();
            if (self.application_host) |app| _ = store.tick(app);
            if (store.busy()) {
                self.tool_bridge.shutdown(self.application_host);
                applog.warn(.app, "Image preview cleanup is pending; retaining AI owner", .{});
                return;
            }
        }
        self.compaction.deinit();
        self.conversation_titles.deinit(self.allocator);
        self.auto_compaction_attempts.deinit(self.allocator);
        self.history_heights.deinit(self.allocator);
        self.row_anchors.deinit(self.allocator);
        self.model_discovery.deinit();
        for (self.retained_executions.items) |*item| item.receipt.deinit(std.heap.c_allocator);
        self.retained_executions.deinit(std.heap.c_allocator);
        // Cancel rate-limit waits and join before releasing request-owned state.
        self.request_cancel.cancel();
        self.host_approval.stop();
        self.user_interaction.stop();
        self.inventory_approval.clear();
        if (self.secret_controller) |*controller| controller.deinit();
        self.secret_controller = null;
        self.tool_bridge.shutdown(self.application_host);
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
        if (self.recording_access) |*access| access.deinit();
        self.recording_access = null;
        // Normal window close drains this owner before Scope disposal.
        if (!self.executionShutdownReady()) {
            // Unexpected teardown must not free contexts still borrowed by the
            // owner. The process exit path retains these owners rather than
            // allowing a callback into freed UI or session memory.
            applog.warn(.app, "Execution shutdown is not released; retaining AI owner", .{});
            return;
        }
        self.tool_bridge.clear() catch {
            applog.warn(.app, "Tool cleanup is not released; retaining AI owner", .{});
            return;
        };
        self.history_submissions.deinit(self.allocator);
        if (self.task_finish) |*finish| finish.deinit();
        self.task_finish = null;
        self.execution_bridge.deinit();
        for (self.lifecycle_controllers.items) |controller| {
            controller.deinitAfterWorker();
            self.allocator.destroy(controller);
        }
        self.lifecycle_controllers.deinit(self.allocator);
        self.task_finish_views.deinit(self.allocator);
        self.execution_close_sent.deinit(self.allocator);
        self.released_task_contexts.deinit(self.allocator);
        self.pending_ai_completions.deinit(self.allocator);
        self.pending_host_notices.deinit(self.allocator);
        self.lifecycle_controller = null;
        if (self.lifecycle_runtime) |runtime| runtime.journal_owner.release();
        self.lifecycle_runtime = null;
        self.cancelAttachmentReaders(null);
        self.attachment_readers.deinit(self.allocator);
        self.cancelImageReaders(null);
        self.image_readers.deinit(self.allocator);
        if (self.transcript_images) |store| {
            store.deinit();
            self.allocator.destroy(store);
            self.transcript_images = null;
        }
        if (self.request_images) |*bundle| bundle.deinit();
        self.request_image_refs.deinit(self.allocator);
        self.clearPreflightImageRefs();
        self.preflight_image_refs.deinit(self.allocator);
        if (self.last_user_images) |*bundle| bundle.deinit();
        if (self.request_attachments) |*bundle| bundle.deinit();
        for (self.history.items) |*message| message.deinit(self.allocator);
        self.history.deinit(self.allocator);
        self.clearRequestHistory();
        self.wire_history.deinit();
        if (self.shared_service == null) if (self.assistant_states) |store| {
            store.deinit();
            self.allocator.destroy(store);
        };
        self.manager.deinit();
        // Scope disposes child conversation widgets before this parent cleanup.
        self.tool_results.deinit();
        self.tool_bridge.deinit();
        self.stream_mailbox.deinit();
        self.step_mailbox.deinit();
        self.current_turn.deinit(self.allocator);
        if (self.recall_draft) |value| self.allocator.free(value);
        self.controller.deinit();
        if (self.request_text) |owned| self.allocator.free(owned);
        if (self.last_user_text) |owned| self.allocator.free(owned);
        if (self.last_user_wire) |owned| self.allocator.free(owned);
        if (self.last_user_attachments) |*bundle| bundle.deinit();
        if (self.native_binding) |binding| self.allocator.destroy(binding);
        if (self.native_client) |client| self.allocator.destroy(client);
        if (self.native_context) |context| self.allocator.destroy(context);
        if (self.request_config) |*snapshot| snapshot.deinit();
        if (self.request_context) |*context| context.deinit(self.allocator);
        if (self.ai_io) |io| {
            io.deinit();
            self.allocator.destroy(io);
        }
        self.allocator.destroy(self);
    }
};

// ── Click contexts for plain-node interactive elements ──────────────

pub const AiStopClick = struct {
    host: *AiHost,
};

pub fn onAiStopClick(raw: *anyopaque) void {
    const click: *AiStopClick = @ptrCast(@alignCast(raw));
    click.host.stop();
}

/// Shared writable conversation surface used by the main assistant and child dialog.
pub fn mountAssistantConversation(ai_host: *AiHost, scope: *ui.Scope, ai_card_box: *ui.Node, ai_scroll: ui.widgets.ScrollAreaResult, ai_conversation: *ui.Node, ai_prompt: *ui.Signal([]const u8)) !void {
    const cx = ai_host.cx;
    const ai_styles = @import("../pane/view/ai_assistant_styles.zig");

    ai_host.task_finish_holder = try ui.boxStyled(cx, ai_styles.trailingHolder, .{});
    ai_host.task_finish_holder.?.meta.ownership.meta.test_id = ai_host.id_space.id("ai.task_finish.list");
    try ai_scroll.content.appendChild(cx.allocator, ai_host.task_finish_holder.?);
    // The current lifecycle row follows every current-turn surface, including approval.
    const ai_turn_footer = try ui.boxStyled(cx, ai_styles.trailingHolder, .{});
    ai_turn_footer.meta.ownership.meta.test_id = ai_host.id_space.id("ai.turn.footer");
    ai_turn_footer.setDisplay(.none);
    ai_host.turn_footer = ai_turn_footer;
    try ai_scroll.content.appendChild(cx.allocator, ai_turn_footer);
    const ai_preview_holder = try ui.boxStyled(cx, @import("../attachments/view/ai_attachments_styles.zig").inlineHolder, .{});
    ai_preview_holder.setDisplay(.none);
    try ai_scroll.content.insertChildBefore(cx.allocator, ai_preview_holder, ai_conversation);
    ai_host.attachment_preview_holder = ai_preview_holder;
    ai_host.attachments_view = try @import("../attachments/view/ai_attachments_view.zig").View.mountInline(cx, scope, .{ .context = ai_host, .remove = AiHost.removeAttachment, .attach = AiHost.attachAttachment, .reselect = AiHost.reselectAttachment, .preview_visibility = AiHost.textPreviewVisibility, .on_error = AiHost.attachmentViewError }, ai_preview_holder);
    ai_card_box.behavior.events.capture_context = ai_host;
    ai_card_box.behavior.events.on_event_capture = AiHost.attachmentPreviewEvent;
    ai_host.images_view = try @import("../attachments/view/ai_image_attachments_view.zig").View.mount(cx, scope, .{ .context = ai_host, .remove = AiHost.removeImage, .retry = AiHost.retryImage, .visibility = AiHost.imagePreviewVisibility, .on_error = AiHost.attachmentViewError }, ai_preview_holder);

    try ai_host.images_view.?.shareRail(ai_host.attachments_view.?.rail.content);
    ai_host.attachments_view.?.external_rail = ai_host.images_view.?.root;
    ai_host.feedback = try @import("../pane/view/ai_feedback_view.zig").View.mount(cx, scope);
    try ai_scroll.content.appendChild(cx.allocator, ai_host.feedback.?.root);
    // “新消息”: over the viewport's bottom edge, centered (it scrolls with nothing).
    ai_host.new_messages = try @import("../pane/view/ai_new_messages_view.zig").View.mount(cx, scope, cx.on(AiHost, ai_host, AiHost.jumpToNewMessages));
    try ai_scroll.container.appendChild(cx.allocator, ai_host.new_messages.?.root);
    const PendingView = @import("../approvals/view/ai_pending_view.zig");
    // The main panel's queue editor state outlives its view (host Scope); a child dialog's goes with it.
    if (ai_host.child_identity == null and ai_host.pending_edit == null) if (ai_host.scope) |host_scope| {
        ai_host.pending_edit = try host_scope.createState(PendingView.Edit, try PendingView.Edit.init(host_scope));
    };
    ai_host.pending_view = try PendingView.View.mountOn(cx, scope, .{ .context = ai_host, .act = AiHost.queueAction }, ai_host.pending_edit);
    ai_host.unconfigured = try @import("../pane/view/ai_unconfigured_view.zig").View.mount(cx, scope, cx.on(AiHost, ai_host, AiHost.configureService));
    try ai_card_box.appendChild(cx.allocator, ai_host.unconfigured.?.root);
    // Composer area (Pencil Kaf7E ③ / ⑤): the queue, the decision panel and the composer — one
    // native compound Textarea: attachment chips in its header row, the tool row (with Send /
    // Stop) in its footer (view: composer/view/ai_composer.yix). The host keeps the Textarea's
    // result (`composer.input()`): IME, paste, drop, ↑↓ history and the send route stay on it.
    const Composer = @import("../composer/view/ai_composer_view.zig");
    const composer = try Composer.View.mount(cx, scope, .{
        .prompt = ai_prompt,
        .callbacks = .{ .context = ai_host, .send = AiHost.sendComposer, .stop = AiHost.stopComposer, .prompt_changed = AiHost.composerPromptChanged },
        .controls = .{ .context = ai_host, .action = AiHost.composerAction, .open_settings = AiHost.composerSettings, .models_opened = AiHost.composerModelsOpened },
        .interaction = .{ .context = ai_host, .act = AiHost.composerInteractionAction },
    });
    ai_host.composer = composer;
    const ai_input = composer.input();
    // Pencil Kaf7E ③: the text grows with its wrapped lines, 1 to 6, then scrolls (native auto_rows).
    ai_host.input_node = ai_input.input;
    ai_host.textarea = ai_input.state;
    ai_host.composer_input = ai_input;
    // The attachment chips sit in this field's header: a preview closes while the field is not shown.
    if (ai_host.attachments_view) |chips| chips.field = ai_input.wrapper;
    ai_host.composer_node = composer.root;
    ai_host.composer_controls = composer.controls;
    ai_host.composer_interaction = composer.interaction;
    ai_host.send_hint = composer.controls.send_hint;
    ai_host.send_disabled = composer.sendDisabledSignal();
    try @import("../composer/view/ai_composer_sizing.zig").bindTheme(cx, scope, ai_input);
    ai_input.input.behavior.events.capture_context = ai_host;
    ai_input.input.behavior.events.on_event_capture = AiHost.composerEvent;
    try composer.queue.appendChild(cx.allocator, ai_host.pending_view.?.root);
    try composer.chips.appendChild(cx.allocator, ai_host.attachments_view.?.root);
    try ai_card_box.appendChild(cx.allocator, composer.root);
}
