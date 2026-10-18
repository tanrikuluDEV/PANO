import SwiftUI
import UIKit

// The shared code is the Mac app's, copied. These stand-ins give it the few AppKit names it uses, backed by
// UIKit, so most files compile unchanged and new Mac features can be copied across with little editing.

typealias NSColor = UIColor
typealias NSImage = UIImage

extension UIColor {
    convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    init(nsColor: UIColor) { self.init(uiColor: nsColor) }
}

extension Image {
    init(nsImage: UIImage) { self.init(uiImage: nsImage) }
}

/// `NSWorkspace.shared.open(url)` → Safari / the app that owns the link.
final class NSWorkspace {
    static let shared = NSWorkspace()
    @discardableResult func open(_ url: URL) -> Bool {
        UIApplication.shared.open(url)
        return true
    }
    /// iOS can't name the app; a non-nil answer means some app takes the link.
    func urlForApplication(toOpen url: URL) -> URL? { UIApplication.shared.canOpenURL(url) ? url : nil }
}

/// `NSPasteboard.general.setString(_, forType: .string)` → UIPasteboard.
final class NSPasteboard {
    enum PasteboardType { case string }
    static let general = NSPasteboard()
    func clearContents() {}
    func setString(_ s: String, forType: PasteboardType) { UIPasteboard.general.string = s }
}

/// Only the material names matter on iOS; every one becomes the system's thin blur.
enum NSVisualEffectView {
    enum Material { case sidebar, underWindowBackground, popover, hudWindow, menu, headerView, windowBackground, contentBackground }
}

struct VisualEffect: View {
    var material: NSVisualEffectView.Material = .sidebar
    var body: some View { Rectangle().fill(.ultraThinMaterial) }
}

func NSLog(_ s: String) { print(s) }
