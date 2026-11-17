#pragma once
// These tests exercise production Binding, Provider and the owner refresh entry.
// The hidden window substitutes only dispatch; Cx publication remains owner-only.
struct DemandFixture {
    zenit_uia::Binding *binding;
    WNDPROC previous;
    DWORD owner = GetCurrentThreadId();
    ZenitA11yNode node = {};
    unsigned calls = 0, wrong_thread = 0;
    bool deferred = false, close_in_callback = false;
};
static int demand_publish(void *opaque, void *) {
    auto *fixture = (DemandFixture *)opaque;
    ++fixture->calls;
    fixture->wrong_thread += GetCurrentThreadId() != fixture->owner;
    if (fixture->close_in_callback) { zenit_uia_destroy(fixture->binding); return 0; }
    if (fixture->deferred) return 0;
    return zenit_uia_publish(fixture->binding, &fixture->node, 1);
}
static LRESULT CALLBACK demand_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto *fixture = (DemandFixture *)GetPropW(window, L"Zenit.DemandFixture");
    if (fixture && message == ZENIT_UIA_REFRESH_MESSAGE)
        return zenit_uia_refresh(fixture->binding, wparam);
    return CallWindowProcW(fixture->previous, window, message, wparam, lparam);
}
struct DemandReader { IValueProvider *value; HRESULT result = E_FAIL; BSTR text = nullptr; };
static DWORD WINAPI demand_read(void *opaque) {
    auto *reader = (DemandReader *)opaque;
    reader->result = reader->value->get_Value(&reader->text);
    return 0;
}
static void demand_wait(HANDLE thread, DemandFixture &fixture, bool frame_end = false, bool close = false) {
    ULONGLONG deadline = GetTickCount64() + 5000;
    bool acted = false;
    while (WaitForSingleObject(thread, 0) == WAIT_TIMEOUT && GetTickCount64() < deadline) {
        MSG message;
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
        if (!acted && fixture.deferred && fixture.calls) {
            acted = true;
            if (close) zenit_uia_destroy(fixture.binding);
            else if (frame_end) { fixture.deferred = false; CHECK(demand_publish(&fixture, nullptr)); }
        }
        MsgWaitForMultipleObjects(1, &thread, FALSE, 10, QS_ALLINPUT);
    }
    DWORD wait = WaitForSingleObject(thread, 0); CHECK(wait == WAIT_OBJECT_0);
    if (wait != WAIT_OBJECT_0) ExitProcess(2);
    CloseHandle(thread);
}
static void a11y_demand_contract(HWND window) {
    using namespace zenit_uia;
    unsigned before = checks;
    auto *binding = (Binding *)zenit_uia_create(window); CHECK(binding); if (!binding) return;
    DemandFixture fixture{binding, (WNDPROC)GetWindowLongPtrW(window, GWLP_WNDPROC)};
    fixture.node.id = 21; fixture.node.parent_index = zenit_a11y::no_parent;
    fixture.node.role = 12; fixture.node.editable = fixture.node.uniform_format = 1;
    fixture.node.value = {"initial", 7}; fixture.node.visible_end = UINT32_MAX;
    CHECK(SetPropW(window, L"Zenit.DemandFixture", &fixture));
    SetWindowLongPtrW(window, GWLP_WNDPROC, (LONG_PTR)demand_window_proc);
    CHECK(zenit_uia_set_demand_handler(binding, &fixture, nullptr, demand_publish));
    InvokeCounter actions{GetCurrentThreadId()};
    CHECK(zenit_uia_set_action_handler(binding, &actions, count_invoke));
    CHECK(!binding->should_publish(GetTickCount64())); // Global listeners cannot pin a window.
    auto *root = new Provider(binding, zenit_a11y::no_parent);
    auto *provider = new Provider(binding, fixture.node.id);
    IRawElementProviderAdviseEvents *advise = nullptr;
    CHECK(root->QueryInterface(IID_IRawElementProviderAdviseEvents, (void **)&advise) == S_OK && advise);
    IUnknown *pattern = nullptr;
    CHECK(provider->GetPatternProvider(UIA_ValuePatternId, &pattern) == S_OK && pattern);
    IValueProvider *value = nullptr;
    if (pattern) { CHECK(pattern->QueryInterface(IID_IValueProvider, (void **)&value) == S_OK && value); pattern->Release(); }
    if (!value || !advise) ExitProcess(2);
    CHECK(fixture.calls == 1 && !fixture.wrong_thread);
    BSTR text = nullptr; CHECK(value->get_Value(&text) == S_OK && text && !wcscmp(text, L"initial")); SysFreeString(text);
    const auto expire = [&] { LONG64 last = InterlockedCompareExchange64(&binding->last_activity, 0, 0); return binding->should_publish((ULONGLONG)last + Binding::activity_timeout_ms + 1); };
    CHECK(!expire() && binding->snapshot_stale);
    fixture.node.value = {"latest \xe4\xb8\xad\xf0\x9f\xa7\xaa", 14};
    DemandReader reader{value}; HANDLE thread = CreateThread(nullptr, 0, demand_read, &reader, 0, nullptr); CHECK(thread);
    if (thread) { demand_wait(thread, fixture); CHECK(reader.result == S_OK && reader.text && !wcscmp(reader.text, L"latest 中🧪")); SysFreeString(reader.text); }
    CHECK(!fixture.wrong_thread && fixture.calls == 2);
    // Event-only subscriptions survive unlimited idle time, with balanced per-event counts.
    CHECK(advise->AdviseEventAdded(UIA_Text_TextChangedEventId, nullptr) == S_OK);
    CHECK(advise->AdviseEventAdded(UIA_Text_TextChangedEventId, nullptr) == S_OK);
    CHECK(advise->AdviseEventAdded(UIA_AutomationPropertyChangedEventId, nullptr) == S_OK);
    CHECK(expire());
    CHECK(advise->AdviseEventRemoved(UIA_Invoke_InvokedEventId, nullptr) == S_OK && binding->subscription_count == 3);
    CHECK(advise->AdviseEventRemoved(UIA_Text_TextChangedEventId, nullptr) == S_OK && expire());
    CHECK(advise->AdviseEventRemoved(UIA_Text_TextChangedEventId, nullptr) == S_OK && expire());
    CHECK(advise->AdviseEventRemoved(UIA_AutomationPropertyChangedEventId, nullptr) == S_OK && !expire());
    // A multi-property subscription can be removed one property at a time.
    // Removing Name must not retire an event-only Value subscriber.
    SAFEARRAY *properties = SafeArrayCreateVector(VT_I4, 0, 2);
    SAFEARRAY *one_property = SafeArrayCreateVector(VT_I4, 0, 1);
    CHECK(properties && one_property);
    if (properties && one_property) {
        LONG index = 0, property = UIA_NamePropertyId;
        CHECK(SafeArrayPutElement(properties, &index, &property) == S_OK);
        CHECK(SafeArrayPutElement(one_property, &index, &property) == S_OK);
        index = 1; property = UIA_ValueValuePropertyId;
        CHECK(SafeArrayPutElement(properties, &index, &property) == S_OK);
        // Force the second allocation to fail and require an atomic rollback.
#ifdef ZENIT_UIA_CONTRACT_CONTENT
        subscription_allocation_fail_after = 1;
        CHECK(advise->AdviseEventAdded(UIA_AutomationPropertyChangedEventId, properties) == E_OUTOFMEMORY);
        CHECK(binding->subscription_count == 0 && binding->subscription_slots == 0);
        subscription_allocation_fail_after = -1;
#endif
        CHECK(advise->AdviseEventAdded(UIA_AutomationPropertyChangedEventId, properties) == S_OK);
        CHECK(advise->AdviseEventRemoved(UIA_AutomationPropertyChangedEventId, one_property) == S_OK);
        CHECK(expire());
        index = 0; CHECK(SafeArrayPutElement(one_property, &index, &property) == S_OK);
        CHECK(advise->AdviseEventRemoved(UIA_AutomationPropertyChangedEventId, one_property) == S_OK);
        CHECK(!expire());
    }
    if (properties) SafeArrayDestroy(properties);
    if (one_property) SafeArrayDestroy(one_property);
#ifdef ZENIT_UIA_CONTRACT_CONTENT
    printf("Windows UIA demand case: property subsets and allocation rollback PASS\n");
#endif
    // Distinct event IDs are untrusted input; the per-window registry is bounded.
    for (unsigned i = 0; i < Binding::max_subscription_keys; ++i) CHECK(advise->AdviseEventAdded(30000 + i, nullptr) == S_OK);
    CHECK(advise->AdviseEventAdded(30000 + Binding::max_subscription_keys, nullptr) == HRESULT_FROM_WIN32(ERROR_NOT_ENOUGH_QUOTA));
    CHECK(binding->subscription_slots == Binding::max_subscription_keys && binding->subscription_count == Binding::max_subscription_keys);
    for (unsigned i = 0; i < Binding::max_subscription_keys; ++i) CHECK(advise->AdviseEventRemoved(30000 + i, nullptr) == S_OK);
    CHECK(binding->subscription_slots == 0 && binding->subscription_count == 0 && !expire());
    printf("Windows UIA demand case: lease and balanced event-only subscriptions PASS\n");
    MSG pending;
    while (PeekMessageW(&pending, window, ZENIT_UIA_REFRESH_MESSAGE, ZENIT_UIA_REFRESH_MESSAGE, PM_REMOVE)) DispatchMessageW(&pending);
    CHECK(!expire());
    // The request arrives during an owner frame; its previous snapshot is not returned.
    fixture.node.value = {"after deferred frame", 20}; fixture.deferred = true; fixture.calls = 0;
    reader = {value}; thread = CreateThread(nullptr, 0, demand_read, &reader, 0, nullptr); CHECK(thread);
    if (thread) { demand_wait(thread, fixture, true); CHECK(reader.result == S_OK && reader.text && !wcscmp(reader.text, L"after deferred frame")); SysFreeString(reader.text); }
    CHECK(fixture.calls == 2 && !fixture.wrong_thread);
    printf("Windows UIA demand case: stale proxy and deferred owner refresh PASS\n");
    CHECK(!expire()); fixture.deferred = true; fixture.calls = 0;
    reader = {value}; thread = CreateThread(nullptr, 0, demand_read, &reader, 0, nullptr); CHECK(thread);
    if (thread) { demand_wait(thread, fixture, false, true); CHECK(reader.result == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE && !reader.text); }
    CHECK(fixture.calls == 1 && !fixture.wrong_thread);
    CHECK(value->get_Value(&text) == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE);
    // Cached requests for an old window identity cannot publish the replacement's tree.
    auto *replacement = (Binding *)zenit_uia_create(window); CHECK(replacement);
    fixture.binding = replacement;
    CHECK(!zenit_uia_refresh(replacement, binding->identity));
    CHECK(zenit_uia_set_demand_handler(replacement, &fixture, nullptr, demand_publish));
    fixture.deferred = false; fixture.close_in_callback = true;
    auto *closing = new Provider(replacement, fixture.node.id); VARIANT property = {};
    CHECK(closing->GetPropertyValue(UIA_NamePropertyId, &property) == (HRESULT)UIA_E_ELEMENTNOTAVAILABLE);
    VariantClear(&property); closing->Release();
    printf("Windows UIA demand case: disconnect, callback destruction and HWND reuse PASS\n");
    value->Release(); advise->Release(); provider->Release(); root->Release();
    SetWindowLongPtrW(window, GWLP_WNDPROC, (LONG_PTR)fixture.previous);
    RemovePropW(window, L"Zenit.DemandFixture");
    printf("Windows UIA demand: %u checks\n", checks-before);
}
