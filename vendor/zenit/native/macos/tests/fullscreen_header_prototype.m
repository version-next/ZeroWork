// AppKit feasibility gate. Native controls are canaries for hosting and input;
// this is deliberately not a claim that Zenit's GPU Header has been integrated.
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CAShapeLayer.h>

@interface ProbeHeader : NSView
@property NSUInteger rightClicks;
@end
@implementation ProbeHeader
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (NSView *)hitTest:(NSPoint)point {
    NSPoint local=[self convertPoint:point fromView:self.superview];
    if(local.x<76) return nil; // Native traffic lights own their hit region.
    return [super hitTest:point];
}
- (void)rightMouseDown:(NSEvent *)event { self.rightClicks++; }
@end

@interface Probe : NSObject <NSWindowDelegate,NSMenuDelegate>
@property NSWindow *window;
@property NSTitlebarAccessoryViewController *accessory;
@property ProbeHeader *header;
@property NSTextField *input;
@property NSButton *button;
@property NSUInteger clicks;
@property BOOL transitioning;
@property NSUInteger menuOpens;
@end
@implementation Probe
- (void)clicked:(id)sender { self.clicks++; }
- (void)menuWillOpen:(NSMenu *)menu { self.menuOpens++; }
- (void)windowWillEnterFullScreen:(NSNotification *)n { self.transitioning=YES; }
- (void)windowDidEnterFullScreen:(NSNotification *)n { self.transitioning=NO; }
- (void)windowWillExitFullScreen:(NSNotification *)n { self.transitioning=YES; }
- (void)windowDidExitFullScreen:(NSNotification *)n { self.transitioning=NO; }
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w { self.transitioning=NO; }
- (void)windowDidFailToExitFullScreen:(NSWindow *)w { self.transitioning=NO; }
@end

static NSMutableArray *checks;
static NSString *output;
static void pump(double seconds) {
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];
    do {
        NSEvent *e=[NSApp nextEventMatchingMask:NSEventMaskAny
            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
            inMode:NSDefaultRunLoopMode dequeue:YES];
        if(e) [NSApp sendEvent:e];
        [NSApp updateWindows];
    } while(until.timeIntervalSinceNow>0);
}
static void check(NSString *name, BOOL passed, id observed) {
    [checks addObject:@{@"name":name,@"passed":@(passed),@"observed":observed?:[NSNull null]}];
    fprintf(stderr,"%s %s\n",passed?"PASS":"FAIL",name.UTF8String);
}
static NSDictionary *rect(NSRect r) {
    return @{@"x":@(r.origin.x),@"y":@(r.origin.y),@"w":@(r.size.width),@"h":@(r.size.height)};
}
static NSRect screenRect(NSView *v) {
    if(!v.window) return NSZeroRect;
    return [v.window convertRectToScreen:[v convertRect:v.bounds toView:nil]];
}
static NSDictionary *geometry(Probe *p) {
    NSButton *close=[p.window standardWindowButton:NSWindowCloseButton];
    return @{@"header":rect(screenRect(p.header)),@"visible":rect(p.header.visibleRect),
        @"close":rect(screenRect(close)),@"closeHidden":@(close.hidden),@"closeAlpha":@(close.alphaValue),
        @"content":rect(screenRect(p.window.contentView)),
        @"contentLayout":rect([p.window convertRectToScreen:p.window.contentLayoutRect]),
        @"headerWindow":@(p.header.window.windowNumber),@"ownerWindow":@(p.window.windowNumber)};
}
static void snapshot(Probe *p,NSString *name) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:geometry(p) options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[output stringByAppendingPathComponent:[name stringByAppendingString:@".json"]] atomically:YES];
    NSRect f=p.window.frame;
    CGFloat top=NSMaxY(NSScreen.screens.firstObject.frame)-NSMaxY(f);
    NSTask *capture=[NSTask new];capture.executableURL=[NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
    capture.arguments=@[@"-x",@"-R",[NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f",f.origin.x,top,f.size.width,f.size.height],
        [output stringByAppendingPathComponent:[name stringByAppendingString:@".png"]]];
    if([capture launchAndReturnError:nil]) { [capture waitUntilExit]; }
}
static void mouse(NSView *v,NSEventType type,NSPoint local) {
    NSPoint point=[v convertPoint:local toView:nil];
    NSEvent *e=[NSEvent mouseEventWithType:type location:point modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:v.window.windowNumber
        context:nil eventNumber:1 clickCount:1 pressure:1];
    [NSApp postEvent:e atStart:NO];
}
static BOOL fullscreen(Probe *p,BOOL desired) {
    if(!!(p.window.styleMask&NSWindowStyleMaskFullScreen)!=desired) {
        p.transitioning=YES;[p.window toggleFullScreen:nil];
    }
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
    while((p.transitioning || !!(p.window.styleMask&NSWindowStyleMaskFullScreen)!=desired)
        && deadline.timeIntervalSinceNow>0) pump(.05);
    pump(.25);
    return !p.transitioning && !!(p.window.styleMask&NSWindowStyleMaskFullScreen)==desired;
}
static void paintMetal(Probe *p,id<MTLDevice> device,id<MTLCommandQueue> queue) {
    CAMetalLayer *layer=(CAMetalLayer *)p.header.layer;
    layer.device=device;layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly=YES;layer.allowsNextDrawableTimeout=YES;
    layer.contentsScale=p.header.window.backingScaleFactor;
    layer.drawableSize=CGSizeMake(p.header.bounds.size.width*layer.contentsScale,
        p.header.bounds.size.height*layer.contentsScale);
    // The side accessory spans underneath the native buttons. Its GPU layer
    // must not cover that region; geometry alone would produce a false pass.
    CAShapeLayer *mask=[CAShapeLayer layer];
    CGPathRef path=CGPathCreateWithRect(CGRectMake(76,0,MAX(0,p.header.bounds.size.width-76),p.header.bounds.size.height),NULL);
    mask.path=path;CGPathRelease(path);layer.mask=mask;
    if(!p.header.window || NSIsEmptyRect(p.header.visibleRect)) return;
    id<CAMetalDrawable> drawable=[layer nextDrawable];
    if(!drawable) return;
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=drawable.texture;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(.925,.929,.945,1);
    id<MTLCommandBuffer> buffer=[queue commandBuffer];
    [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
    [buffer presentDrawable:drawable];[buffer commit];[buffer waitUntilCompleted];
    // Public NSView property, native NSButtons are still rendered by AppKit.
    // System reveal may change alpha later: the production host must observe
    // this lifecycle rather than assume hidden=false means visible.
    if(p.window.toolbar.visible) for(NSNumber *kind in @[@(NSWindowCloseButton),@(NSWindowMiniaturizeButton),@(NSWindowZoomButton)])
        [p.window standardWindowButton:kind.integerValue].alphaValue=1;
}
int main(int argc,const char **argv) { @autoreleasepool {
    output=argc>1?@(argv[1]):@"/tmp/zenit-fullscreen-header-prototype";
    [[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
    checks=[NSMutableArray array];
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp finishLaunching];
    Probe *p=[Probe new];
    p.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,900,600)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    p.window.releasedWhenClosed=NO;p.window.delegate=p;
    p.window.title=@"Zenit — native fullscreen Header prototype";
    p.window.titleVisibility=NSWindowTitleHidden;p.window.titlebarAppearsTransparent=YES;
    p.window.collectionBehavior=NSWindowCollectionBehaviorFullScreenPrimary;
    p.window.contentView.wantsLayer=YES;p.window.contentView.layer.backgroundColor=NSColor.whiteColor.CGColor;
    NSTextField *body=[NSTextField labelWithString:@"Body anchor — must not jump when the Header is revealed"];
    body.frame=NSMakeRect(30,500,650,25);[p.window.contentView addSubview:body];
    p.header=[[ProbeHeader alloc] initWithFrame:NSMakeRect(0,0,900,38)];
    p.header.wantsLayer=YES;p.header.layer=[CAMetalLayer layer];
    p.input=[[NSTextField alloc] initWithFrame:NSMakeRect(90,6,270,26)];
    p.input.stringValue=@"Zenit Header · 中文";[p.header addSubview:p.input];
    p.button=[NSButton buttonWithTitle:@"Header action" target:p action:@selector(clicked:)];
    p.button.frame=NSMakeRect(380,6,140,26);[p.header addSubview:p.button];
    p.accessory=[NSTitlebarAccessoryViewController new];p.accessory.view=p.header;
    p.accessory.layoutAttribute=NSLayoutAttributeTrailing;p.accessory.automaticallyAdjustsSize=NO;
    p.window.toolbar=[[NSToolbar alloc] initWithIdentifier:@"Zenit.HeaderPrototype"];
    p.window.toolbarStyle=NSWindowToolbarStyleUnifiedCompact;
    p.window.toolbar.visible=YES;[p.window addTitlebarAccessoryViewController:p.accessory];
    [p.window center];[p.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];pump(.4);
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();id<MTLCommandQueue> queue=[device newCommandQueue];
    paintMetal(p,device,queue);snapshot(p,@"windowed");
    check(@"enter-fullscreen",fullscreen(p,YES),geometry(p));
    p.header.frame=NSMakeRect(0,0,p.window.frame.size.width,38);pump(.3);
    paintMetal(p,device,queue);snapshot(p,@"pinned");
    NSRect hr=screenRect(p.header),cr=screenRect([p.window standardWindowButton:NSWindowCloseButton]);
    check(@"native-controls-same-row",fabs(NSMidY(hr)-NSMidY(cr))<=4 && ![p.window standardWindowButton:NSWindowCloseButton].hidden
        && [p.window standardWindowButton:NSWindowCloseButton].alphaValue>.99,geometry(p));
    NSRect closeInHeader=[p.header convertRect:[p.window standardWindowButton:NSWindowCloseButton].bounds
        fromView:[p.window standardWindowButton:NSWindowCloseButton]];
    check(@"native-button-region-uncovered",NSMaxX(closeInHeader)<76,@(NSMaxX(closeInHeader)));
    mouse(p.button,NSEventTypeLeftMouseDown,NSMakePoint(70,13));mouse(p.button,NSEventTypeLeftMouseUp,NSMakePoint(70,13));pump(.1);
    check(@"header-button-native-routing",p.clicks==1,@(p.clicks));
    mouse(p.header,NSEventTypeRightMouseDown,NSMakePoint(600,19));mouse(p.header,NSEventTypeRightMouseUp,NSMakePoint(600,19));pump(.1);
    check(@"header-right-click-native-routing",p.header.rightClicks==1,@(p.header.rightClicks));
    [p.header.window makeFirstResponder:p.input];
    NSTextView *editor=(NSTextView *)p.header.window.firstResponder;
    BOOL textEditor=[editor isKindOfClass:NSTextView.class];
    if(textEditor) { [editor setSelectedRange:NSMakeRange(editor.string.length,0)];[editor insertText:@"你好" replacementRange:NSMakeRange(NSNotFound,0)]; }
    check(@"header-text-client",textEditor && [p.input.stringValue hasSuffix:@"你好"],p.input.stringValue);
    NSRect before=screenRect(body);
    [p.window makeFirstResponder:nil];p.window.toolbar.visible=NO;pump(.5);
    snapshot(p,@"autohide");
    check(@"autohide-clips-header",NSIsEmptyRect(p.header.visibleRect),geometry(p));
    check(@"autohide-does-not-move-body",fabs(screenRect(body).origin.y-before.origin.y)<.5,geometry(p));
    // A visible toolbar is the public reveal lease used by the tabbed host.
    p.window.toolbar.visible=YES;[p.accessory removeFromParentViewController];
    [p.window addTitlebarAccessoryViewController:p.accessory];pump(.3);
    paintMetal(p,device,queue);
    check(@"reveal-lock-visible",p.header.visibleRect.size.height>=37,geometry(p));
    check(@"reveal-lock-does-not-move-body",fabs(screenRect(body).origin.y-before.origin.y)<.5,geometry(p));
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Header commands"];menu.delegate=p;
    for(NSString *title in @[@"分享",@"历史",@"全屏 / 退出全屏"]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(clicked:) keyEquivalent:@""];
        item.target=p;[menu addItem:item];
    }
    NSTimer *menuInput=[NSTimer timerWithTimeInterval:.2 repeats:NO block:^(NSTimer *timer) {
        snapshot(p,@"menu");
        for(NSNumber *code in @[@125,@36]) {
            NSString *characters=code.intValue==125?@"\uf701":@"\r";
            NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                windowNumber:p.header.window.windowNumber context:nil characters:characters
                charactersIgnoringModifiers:characters isARepeat:NO keyCode:code.unsignedShortValue];
            [NSApp postEvent:event atStart:NO];
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:menuInput forMode:NSRunLoopCommonModes];
    // Watchdog is a failure escape, never an acceptance shortcut.
    NSTimer *watchdog=[NSTimer timerWithTimeInterval:3 repeats:NO block:^(NSTimer *timer) { [menu cancelTracking]; }];
    [[NSRunLoop mainRunLoop] addTimer:watchdog forMode:NSRunLoopCommonModes];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(600,0) inView:p.header];
    [watchdog invalidate];pump(.1);
    check(@"header-menu-native-keyboard-selection",p.menuOpens==1 && p.clicks==2,@{@"opens":@(p.menuOpens),@"actions":@(p.clicks)});
    NSButton *zoom=[p.window standardWindowButton:NSWindowZoomButton];
    paintMetal(p,device,queue);
    mouse(zoom,NSEventTypeLeftMouseDown,NSMakePoint(zoom.bounds.size.width/2,zoom.bounds.size.height/2));
    mouse(zoom,NSEventTypeLeftMouseUp,NSMakePoint(zoom.bounds.size.width/2,zoom.bounds.size.height/2));pump(1.5);
    check(@"native-green-button-exits-fullscreen",!(p.window.styleMask&NSWindowStyleMaskFullScreen),geometry(p));
    check(@"exit-fullscreen",fullscreen(p,NO),geometry(p));
    check(@"header-text-survives-exit",[p.input.stringValue hasSuffix:@"你好"],p.input.stringValue);
    paintMetal(p,device,queue);snapshot(p,@"restored");
    for(int i=0;i<2;i++) {
        check([NSString stringWithFormat:@"repeat-enter-%d",i],fullscreen(p,YES),geometry(p));
        check([NSString stringWithFormat:@"repeat-exit-%d",i],fullscreen(p,NO),geometry(p));
    }
    [p.accessory removeFromParentViewController];p.window.toolbar=nil;[p.window close];
    BOOL passed=YES;for(NSDictionary *c in checks) if(![c[@"passed"] boolValue]) passed=NO;
    NSDictionary *result=@{@"passed":@(passed),@"os":NSProcessInfo.processInfo.operatingSystemVersionString,
        @"scope":@"Public AppKit hosting prototype; not Zenit input/IME/menu acceptance",@"checks":checks};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[output stringByAppendingPathComponent:@"results.json"] atomically:YES];
    return passed?0:1;
}}
