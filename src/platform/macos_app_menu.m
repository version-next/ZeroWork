#import <AppKit/AppKit.h>

extern void zw_update_open(void);
extern const char *zw_update_current_version(void);
extern void macos_post_empty_event(void);
// 显示 › 外观… (title-click): the theme left the title bar; this native menu item opens
// Settings › 外观与主题 in the key window. The Zig loop takes the request (zw_app_menu_take_appearance).
static BOOL appearanceRequested;
static NSString *versionMetadata;
static void applyMenuBranding(void);
static char mainMenuObservation;
static BOOL observingMainMenu;
@interface ZWUpdateMenuAction : NSObject
- (void)check:(id)sender;
- (void)about:(id)sender;
- (void)appearance:(id)sender;
@end
@implementation ZWUpdateMenuAction
- (void)check:(id)sender { zw_update_open(); }
- (void)appearance:(id)sender { appearanceRequested = YES; macos_post_empty_event(); }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &mainMenuObservation) {
        applyMenuBranding();
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}
- (void)about:(id)sender {
    NSString *version = [NSString stringWithFormat:@"%s · %@", zw_update_current_version(), versionMetadata];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"ZeroWork",
        NSAboutPanelOptionApplicationVersion: version,
        NSAboutPanelOptionVersion: @"",
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:@""]
    }];
}
@end
static ZWUpdateMenuAction *updateMenuAction;

// AppKit caches the top-level item separately from its submenu title.
// Keep native actions and shortcuts, but do not expose the framework's CLI.
static void applyMenuBranding(void) {
    if (![NSThread isMainThread] || !NSApp) return;
    NSProcessInfo.processInfo.processName = @"ZeroWork";
    NSMenuItem *appMenuItem = NSApp.mainMenu.itemArray.firstObject;
    NSMenu *appMenu = appMenuItem.submenu;
    if (!appMenu) return;
    appMenuItem.title = @"ZeroWork";
    appMenu.title = @"ZeroWork";
    if (![appMenu itemWithTag:59301]) {
        NSMenuItem *update = [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(check:) keyEquivalent:@""];
        update.target = updateMenuAction; update.tag = 59301; [appMenu insertItem:update atIndex:MIN(1, appMenu.numberOfItems)];
    }
    for (NSMenuItem *item in appMenu.itemArray.copy) {
        if (item.action == NSSelectorFromString(@"zenitInstallCli:")) {
            [appMenu removeItem:item];
        }
    }
    // 显示 › 外观…: the menu bar generated from the shortcut router already has a 显示 menu;
    // tag it and put 外观… first. Otherwise (framework menu) add a top-level menu before Window.
    if (![NSApp.mainMenu itemWithTag:59310]) {
        for (NSMenuItem *item in NSApp.mainMenu.itemArray) {
            if (item.submenu && [item.submenu.title isEqualToString:@"显示"]) {
                item.tag = 59310;
                break;
            }
        }
    }
    NSMenuItem *existingView = [NSApp.mainMenu itemWithTag:59310];
    if (existingView && existingView.submenu && [existingView.submenu indexOfItemWithTag:59311] < 0) {
        NSMenuItem *appearance = [[NSMenuItem alloc] initWithTitle:@"外观…" action:@selector(appearance:) keyEquivalent:@""];
        appearance.target = updateMenuAction; appearance.tag = 59311;
        [existingView.submenu insertItem:appearance atIndex:0];
        if (existingView.submenu.numberOfItems > 1) [existingView.submenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }
    if (![NSApp.mainMenu itemWithTag:59310]) {
        NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"显示"];
        NSMenuItem *appearance = [[NSMenuItem alloc] initWithTitle:@"外观…" action:@selector(appearance:) keyEquivalent:@""];
        appearance.target = updateMenuAction; appearance.tag = 59311;
        [viewMenu addItem:appearance];
        NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"显示" action:nil keyEquivalent:@""];
        viewItem.tag = 59310; viewItem.submenu = viewMenu;
        NSInteger index = NSApp.windowsMenu ? [NSApp.mainMenu indexOfItemWithSubmenu:NSApp.windowsMenu] : -1;
        if (index < 0) index = NSApp.mainMenu.numberOfItems;
        [NSApp.mainMenu insertItem:viewItem atIndex:index];
    }
    // Removing the framework-only action can leave adjacent separators.
    for (NSInteger i = appMenu.numberOfItems - 1; i > 0; --i) {
        if ([appMenu itemAtIndex:i].isSeparatorItem && [appMenu itemAtIndex:i - 1].isSeparatorItem) {
            [appMenu removeItemAtIndex:i];
        }
    }
    for (NSMenuItem *item in appMenu.itemArray) {
        if (item.action == @selector(orderFrontStandardAboutPanel:) || item.action == @selector(about:)) {
            item.title = @"关于 ZeroWork";
            item.target = updateMenuAction;
            item.action = @selector(about:);
        } else if (item.action == @selector(hide:)) {
            item.title = @"隐藏 ZeroWork";
        } else if (item.action == @selector(hideOtherApplications:)) {
            item.title = @"隐藏其他";
        } else if (item.action == @selector(unhideAllApplications:)) {
            item.title = @"显示全部";
        } else if (item.action == @selector(terminate:)) {
            item.title = @"退出 ZeroWork";
        }
    }
}

// The framework replaces mainMenu again when AppKit finishes launching.
// Reapply branding to that menu and any later replacement, without polling.
void zw_app_menu_apply_branding(const char *metadata) {
    if (![NSThread isMainThread] || !NSApp) return;
    versionMetadata = [NSString stringWithUTF8String:metadata];
    if (!updateMenuAction) updateMenuAction = [ZWUpdateMenuAction new];
    if (!observingMainMenu) {
        [NSApp addObserver:updateMenuAction forKeyPath:@"mainMenu" options:0 context:&mainMenuObservation];
        observingMainMenu = YES;
    }
    applyMenuBranding();
}

bool zw_app_menu_take_appearance(void) {
    BOOL requested = appearanceRequested;
    appearanceRequested = NO;
    return requested;
}

// Test harness only (the route is erased from production builds): list the main menu's
// top-level titles, the 显示 menu's items and every item's key equivalent; invoke 显示 › 外观…
// (invoke = 1) or the item titled `title` (invoke = 2) through AppKit.
size_t zw_app_menu_test(int invoke, const char *title, size_t title_len, char *buffer, size_t capacity) {
    if (![NSThread isMainThread] || !NSApp.mainMenu || capacity == 0) return 0;
    NSMenuItem *viewItem = [NSApp.mainMenu itemWithTag:59310];
    if (invoke == 1) {
        NSInteger index = viewItem ? [viewItem.submenu indexOfItemWithTag:59311] : -1;
        if (index < 0) return 0;
        [viewItem.submenu performActionForItemAtIndex:index];
    } else if (invoke == 2) {
        NSString *wanted = [[NSString alloc] initWithBytes:title length:title_len encoding:NSUTF8StringEncoding];
        BOOL found = NO;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            NSInteger index = wanted ? [top.submenu indexOfItemWithTitle:wanted] : -1;
            if (index < 0) continue;
            [top.submenu update];
            if (![top.submenu itemAtIndex:index].enabled) return 0;
            [top.submenu performActionForItemAtIndex:index];
            found = YES;
            break;
        }
        if (!found) return 0;
    }
    NSMutableArray *top = [NSMutableArray array];
    NSMutableArray *all = [NSMutableArray array];
    for (NSMenuItem *item in NSApp.mainMenu.itemArray) {
        NSString *menuTitle = item.submenu.title ?: item.title;
        [top addObject:menuTitle];
        for (NSMenuItem *entry in item.submenu.itemArray) {
            if (entry.isSeparatorItem) continue;
            NSEventModifierFlags mask = entry.keyEquivalentModifierMask;
            [all addObject:@{
                @"menu": menuTitle, @"title": entry.title ?: @"", @"key": entry.keyEquivalent ?: @"",
                @"command": @((mask & NSEventModifierFlagCommand) != 0), @"shift": @((mask & NSEventModifierFlagShift) != 0),
                @"control": @((mask & NSEventModifierFlagControl) != 0), @"option": @((mask & NSEventModifierFlagOption) != 0),
            }];
        }
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSMenuItem *item in viewItem.submenu.itemArray) [items addObject:item.title];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"ok": @YES, @"menus": top, @"view": items, @"items": all, @"invoked": @(invoke != 0)} options:0 error:nil];
    if (!json || json.length >= capacity) return 0;
    memcpy(buffer, json.bytes, json.length);
    return json.length;
}
