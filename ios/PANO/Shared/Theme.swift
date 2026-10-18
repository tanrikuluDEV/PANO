import SwiftUI
#if os(macOS)
#if os(macOS)
import AppKit
#endif
#else
import UIKit
#endif
import CoreText

/// oklch → sRGB (Björn Ottosson's matrices), so the design tokens can be used verbatim.
func oklch(_ l: Double, _ c: Double, _ h: Double, _ alpha: Double = 1) -> NSColor {
    let hr = h * .pi / 180
    let a = c * cos(hr), b = c * sin(hr)
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
    let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
    let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
    let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
    func gamma(_ x: Double) -> CGFloat {
        let v = min(max(x, 0), 1)
        return CGFloat(v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
    }
    return NSColor(srgbRed: gamma(r), green: gamma(g), blue: gamma(bl), alpha: alpha)
}

func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
    #if os(macOS)
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
    #else
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    #endif
}

/// sRGB hex → colour, for the two brand surfaces.
func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// Colour theme: sets the accent *and* tints every surface (paper, cards, sidebar, rules, ink) with the theme's hue,
/// in both light and dark mode. Lacivert is the original design — Platinum light / Charcoal dark — untouched.
/// Same lightness recipe for every theme (accent L 0.42 light, L 0.74 dark) so they read as equally "weighted";
/// only hue and chroma move, which keeps text contrast the same across themes.
enum ColorTheme: String, CaseIterable, Identifiable, Codable {
    case lacivert, zumrut, bordo, amber, mor
    var id: String { rawValue }

    var name: String {
        switch self {
        case .lacivert: return "Lacivert"
        case .zumrut: return "Zümrüt"
        case .bordo: return "Bordo"
        case .amber: return "Amber"
        case .mor: return "Mor"
        }
    }
    var hue: Double {
        switch self {
        case .lacivert: return 262
        case .zumrut: return 175
        case .bordo: return 8
        case .amber: return 55
        case .mor: return 305
        }
    }
    var chroma: Double {
        switch self {
        case .lacivert: return 0.11
        case .zumrut: return 0.13
        case .bordo: return 0.14
        case .amber: return 0.13
        case .mor: return 0.13
        }
    }
    /// A fixed mid-tone swatch for the picker, independent of light/dark.
    var swatch: Color { Color(nsColor: oklch(0.58, chroma, hue)) }
    /// This theme's page colour, for previewing the background in the picker.
    var paperSwatch: Color { T.surface(self, 0.916, 0.003, 0.265, 0.022) }

    /// Extra chroma added to light surfaces, and the multiplier on dark ones. Lacivert stays neutral/Charcoal.
    var lightTint: Double { self == .lacivert ? 0 : 0.016 }
    var darkTint: Double { self == .lacivert ? 1 : 1.45 }
    /// Hue the surfaces are tinted with: Lacivert keeps the original warm-grey light / Charcoal dark hues.
    var surfaceHue: (light: Double, dark: Double) { self == .lacivert ? (85, 237.5) : (hue, hue) }

    /// The active theme. AppStore keeps this in sync with `prefs.colorTheme`; views pick the new
    /// accent up on their next redraw, which callers force with `.id(store.lookID)` at each window root.
    static var current: ColorTheme = .lacivert
}

/// Overall look. `cam` (glassmorphism, the default): a colour-wash backdrop in the theme's hues with the desktop
/// showing through, frosted translucent cards and panels. `klasik`: the original opaque paper surfaces.
enum UIStyle: String, CaseIterable, Identifiable {
    case cam, klasik
    var id: String { rawValue }
    var name: String { self == .cam ? "Cam" : "Klasik" }
    /// Kept in sync with `prefs.uiStyle` by AppStore; window roots redraw via `.id(...)` like the colour theme.
    static var current: UIStyle = .cam
}

/// Design tokens. Light surfaces are built around Platinum #E5E4E2; dark surfaces are a deepened Charcoal
/// (hue of #36454F, lower lightness). Cards, wells, sidebar and rules are lighter/darker steps of the same hue.
enum T {
    static var glass: Bool { UIStyle.current == .cam }
    /// Glass variants: translucent whites for raised surfaces, a faint theme-tinted ink for wells and rules.
    private static func tintInk(_ a: Double) -> NSColor { oklch(0.30, 0.03, ColorTheme.current.hue, a) }
    private static func white(_ a: Double) -> NSColor { NSColor(white: 1, alpha: a) }
    /// A surface token for `theme`: lightness is fixed per token, chroma and hue follow the theme.
    /// The base chroma values are the original Platinum/Charcoal ones, so Lacivert reproduces them exactly.
    /// `tint` scales how strongly this token takes the light-mode tint (cards less, sidebar more).
    static func surface(_ theme: ColorTheme, _ lL: Double, _ lC: Double, _ dL: Double, _ dC: Double,
                        tint: Double = 1, alpha: (Double, Double) = (1, 1)) -> Color {
        let h = theme.surfaceHue
        return dyn(oklch(lL, lC + theme.lightTint * tint, h.light, alpha.0), oklch(dL, dC * theme.darkTint, h.dark, alpha.1))
    }
    private static func s(_ lL: Double, _ lC: Double, _ dL: Double, _ dC: Double,
                          tint: Double = 1, alpha: (Double, Double) = (1, 1)) -> Color {
        surface(ColorTheme.current, lL, lC, dL, dC, tint: tint, alpha: alpha)
    }
    /// Ink leans toward the theme hue only slightly, so body text stays near-neutral and fully legible.
    private static func ink(_ lL: Double, _ lC: Double, _ dL: Double, _ dC: Double) -> Color {
        let t = ColorTheme.current
        return t == .lacivert ? dyn(oklch(lL, lC, 265), oklch(dL, dC, 237.5)) : dyn(oklch(lL, lC, t.hue), oklch(dL, dC, t.hue))
    }

    static var desk: Color { s(0.895, 0.003, 0.19, 0.018) }
    static var paper: Color {
        if glass { return dyn(white(0.40), white(0.06)) }
        return ColorTheme.current == .lacivert ? dyn(hex(0xE5E4E2), oklch(0.265, 0.022, 237.5)) : s(0.916, 0.003, 0.265, 0.022) }
    static var paper2: Color { glass ? dyn(white(0.52), white(0.08)) : s(0.965, 0.003, 0.325, 0.024, tint: 0.45) }   // cards stay closest to white
    static var paper3: Color { glass ? dyn(tintInk(0.06), white(0.05)) : s(0.885, 0.003, 0.30, 0.023) }
    static var sidebar: Color {
        glass ? dyn(white(0.22), oklch(0.16, 0.02, ColorTheme.current.hue, 0.30)) : s(0.875, 0.004, 0.21, 0.018, tint: 1.3, alpha: (0.80, 0.86))
    }
    static var ink: Color { ink(0.24, 0.02, 0.95, 0.006) }
    static var ink2: Color { ink(0.42, 0.015, 0.82, 0.012) }
    static var ink3: Color { ink(0.52, 0.012, 0.68, 0.014) }
    static var rule: Color { glass ? dyn(tintInk(0.13), white(0.13)) : s(0.83, 0.004, 0.39, 0.022) }
    static var rule2: Color { glass ? dyn(tintInk(0.08), white(0.08)) : s(0.865, 0.003, 0.345, 0.021) }
    /// Glass edge: bright along the top-left, fading out — the "light catching the rim" of a pane.
    static var glassEdge: LinearGradient {
        LinearGradient(colors: [dyn(white(0.85), white(0.28)), dyn(white(0.25), white(0.05))], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var glassShadow: Color { dyn(tintInk(0.10), NSColor(white: 0, alpha: 0.35)) }
    static var accent: Color { dyn(oklch(0.42, ColorTheme.current.chroma, ColorTheme.current.hue), oklch(0.74, ColorTheme.current.chroma, ColorTheme.current.hue)) }
    static var accentInk: Color { dyn(oklch(0.99, 0.004, 85), oklch(0.16, 0.02, ColorTheme.current.hue)) }
    static var accentSoft: Color { dyn(oklch(0.42, ColorTheme.current.chroma, ColorTheme.current.hue, 0.10), oklch(0.74, ColorTheme.current.chroma, ColorTheme.current.hue, 0.16)) }
    static let up = dyn(oklch(0.50, 0.13, 152), oklch(0.76, 0.15, 152))
    static let upSoft = dyn(oklch(0.50, 0.13, 152, 0.12), oklch(0.76, 0.15, 152, 0.16))
    static let down = dyn(oklch(0.52, 0.17, 27), oklch(0.70, 0.16, 27))
    static let downSoft = dyn(oklch(0.52, 0.17, 27, 0.12), oklch(0.70, 0.16, 27, 0.16))
    static var stripe: Color { glass ? dyn(tintInk(0.10), white(0.10)) : s(0.85, 0.004, 0.37, 0.021) }
    static let yellow = Color(nsColor: oklch(0.78, 0.15, 95))
}

// MARK: - Fonts

enum Fonts {
    static var petrona = false
    static var mono = false

    static func register() {
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
            }
        }
        #if os(macOS)
        let families = Set(NSFontManager.shared.availableFontFamilies)
        #else
        let families = Set(UIFont.familyNames)
        #endif
        petrona = families.contains("Petrona")
        mono = families.contains("JetBrains Mono")
    }
}

extension Font {
    /// Petrona (headings, article text) — falls back to the system serif.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        Fonts.petrona ? .custom("Petrona", size: size).weight(weight) : .system(size: size, weight: weight, design: .serif)
    }
    /// JetBrains Mono (numbers, labels) — falls back to the system monospace.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        Fonts.mono ? .custom("JetBrains Mono", size: size).weight(weight) : .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
