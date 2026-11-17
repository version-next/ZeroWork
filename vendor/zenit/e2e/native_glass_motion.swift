// Lossless window frames with WindowServer presentation timestamps. The same
// capture path is used for the SwiftUI reference and the production Metal app.
import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreMedia
import CoreImage
import ImageIO
import UniformTypeIdentifiers

private func hostSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
private func saveJSON(_ value: Any, _ path: String) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: path), options: .atomic)
}
private func delay(_ seconds: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
final class FrameWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "glass.capture.frames")
    let folder: String
    let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    var frames: [[String: Any]] = []
    var failure: String?
    init(_ folder: String) throws {
        self.folder = folder
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.failure = "\(error)" } }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first, let status = info[.status] as? Int,
              status == SCFrameStatus.complete.rawValue || status == SCFrameStatus.started.rawValue,
              let pixels = buffer.imageBuffer else { return }
        do {
            guard CVPixelBufferGetWidth(pixels) == 1280, CVPixelBufferGetHeight(pixels) == 960,
                  let scale = info[.scaleFactor] as? Double, scale == 2,
                  let contentScale = info[.contentScale] as? Double, abs(contentScale - 1) < 0.001,
                  let displayTime = info[.displayTime] as? UInt64 else {
                throw NSError(domain: "Invalid frame geometry or missing presentation clock: \(info)", code: 70)
            }
            let time = CMClockMakeHostTimeFromSystemUnits(displayTime).seconds
            let source = CIImage(cvPixelBuffer: pixels)
            guard let image = ci.createCGImage(source, from: source.extent, format: .BGRA8,
                                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
                throw NSError(domain: "Unable to read a presented window frame", code: 71)
            }
            let name = String(format: "frame-%04d.png", frames.count)
            let url = URL(fileURLWithPath: "\(folder)/\(name)")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw NSError(domain: "Unable to create PNG", code: 72)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "PNG write failed", code: 73) }
            frames.append(["file": name, "display_time": time, "pts": buffer.presentationTimeStamp.seconds,
                           "scale": scale, "content_scale": contentScale, "status": status])
        } catch { failure = "\(error)" }
    }
}
@MainActor final class MotionModel: ObservableObject {
    @Published var x = 160.0
    @Published var y = 208.0
    @Published var width = 320.0
    @Published var height = 64.0
    @Published var hovered = false
    var transitions: [[String: Any]] = []
    var clicks = 0
    let action: String
    init(_ action: String) {
        self.action = action
        if action == "hover_press_release" { y = 140; width = 240; height = 104 }
    }
}
struct NativeMotionView: View {
    @ObservedObject var model: MotionModel
    let background: NSImage
    let foreground: NSImage?
    var radius: Double { model.action == "hover_press_release" ? 18 : 32 }
    var label: some View {
        Group {
            if let foreground { Image(nsImage: foreground).resizable().interpolation(.none) }
            else { Color.clear }
        }.frame(width: model.width, height: model.height)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .circular))
    }
    var glass: some View {
        Group {
            if model.action == "drag" {
                label
            } else {
                Button(action: { model.clicks += 1; model.transitions.append(["name": "click", "time": hostSeconds()]) }) { label }
                    .buttonStyle(.plain)
            }
        }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius, style: .circular))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: radius, style: .circular))
            .onHover { model.hovered = $0; model.transitions.append(["name": $0 ? "hover" : "leave", "time": hostSeconds()]) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): model.transitions.append(["name": "pointer", "time": hostSeconds(), "x": location.x, "y": location.y])
                case .ended: model.transitions.append(["name": "pointer_end", "time": hostSeconds()])
                }
            }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.action == "scroll" {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(0..<2) { _ in
                            Image(nsImage: background).resizable().interpolation(.none).frame(width: 640, height: 480)
                        }
                    }
                }.scrollIndicators(.hidden).frame(width: 640, height: 480)
            } else {
                Image(nsImage: background).resizable().interpolation(.none).frame(width: 640, height: 480)
            }
            if model.action == "drag" {
                glass.position(x: model.x + model.width / 2, y: model.y + model.height / 2)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        model.x = 160 + value.translation.width
                        model.y = 208 + value.translation.height
                        model.transitions.append(["name": "drag", "time": hostSeconds(), "x": model.x, "y": model.y])
                    })
            } else {
                glass.position(x: model.x + model.width / 2, y: model.y + model.height / 2)
            }
        }.frame(width: 640, height: 480).environment(\.colorScheme, .light)
    }
}
final class MotionWindow: NSWindow {
    var dispatched: [[String: Any]] = []
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        dispatched.append(["type": event.type.rawValue, "time": hostSeconds(), "x": event.locationInWindow.x, "y": event.locationInWindow.y,
                           "cg_x": event.cgEvent?.location.x ?? -1, "cg_y": event.cgEvent?.location.y ?? -1, "window": event.windowNumber])
        super.sendEvent(event)
    }
}
@MainActor final class MotionDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var events: [[String: Any]] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await run(); NSApp.terminate(nil) }
            catch { fputs("motion capture failed: \(error)\n", stderr); exit(1) }
        }
    }
    func event(_ name: String, body: () throws -> Void) rethrows {
        let before = hostSeconds(); try body()
        events.append(["name": name, "time": before, "dispatch_end": hostSeconds()])
    }
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) throws {
        guard let window, let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 480-y),
                modifierFlags: [], timestamp: hostSeconds(), windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
            throw NSError(domain: "Unable to dispatch native pointer event", code: 74)
        }
        // Queue down/up, since AppKit controls can run a tracking loop on down.
        NSApp.postEvent(e, atStart: false)
    }
    func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 5, args[1] == "native" || args[1] == "window" else {
            throw NSError(domain: "usage: native_glass_motion native ACTION FIXTURES OUT | window PID DURATION OUT", code: 64)
        }
        let native = args[1] == "native", action = args[2], out = args[4]
        let ws = NSWorkspace.shared
        guard !ws.accessibilityDisplayShouldReduceTransparency && !ws.accessibilityDisplayShouldIncreaseContrast && !ws.accessibilityDisplayShouldReduceMotion else {
            throw NSError(domain: "Accessibility material/motion fallback active", code: 65)
        }
        var model: MotionModel?
        var pid = getpid()
        var outsideOrigin: NSPoint?
        var insideOrigin: NSPoint?
        if native {
            let m = MotionModel(action); model = m
            guard let image = NSImage(contentsOfFile: "\(args[3])/mixed.png") else { throw NSError(domain: "Missing shared fixture", code: 66) }
            // Match the production AppKit window, including its transparent
            // titlebar and traffic lights. SCStream captures the whole window.
            let w = MotionWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
            w.title = "Native Glass Motion Reference"; w.isReleasedWhenClosed = false; w.acceptsMouseMovedEvents = true
            let foreground = action == "hover_press_release" ? NSImage(contentsOfFile: "\(args[3])/foreground-regular-panel.png") : nil
            if action == "hover_press_release" && foreground == nil { throw NSError(domain: "Missing shared foreground", code: 66) }
            let hosting = NSHostingView(rootView: NativeMotionView(model: m, background: image, foreground: foreground).ignoresSafeArea())
            hosting.sizingOptions = []
            w.contentView = hosting
            w.setFrame(NSRect(x: 200, y: 200, width: 640, height: 480), display: false)
            window = w
            if action == "hover_press_release" {
                // Move only this fixture window beneath the stationary pointer.
                // WindowServer then generates genuine tracking entry/exit;
                // AppKit-only mouseMoved injection does not generate them.
                let pointer = NSEvent.mouseLocation
                let outside = NSPoint(x: pointer.x - 60, y: pointer.y - 420)
                outsideOrigin = outside
                insideOrigin = NSPoint(x: pointer.x - 280, y: pointer.y - 288)
                w.setFrameOrigin(outside)
            }
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        } else {
            guard let value = Int32(action), let app = NSRunningApplication(processIdentifier: value) else { throw NSError(domain: "Production app not running", code: 67) }
            pid = value; app.activate(options: [.activateAllWindows])
        }
        try await delay(1)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let own = content.windows.first(where: { $0.owningApplication?.processID == pid && $0.frame.width == 640 && $0.frame.height >= 480 }) else {
            throw NSError(domain: "640 × 480 live window not found for pid \(pid)", code: 68)
        }
        // Both apps use a 640 × 480 content viewport. No image registration,
        // resizing, or post-capture alignment is allowed by the comparison.
        guard abs(own.frame.height - 480) < 0.01 else { throw NSError(domain: "Window includes chrome outside the required viewport: \(own.frame)", code: 69) }
        let writer = try FrameWriter(out)
        let cfg = SCStreamConfiguration(); cfg.width = 1280; cfg.height = 960
        cfg.sourceRect = CGRect(x: 0, y: 0, width: 640, height: 480)
        cfg.showsCursor = false; cfg.ignoreShadowsSingleWindow = true; cfg.scalesToFit = false
        cfg.colorSpaceName = CGColorSpace.sRGB; cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120); cfg.queueDepth = 8
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: own), configuration: cfg, delegate: writer)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        for _ in 0..<100 {
            if writer.queue.sync(execute: { !writer.frames.isEmpty || writer.failure != nil }) { break }
            try await delay(0.02)
        }
        guard writer.queue.sync(execute: { !writer.frames.isEmpty && writer.failure == nil }) else {
            throw NSError(domain: "Stream produced no valid presented frame: \(writer.queue.sync { writer.failure ?? "empty" })", code: 75)
        }
        try saveJSON(["host_time": hostSeconds(), "unix_time": Date().timeIntervalSince1970, "pid": pid], "\(out)/ready.json")
        if native {
            guard let model, window?.isKeyWindow == true, NSApp.isActive else { throw NSError(domain: "Native interaction window inactive", code: 76) }
            try await delay(0.3)
            switch action {
            case "morph":
                event("morph") { withAnimation(.timingCurve(1.0/3, 0, 2.0/3, 1, duration: 0.3)) {
                    model.x = 200; model.y = 160; model.width = 240; model.height = 160
                } }
                try await delay(1)
            case "hover_press_release":
                guard let insideOrigin, let outsideOrigin else { throw NSError(domain: "Native hover geometry missing", code: 84) }
                window?.setFrameOrigin(insideOrigin)
                try await delay(0.2) // let WindowServer commit the new screen origin
                try event("hover") { try mouse(.mouseMoved, 280, 192) }; try await delay(0.5)
                try event("press") { try mouse(.leftMouseDown, 280, 192) }; try await delay(0.5)
                try event("release") { try mouse(.leftMouseUp, 280, 192) }; try await delay(0.5)
                window?.setFrameOrigin(outsideOrigin)
                try await delay(0.2)
                try event("leave") { try mouse(.mouseMoved, 60, 60) }; try await delay(1)
            case "drag":
                try event("drag_start") { try mouse(.leftMouseDown, 320, 240) }
                for i in 1...8 {
                    try await delay(0.04)
                    try event("drag_\(i)") { try mouse(.leftMouseDragged, 320 + Double(i)*10, 240 + Double(i)*3) }
                }
                try event("drag_end") { try mouse(.leftMouseUp, 400, 264) }; try await delay(1)
            case "scroll":
                for i in 1...8 {
                    try await delay(0.04)
                    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0) else { throw NSError(domain: "Wheel creation failed", code: 77) }
                    e.location = CGPoint(x: 100, y: 380)
                    guard let event = NSEvent(cgEvent: e) else { throw NSError(domain: "Native wheel conversion failed", code: 78) }
                    // Dispatch to the native window under the fixture's scroll region.
                    self.event("scroll_\(i)") { window?.contentView?.hitTest(NSPoint(x: 100, y: 380))?.scrollWheel(with: event) }
                }
                try await delay(1)
            default: throw NSError(domain: "Unknown native action \(action)", code: 79)
            }
            guard window?.isKeyWindow == true, NSApp.isActive else { throw NSError(domain: "Native window lost activation during capture", code: 80) }
        } else {
            guard let seconds = Double(args[3]), seconds > 0, seconds <= 20 else { throw NSError(domain: "Invalid capture duration", code: 81) }
            try await delay(seconds)
        }
        try await stream.stopCapture()
        let frames = writer.queue.sync { writer.frames }, error = writer.queue.sync { writer.failure }
        if let error { throw NSError(domain: error, code: 82) }
        let finalGeometry: [Double] = [model?.x ?? 0, model?.y ?? 0, model?.width ?? 0, model?.height ?? 0]
        let timeline: [String: Any] = ["schema_version": 1, "renderer": native ? "SwiftUI.glassEffect.interactive" : "Zenit.production.Metal",
                      "capture": "SCStream.lossless.sRGB", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                      "scale": 2, "viewport": [640, 480], "window_frame": [own.frame.origin.x, own.frame.origin.y, own.frame.width, own.frame.height],
                      "events": events, "frames": frames, "hover_detected": model?.hovered ?? false,
                      "transitions": model?.transitions ?? [], "clicks": model?.clicks ?? 0,
                      "dispatched": (window as? MotionWindow)?.dispatched ?? [],
                      "final_geometry": finalGeometry, "end_time": hostSeconds(),
                      "run_id": ProcessInfo.processInfo.environment["ZENIT_GLASS_GATE_RUN_ID"] ?? "",
                      "glass_diffusion_preference": UserDefaults.standard.bool(forKey: "NSGlassDiffusionSetting"),
                      "foreground": native && action == "hover_press_release" ? "foreground-regular-panel" : "none",
                      "reduce_transparency": ws.accessibilityDisplayShouldReduceTransparency,
                      "increase_contrast": ws.accessibilityDisplayShouldIncreaseContrast,
                      "reduce_motion": ws.accessibilityDisplayShouldReduceMotion,
                      "active_key_window": native ? (window?.isKeyWindow == true && NSApp.isActive) : (NSRunningApplication(processIdentifier: pid)?.isActive == true)]
        try saveJSON(timeline, "\(out)/timeline.json")
        if native && action == "hover_press_release" {
            // A complete frame stays on screen until replaced. A native effect
            // may leave this empty-label fixture unchanged on the recorded OS;
            // accept that only after its real hover and click callbacks prove
            // that input was received. Never manufacture duplicate PNG frames.
            guard model?.clicks == 1, model?.hovered == false,
                  model?.transitions.contains(where: { $0["name"] as? String == "hover" }) == true,
                  model?.transitions.contains(where: { $0["name"] as? String == "leave" }) == true else {
                throw NSError(domain: "Native hover/click states missing; diagnostic timeline saved", code: 85)
            }
        } else {
            guard frames.count >= 2 else { throw NSError(domain: "Missing motion frames; diagnostic timeline saved", code: 83) }
        }
        print("Captured \(frames.count) presented frames, \(events.count) native events")
    }
}
@main @MainActor struct NativeMotionMain {
    static func main() {
        let app = NSApplication.shared, delegate = MotionDelegate()
        app.delegate = delegate; app.setActivationPolicy(CommandLine.arguments.dropFirst().first == "window" ? .accessory : .regular)
        app.run(); withExtendedLifetime(delegate) {}
    }
}
