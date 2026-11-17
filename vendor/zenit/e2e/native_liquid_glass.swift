// The reference uses the system material, without a substitute shader or blur.
import AppKit
import SwiftUI
import ScreenCaptureKit
struct Scene: Decodable { let id, background, variant: String; let x,y,w,h,radius: Double; let tint: [Double]?; let foreground: String? }
final class ReferenceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
func captureRMSE(_ a:CGImage,_ b:CGImage) -> Double {
    let aa=NSBitmapImageRep(cgImage:a),bb=NSBitmapImageRep(cgImage:b)
    guard aa.pixelsWide==bb.pixelsWide && aa.pixelsHigh==bb.pixelsHigh,
          let ap=aa.bitmapData,let bp=bb.bitmapData else { return .infinity }
    var sum=0.0
    for y in 0..<aa.pixelsHigh { for x in 0..<aa.pixelsWide { for c in 0..<3 {
        let d=Double(ap[y*aa.bytesPerRow+x*aa.samplesPerPixel+c])-Double(bp[y*bb.bytesPerRow+x*bb.samplesPerPixel+c])
        sum += d*d
    } } }
    return sqrt(sum/Double(aa.pixelsWide*aa.pixelsHigh*3))
}
@MainActor final class Model: ObservableObject { @Published var scene: Scene; init(_ scene: Scene) {self.scene=scene} }
struct ReferenceView: View {
    @ObservedObject var model: Model
    let assets: String
    var body: some View {
        let s=model.scene
        let material: Glass = s.variant == "clear" ? .clear : .regular
        let tinted: Glass = s.tint.map { material.tint(Color(red:$0[0]/255,green:$0[1]/255,blue:$0[2]/255)) } ?? material
        ZStack(alignment:.topLeading) {
            Image(nsImage:NSImage(contentsOfFile:"\(assets)/\(s.background).png")!)
                .resizable().interpolation(.none).frame(width:640,height:480)
            Group {
                if let foreground = s.foreground {
                    Image(nsImage:NSImage(contentsOfFile:"\(assets)/\(foreground).png")!)
                        .resizable().interpolation(.none)
                } else { Color.clear }
            }.frame(width:s.w,height:s.h)
                .glassEffect(tinted,in:RoundedRectangle(cornerRadius:s.radius,style:.circular))
                .position(x:s.x+s.w/2,y:s.y+s.h/2).id(s.id)
        }.frame(width:640,height:480)
            .environment(\.colorScheme,s.background == "dark" ? .dark : .light)
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                guard CommandLine.arguments.count>=3 else {throw NSError(domain:"usage: native_liquid_glass FIXTURES OUT [process preference arguments]",code:64)}
                let assets=CommandLine.arguments[1], out=CommandLine.arguments[2]
                let ws=NSWorkspace.shared
                guard !ws.accessibilityDisplayShouldReduceTransparency && !ws.accessibilityDisplayShouldIncreaseContrast && !ws.accessibilityDisplayShouldReduceMotion else {throw NSError(domain:"Accessibility fallback active; native reference invalid",code:65)}
                let scenes=try JSONDecoder().decode([Scene].self,from:Data(contentsOf:URL(fileURLWithPath:"\(assets)/scenes.json")))
                let model=Model(scenes[0])
                window=ReferenceWindow(contentRect:NSRect(x:200,y:200,width:640,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
                window.title="Native Liquid Glass Reference";window.isReleasedWhenClosed=false
                window.isOpaque=false;window.contentView=NSHostingView(rootView:ReferenceView(model:model,assets:assets))
                window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                try FileManager.default.createDirectory(atPath:out,withIntermediateDirectories:true)
                try await Task.sleep(for:.seconds(1))
                guard window.backingScaleFactor==2 else {throw NSError(domain:"Reference requires 2x backing scale",code:66)}
                let content=try await SCShareableContent.currentProcess
                guard let own=content.windows.first(where:{$0.windowID==UInt32(window.windowNumber)}) else {throw NSError(domain:"Reference window not found",code:67)}
                let filter=SCContentFilter(desktopIndependentWindow:own)
                let cfg=SCStreamConfiguration();cfg.width=1280;cfg.height=960;cfg.showsCursor=false
                cfg.ignoreShadowsSingleWindow=true;cfg.colorSpaceName=CGColorSpace.sRGB
                var idleErrors:[String:Double]=[:]
                for scene in scenes {
                    // Rebuild the host for each independent material case.
                    // Reusing a regular circle's retained effect layer can
                    // leave the following .clear capture opaque on macOS 26.4.
                    // A fresh host exercises the requested API without a
                    // material-transition history or a stale effect surface.
                    window.contentView=NSHostingView(rootView:ReferenceView(model:Model(scene),assets:assets))
                    NSApp.activate(ignoringOtherApps:true)
                    window.makeKeyAndOrderFront(nil)
                    try await Task.sleep(for:.seconds(0.8))
                    // Activation can be asynchronous after another test/app closes.
                    // Retry activation, but never capture an inactive fallback as the reference.
                    for _ in 0..<5 where !window.isKeyWindow || !NSApp.isActive {
                        NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
                        try await Task.sleep(for:.seconds(0.1))
                    }
                    guard window.isKeyWindow && NSApp.isActive else {throw NSError(domain:"Native reference inactive: key=\(window.isKeyWindow) appActive=\(NSApp.isActive)",code:69)}
                    var cg=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:cfg)
                    var idle=cg,error=Double.infinity
                    for _ in 0..<10 {
                        try await Task.sleep(for:.seconds(0.1))
                        idle=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:cfg)
                        error=captureRMSE(cg,idle)
                        if error <= 0.5 { break }
                        cg=idle
                    }
                    guard error <= 0.5 else { throw NSError(domain:"Native material did not settle: \(scene.id) RMSE=\(error)",code:70) }
                    guard window.isKeyWindow && NSApp.isActive else { throw NSError(domain:"Native window lost activation during capture",code:69) }
                    idleErrors[scene.id]=error
                    guard cg.width==1280 && cg.height==960 else {throw NSError(domain:"Invalid capture dimensions",code:68)}
                    try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(out)/\(scene.id).png"))
                    try NSBitmapImageRep(cgImage:idle).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(out)/\(scene.id)-idle.png"))
                    print("captured \(scene.id)")
                }
                let metadata:[String:Any]=["os":ProcessInfo.processInfo.operatingSystemVersionString,"scale":2,"reduce_transparency":false,"increase_contrast":false,"reduce_motion":false,"active_key_window":true,"renderer":"SwiftUI.glassEffect","cases":scenes.map(\.id),
                    "captured_at":ISO8601DateFormatter().string(from:Date()),
                    "fixture_isolation":"fresh NSHostingView per scene",
                    "native_idle_rmse":idleErrors,
                    "run_id":ProcessInfo.processInfo.environment["ZENIT_GLASS_GATE_RUN_ID"] ?? "",
                    "glass_diffusion_preference":UserDefaults.standard.bool(forKey:"NSGlassDiffusionSetting"),
                    "process_arguments":CommandLine.arguments.dropFirst(3).map{$0}]
                try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"\(out)/metadata.json"))
                NSApp.terminate(nil)
            } catch { fputs("native reference failed: \(error)\n",stderr);exit(1) }
        }
    }
}
@main @MainActor struct NativeMain {
    static func main() {let app=NSApplication.shared;let delegate=Delegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run();withExtendedLifetime(delegate){}}
}
