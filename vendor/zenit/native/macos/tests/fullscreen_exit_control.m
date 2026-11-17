// Native control group for fullscreen exit continuity: a bare NSWindow (optionally
// with the system default titlebar, or a UnifiedCompact toolbar plus trailing
// titlebar accessory) enters and exits fullscreen on a timer. The recording is
// analyzed by scripts/check_macos_window_continuity.py to measure how many frames
// AppKit itself leaves the window undrawn after its exit animation.
// Build and run through scripts/run_macos_fullscreen_exit_control.sh.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
static double nowMs(void) { return [NSDate date].timeIntervalSince1970 * 1000.0; }
#define LOG(fmt, ...) fprintf(stderr, "[control %.1f] " fmt "\n", nowMs(), ##__VA_ARGS__)

@interface D : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *w;
@end
@implementation D
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 860)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    if (!getenv("CONTROL_DEFAULT_TITLEBAR")) {
        w.titlebarAppearsTransparent = YES;
        w.titleVisibility = NSWindowTitleHidden;
    } else LOG("default titlebar");
    w.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    NSView *v = [[NSView alloc] initWithFrame:w.contentView.bounds];
    v.wantsLayer = YES;
    v.layer.backgroundColor = [NSColor colorWithSRGBRed:0.95 green:0.55 blue:0.15 alpha:1].CGColor;
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    for (int i = 0; i < 6; i++) {
        CALayer *l = [CALayer layer];
        l.backgroundColor = [NSColor colorWithSRGBRed:0.2 green:0.3 blue:0.8 alpha:1].CGColor;
        l.frame = CGRectMake(60 + i * 160, 120 + (i % 2) * 200, 100, 100);
        [v.layer addSublayer:l];
    }
    w.contentView = v;
    if (getenv("CONTROL_ACCESSORY")) {
        NSTitlebarAccessoryViewController *acc = [NSTitlebarAccessoryViewController new];
        NSView *h = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1180, 38)];
        h.wantsLayer = YES;
        h.layer.backgroundColor = [NSColor colorWithSRGBRed:0.92 green:0.93 blue:0.95 alpha:1].CGColor;
        acc.view = h;
        acc.layoutAttribute = NSLayoutAttributeTrailing;
        acc.automaticallyAdjustsSize = NO;
        w.toolbar = [[NSToolbar alloc] initWithIdentifier:@"control.toolbar"];
        w.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        w.toolbar.visible = YES;
        [w addTitlebarAccessoryViewController:acc];
        LOG("accessory installed");
    }
    [w center];
    w.delegate = self;
    self.w = w;
    [w makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    LOG("window shown");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LOG("toggle enter"); [w toggleFullScreen:nil]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LOG("toggle exit"); [w toggleFullScreen:nil]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LOG("terminate"); [NSApp terminate:nil]; });
}
- (void)windowWillEnterFullScreen:(NSNotification *)n { LOG("willEnter"); }
- (void)windowDidEnterFullScreen:(NSNotification *)n { LOG("didEnter"); }
- (void)windowWillExitFullScreen:(NSNotification *)n { LOG("willExit"); }
- (void)windowDidExitFullScreen:(NSNotification *)n { LOG("didExit frame=%s", NSStringFromRect(self.w.frame).UTF8String); }
- (void)windowDidResize:(NSNotification *)n { LOG("didResize frame=%s visible=%d", NSStringFromRect(self.w.frame).UTF8String, self.w.visible); }
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        D *d = [D new];
        NSApp.delegate = d;
        [NSApp run];
    }
    return 0;
}
