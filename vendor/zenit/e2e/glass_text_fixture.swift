// Rasterize identical real text for both renderers, including small glyphs
// that expose a sharp transmission core hidden by low-frequency grid tests.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let dir = CommandLine.arguments[1]
let width = 1280, height = 960
func fixture(_ name: String, media: Bool) throws {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress!, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 2, y: -2)
        if media {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(dir)/mixed.png") as CFURL, nil)!
            ctx.saveGState(); ctx.translateBy(x: 0, y: 480); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(CGImageSourceCreateImageAtIndex(source, 0, nil)!, in: CGRect(x: 0, y: 0, width: 640, height: 480))
            ctx.restoreGState()
        } else {
            ctx.setFillColor(CGColor(gray: 0.98, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        let labels = ["Button", "Checkbox", "Switch", "Radio", "Slider", "Input", "TextArea", "Select", "ComboBox", "DATA DISPLAY", "Badge", "Content row 11", "Content row 12", "Content row 13"]
        for column in 0..<3 {
            for (row, text) in labels.enumerated() {
                let font = NSFont.systemFont(ofSize: row == 9 ? 10 : 13, weight: row == 9 ? .semibold : .regular)
                let color = media && column == 1 ? NSColor.white : NSColor(calibratedWhite: 0.08, alpha: 1)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
                ctx.saveGState(); ctx.translateBy(x: CGFloat(28 + column * 210), y: CGFloat(24 + row * 31)); ctx.scaleBy(x: 1, y: -1)
                ctx.textPosition = .zero; CTLineDraw(line, ctx); ctx.restoreGState()
            }
        }
        let image = ctx.makeImage()!
        let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw NSError(domain: "PNG write failed", code: 1) }
    }
    try Data(bytes).write(to: URL(fileURLWithPath: "\(dir)/\(name).rgba"))
}
try fixture("text-light", media: false)
try fixture("text-mixed", media: true)

func foreground(_ name: String, width: Int, height: Int, clear: Bool, toolbar: Bool) throws {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress!, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 2, y: -2)
        func line(_ text: String, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, secondary: Bool = false) {
            let color = clear ? NSColor.white.withAlphaComponent(secondary ? 0.8 : 1) : NSColor(calibratedWhite: secondary ? 0.35 : 26.0/255, alpha: 1)
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]))
            ctx.saveGState(); ctx.translateBy(x: toolbar ? 12 : 16, y: y); ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero; CTLineDraw(text, ctx); ctx.restoreGState()
        }
        if toolbar { line("Floating glass toolbar", 23, 13, .semibold) }
        else {
            line(clear ? "Clear" : "Interactive", 28, 15, .semibold)
            line(clear ? "media-rich backdrop" : "hover / press me", 49, 12, .regular, secondary: true)
            line(clear ? "Backdrop shows through." : "Glass responds to touch.", 82, 13, .regular)
        }
        let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
        guard CGImageDestinationFinalize(out) else { throw NSError(domain: "Foreground PNG write failed", code: 1) }
    }
    // Zenit's public image texture API accepts straight RGBA; the CGContext
    // buffer is premultiplied. PNG already stores the corresponding straight color.
    for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i+3] > 0 {
        for c in 0..<3 { bytes[i+c] = UInt8(min(255, (Int(bytes[i+c]) * 255 + Int(bytes[i+3])/2) / Int(bytes[i+3]))) }
    }
    try Data(bytes).write(to: URL(fileURLWithPath: "\(dir)/\(name).rgba"))
}
try foreground("foreground-regular-panel", width: 480, height: 208, clear: false, toolbar: false)
try foreground("foreground-clear-panel", width: 480, height: 208, clear: true, toolbar: false)
try foreground("foreground-toolbar", width: 840, height: 88, clear: false, toolbar: true)
