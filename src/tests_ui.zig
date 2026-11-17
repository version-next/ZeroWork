//! transfer_panel 的 zenit 布局测试聚合器：独立测试模块（test-ui step）。
//! 单独存在的理由见 build.zig 注释——zenit 的 coretext 桥是 C 源，挂到被
//! exe 依赖的模块上会传播成重复链接（zenit build.zig 同款警告）。
// Load the nested host UI contract even under a narrow test filter.
comptime {
    _ = @import("features/files/view/file_workspace_icons.zig");
    _ = @import("features/ai/pane/tests/remaining_ui_tests.zig");
    _ = @import("features/ai/pane/tests/ai_history_view_tests.zig");
    _ = @import("features/ai/pane/tests/incremental_ui_tests.zig");
    _ = @import("shared/ui/components/icon_button_feedback/icon_button_feedback.zig");
    _ = @import("shared/ui/components/copy_button/copy_button.zig");
    _ = @import("features/workspace/model/context_menus.zig");
    _ = @import("features/shell/model/menu_spec.zig");
    _ = @import("features/shell/view/app_menu.zig");
    _ = @import("features/connections/auth/host/plugin_challenge_presenter.zig");
    _ = @import("platform/applog.zig");
    _ = @import("ai/provider_transport.zig");
    _ = @import("features/ai/sessions/tests/ai_empty_recent_view_tests.zig");
    _ = @import("features/ai/sessions/model/view_model.zig");
    _ = @import("features/ai/shared/view/ai_id_space.zig");
    _ = @import("features/ai/approvals/tests/ai_inventory_grant_view_tests.zig");
    _ = @import("features/ai/approvals/tests/host_secret_store_tests.zig");
    _ = @import("features/ai/tools/host/ai_tools.zig");
    _ = @import("features/terminal/model/terminal_document.zig");
    _ = @import("shared/ui/styles/layout_motion.zig");
    _ = @import("shared/ui/interaction.zig");
    _ = @import("shared/ui/styles/float_card_motion.zig");
    _ = @import("shared/ui/styles/surface_material.zig");
    _ = @import("shared/ui/theme/theme_watch.zig");
    _ = @import("transfer/sftp_engine.zig");
    _ = @import("features/connections/wizard/view/wizard.zig");
    _ = @import("shared/ui/window/aux_window.zig");
    _ = @import("shared/ui/window/fixture_window.zig");
    _ = @import("plugins/remote/editor.zig");
    _ = @import("features/workspace/view/workspace.zig");
    _ = @import("features/workspace/view/empty_saved_connections.zig");
    _ = @import("features/shell/model/status_connection_extras.zig");
    _ = @import("features/workspace/host/session_os_cache.zig");
    _ = @import("shared/ui/components/session_icon/session_icon.zig");
    _ = @import("features/files/tests/file_application_host_tests.zig");
    _ = @import("features/notifications/tests/notification_presenter_controls_tests.zig");
    _ = @import("features/notifications/tests/notification_history_tests.zig");
}
test {
    _ = @import("features/ai/tools/host/ai_host_terminal_queries.zig");
    _ = @import("vt/tests/terminal_search_service_tests.zig");
    _ = @import("features/history/model/history_replay.zig");
    // copy-terms: history_archive.zig 的测试此前没有被任何测试根引用。
    _ = @import("features/history/model/history_archive.zig");
    _ = @import("platform/snapshot_scratch.zig");
    _ = @import("vt/search_task.zig");
    _ = @import("platform/idle_memory.zig");
    _ = @import("features/workspace/view/remote_session_notice.zig");
    _ = @import("shared/ui/tests/ui_constraint_tests.zig");
    _ = @import("features/history/tests/record_cleanup_ui_tests.zig");
    _ = @import("features/history/tests/history_card_vm_tests.zig");
    _ = @import("shared/ui/tests/history_host_teardown_tests.zig");
    _ = @import("features/history/model/card_type.zig");
    _ = @import("features/terminal/view/replay_surface.zig");
    _ = @import("features/ai/attachments/tests/ai_remote_picker_view_tests.zig");
    _ = @import("features/notifications/tests/notification_presenter_controls_tests.zig");
    _ = @import("features/notifications/tests/notification_history_tests.zig");
    _ = @import("shared/ui/tests/chrome_policy_tests.zig");
    _ = @import("shared/ui/tests/button_policy_tests.zig");
    _ = @import("features/transfer/view/transfer_panel.zig");
    _ = @import("features/connections/wizard/tests/wizard_tests.zig");
    _ = @import("features/connections/wizard/tests/wizard_probe_tests.zig");
    // 设置窗口（`.yix`）：3f 删除旧外壳后，原先经 settings_content_tests 聚合的用例直接登记在这里。
    _ = @import("features/settings/tests/settings_window_semantic_tests.zig");
    _ = @import("features/settings/tests/settings_window_yix_tests.zig");
    _ = @import("features/settings/tests/settings_rows_tests.zig");
    _ = @import("features/settings/tests/settings_panes_tests.zig");
    _ = @import("features/settings/tests/settings_panes_b_tests.zig");
    _ = @import("features/settings/tests/settings_appearance_tests.zig");
    _ = @import("features/settings/tests/settings_data_cleanup_tests.zig");
    _ = @import("features/settings/tests/plugin_settings_yix_tests.zig");
    _ = @import("features/settings/tests/settings_transfer_budget_tests.zig");
    _ = @import("features/transfer/tests/settings_transfer_defaults_tests.zig");
    _ = @import("shared/ui/tests/theme_layer_tests.zig");
    _ = @import("features/terminal/tests/terminal_overlay_theme_tests.zig");
    _ = @import("features/terminal/tests/terminal_search_theme_tests.zig");
    _ = @import("features/settings/tests/settings_field_lifecycle_tests.zig");
    _ = @import("features/settings/tests/settings_search_alias_tests.zig");
    _ = @import("features/shell/tests/status_detail_tests.zig");
    _ = @import("features/shell/tests/startup_view_tests.zig");
    _ = @import("shared/ui/tests/overlay_host_tests.zig");
    _ = @import("shared/ui/tests/surface_migration_tests.zig");
    _ = @import("shared/ui/surface/lifecycle_budget.zig");
    _ = @import("shared/ui/tests/confirm_tests.zig");
    _ = @import("shared/ui/confirm/confirm.zig");
    _ = @import("shared/ui/overlay/overlay_host.zig");
    _ = @import("features/connections/progress/tests/ssh_status_host_tests.zig");
    _ = @import("features/connections/progress/tests/ssh_terminal_status_tests.zig");
    _ = @import("features/connections/assets/tests/asset_group_host_tests.zig");
    _ = @import("features/shell/tests/sidebar_view_tests.zig");
    _ = @import("features/ai/pane/tests/ai_message_alignment_tests.zig");
    _ = @import("features/ai/pane/tests/ai_feedback_view_tests.zig");
    _ = @import("features/terminal/tests/settings_runtime_consumer_tests.zig");
    _ = @import("features/workspace/host/session_export_jobs.zig");
    _ = @import("features/terminal/tests/terminal_surface_tests.zig");
    _ = @import("features/terminal/tests/ssh_terminal_service_tests.zig");
    _ = @import("features/shell/view/background_layers.zig");
    _ = @import("features/shell/tests/background_surface_tests.zig");
    _ = @import("shared/ui/tests/floating_input_tests.zig");
    _ = @import("features/connections/socks/tests/socks_info_theme_tests.zig");
    _ = @import("features/connections/socks/tests/socks_background_ui_tests.zig");
    _ = @import("features/shell/tests/material_popup_tests.zig");
    _ = @import("features/shell/view/title_tools_view.zig");
    _ = @import("proto/ssh/tests/shared_transfer_native_tests.zig");
    _ = @import("features/connections/auth/tests/totp_autofill_tests.zig");
    _ = @import("features/terminal/tests/notification_read_view_tests.zig");
    _ = @import("shared/ui/tests/auxiliary_appearance_tests.zig");
    _ = @import("features/workspace/view/session_menu.zig");
    _ = @import("features/transfer/tests/transfer_manager_view_tests.zig");
    _ = @import("features/transfer/tests/transfer_confirmation_view_tests.zig");
    _ = @import("features/settings/tests/ai_provider_settings_tests.zig");
    _ = @import("features/settings/tests/ai_settings_yix_tests.zig");
    _ = @import("features/ai/composer/tests/ai_composer_controls_view_tests.zig");
    _ = @import("features/ai/composer/tests/ai_composer_view_tests.zig");
    _ = @import("features/ai/composer/tests/ai_composer_input_tests.zig");
    _ = @import("features/ai/composer/tests/ai_composer_interaction_view_tests.zig");
    _ = @import("features/ai/pane/tests/ai_conversation_input_view_tests.zig");
    _ = @import("features/ai/attachments/tests/ai_attachments_view_tests.zig");
    _ = @import("features/ai/attachments/tests/ai_image_attachment_view_tests.zig");
    _ = @import("ai/tests/ai_image_attachment_tests.zig");
    _ = @import("ai/tests/ai_terminal_text_attachment_tests.zig");
    _ = @import("features/ai/attachments/tests/ai_vt_attachment_view_tests.zig");
    _ = @import("features/ai/pane/tests/ai_panel_visibility_tests.zig");
    _ = @import("features/ai/pane/tests/ai_launcher_view_tests.zig");
    _ = @import("features/terminal/tests/command_error_hint_tests.zig");
    _ = @import("features/terminal/tests/command_help_tests.zig");
    _ = @import("features/workspace/tests/app_menu_tests.zig");
    _ = @import("shared/ui/tests/float_layer_tests.zig");
    _ = @import("shared/ui/tests/float_chrome_tests.zig");
    _ = @import("shared/ui/tests/panel_header_tests.zig");
    _ = @import("shared/ui/tests/float_swipe_layer_tests.zig");
    _ = @import("features/workspace/view/tab_motion_anchor.zig");
    _ = @import("features/ai/sessions/tests/ai_children_view_tests.zig");
    _ = @import("features/ai/sessions/view/ai_child_logo.zig");
    _ = @import("features/ai/sessions/view/ai_popover_anchor.zig");
    _ = @import("features/ai/cards/tests/ai_tool_results_view_tests.zig");
    _ = @import("features/ai/cards/tests/ai_recovery_view_tests.zig");
    _ = @import("features/connections/progress/tests/connection_host_tests.zig");
    _ = @import("features/connections/quick_connect/tests/quick_connect_view_tests.zig");
    _ = @import("features/connections/wizard/tests/wizard_test_progress_tests.zig");
    _ = @import("features/terminal/tests/terminal_search_tests.zig");
    _ = @import("features/terminal/view/terminal_view.zig");
    _ = @import("vt/ssh_worker.zig");
    _ = @import("features/shell/view/tab_rename.zig");
    _ = @import("features/workspace/view/workspace.zig");
    _ = @import("features/shell/host/application_host.zig");
    _ = @import("features/workspace/host/multiwindow_test_routes.zig");
    _ = @import("features/shell/tests/fullscreen_titlebar_tests.zig");
    _ = @import("features/history/model/history_list.zig");
    _ = @import("features/workspace/host/session_runtime.zig");
    _ = @import("features/connections/wizard/tests/ssh_resource_ledger_tests.zig");
    _ = @import("features/connections/auth/tests/auth_challenge_view_tests.zig");
    _ = @import("features/connections/progress/tests/connection_progress_view_tests.zig");
    _ = @import("features/connections/progress/model/failure_view.zig");
    _ = @import("features/connections/assets/tests/asset_action_view_tests.zig");
    _ = @import("features/connections/progress/tests/connection_details_view_tests.zig");
    _ = @import("features/connections/progress/tests/connection_logs_view_tests.zig");
    _ = @import("features/shell/tests/status_connection_view_tests.zig");
    _ = @import("features/connections/socks/tests/socks_info_view_tests.zig");
    _ = @import("features/connections/socks/tests/socks_config_view_tests.zig");
    _ = @import("features/connections/socks/tests/socks_exposure_confirm_tests.zig");
    _ = @import("features/ai/tools/tests/ai_local_tools_tests.zig");
    _ = @import("features/workspace/tests/group_close_controller_tests.zig");
    _ = @import("host/tests/application_task_domain_tests.zig");
    _ = @import("ai/tests/provider_protocol_tools_tests.zig");
    _ = @import("proto/ssh/tests/sftp_readonly_tests.zig");
    _ = @import("transfer/tests/sftp_resume_native_tests.zig");
    _ = @import("host/tests/file_binding_host_tests.zig");
    _ = @import("host/tests/file_binding_startup_tests.zig");
    _ = @import("host/tests/file_route_factory_tests.zig");
    _ = @import("features/files/tests/file_workspace_view_tests.zig");
    _ = @import("transfer/tests/transfer_engine_mux_tests.zig");
    _ = @import("host/tests/file_transfer_runtime_tests.zig");
    _ = @import("host/tests/file_workspace_controller_tests.zig");
    _ = @import("host/tests/sftp_adapter_tests.zig");
    _ = @import("features/files/tests/file_authentication_tests.zig");
    _ = @import("features/files/tests/file_workspace_presentation_tests.zig");
    _ = @import("host/tests/file_transfer_host_tests.zig");
    _ = @import("transfer/tests/engine_dispatch_tests.zig");
    _ = @import("transfer/tests/transfer_conflict_tests.zig");
    _ = @import("features/files/tests/file_application_host_tests.zig");
    _ = @import("features/ai/tools/tests/ai_ssh_tools_tests.zig");
    _ = @import("features/ai/cards/tests/ai_file_tool_result_tests.zig");
    _ = @import("features/ai/pane/tests/ai_tail_follow_tests.zig");
    _ = @import("features/ai/pane/view/ai_tail_follow.zig");
    _ = @import("features/ai/pane/view/ai_unconfigured_view.zig");
    _ = @import("local/tests/local_fs_service_tests.zig");
}

test {
    _ = @import("features/files/tests/file_mkdir_view_tests.zig");
    _ = @import("features/transfer/tests/transfer_conflict_view_tests.zig");
}

test {
    _ = @import("features/workspace/tests/broadcast_view_tests.zig");
}

test {
    _ = @import("features/ai/pane/tests/ai_conversation_tests.zig");
}

test {
    _ = @import("features/ai/pane/tests/ai_close_confirmation_view_tests.zig");
}

test {
    _ = @import("shared/testing/ui_kit.zig");
}
