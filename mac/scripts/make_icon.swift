// Draws the app icon from the design (1024²) and writes it to the path in argv[1].
import AppKit

func oklch(_ l: Double, _ c: Double, _ h: Double) -> NSColor {
    let hr = h * .pi / 180, a = c * cos(hr), b = c * sin(hr)
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b, m_ = l - 0.1055613458 * a - 0.0638541728 * b, s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
    func g(_ x: Double) -> CGFloat { let v = min(max(x, 0), 1); return CGFloat(v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055) }
    return NSColor(srgbRed: g(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S), green: g(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S), blue: g(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S), alpha: 1)
}

let size: CGFloat = 1024, k = size / 168
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Design coordinates are top-left based; flip.
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * k, y: size - (y + h) * k, width: w * k, height: h * k) }

let accent = oklch(0.42, 0.11, 262), line = oklch(0.70, 0.02, 82)
let inset: CGFloat = 40   // macOS icon grid margin
let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let clip = NSBezierPath(roundedRect: body, xRadius: 214, yRadius: 214)
clip.addClip()
NSGradient(starting: oklch(0.985, 0.012, 85), ending: oklch(0.935, 0.020, 82))!.draw(in: body, angle: -80)

// "P." — bold sans, deep-blue P with a lighter blue full stop, centred on cap height (design: 96px on a 168px tile)
let fontSize = body.height * 96 / 168
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let kern = -0.05 * fontSize
let str = NSMutableAttributedString(string: "P", attributes: [.font: font, .foregroundColor: oklch(0.42, 0.11, 262), .kern: kern])
str.append(NSAttributedString(string: ".", attributes: [.font: font, .foregroundColor: oklch(0.62, 0.15, 262), .kern: kern]))
let w = str.size().width + kern   // trailing kern
let baseline = body.midY - font.capHeight / 2
str.draw(at: NSPoint(x: body.midX - w / 2, y: baseline + font.descender))
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
