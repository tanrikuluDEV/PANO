// Splash logo: the app icon as a rounded tile on a transparent ground, at 1x/2x/3x of 120 pt, into
// PANO/Assets.xcassets/SplashLogo.imageset. The system launch screen and the SwiftUI splash both show this image,
// so the hand-over between them doesn't move a pixel.
import AppKit

let icon = NSImage(contentsOfFile: "PANO/Assets.xcassets/AppIcon.appiconset/icon-1024.png")!
let dir = "PANO/Assets.xcassets/SplashLogo.imageset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for scale in [1, 2, 3] {
    let px = 120 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: 0, y: 0, width: px, height: px)
    NSBezierPath(roundedRect: r, xRadius: CGFloat(px) * 0.225, yRadius: CGFloat(px) * 0.225).addClip()
    icon.draw(in: r)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/splash@\(scale)x.png"))
}
let json = """
{"images":[{"filename":"splash@1x.png","idiom":"universal","scale":"1x"},{"filename":"splash@2x.png","idiom":"universal","scale":"2x"},{"filename":"splash@3x.png","idiom":"universal","scale":"3x"}],"info":{"version":1,"author":"xcode"}}
"""
try! json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
