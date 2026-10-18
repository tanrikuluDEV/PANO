import SwiftUI
import UIKit
import AVKit
import WebKit

// iOS versions of the Mac app's AppKit-backed views (same names, so the shared screens use them unchanged).

/// Defter's lined page: a text view with a fixed 31pt line height drawn over ruled lines.
struct RuledEditor: UIViewRepresentable {
    @Binding var text: String
    static let lineHeight: CGFloat = 31

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RuledTextView {
        let v = RuledTextView()
        v.delegate = context.coordinator
        v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 20, left: 18, bottom: 20, right: 18)
        v.isScrollEnabled = false
        v.applyStyle()
        v.text = text
        return v
    }

    func updateUIView(_ v: RuledTextView, context: Context) {
        if v.text != text { v.text = text }
        v.applyStyle()
        v.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RuledEditor
        init(_ p: RuledEditor) { parent = p }
        func textViewDidChange(_ v: UITextView) { parent.text = v.text; v.setNeedsDisplay() }
    }
}

final class RuledTextView: UITextView {
    func applyStyle() {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = RuledEditor.lineHeight; ps.maximumLineHeight = RuledEditor.lineHeight
        let font = UIFont(name: Fonts.petrona ? "Petrona" : "Georgia", size: 17) ?? .systemFont(ofSize: 17)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(T.ink), .paragraphStyle: ps]
        typingAttributes = attrs
        tintColor = UIColor(T.accent)
        if textStorage.length > 0 { textStorage.addAttributes(attrs, range: NSRange(location: 0, length: textStorage.length)) }
    }

    override var intrinsicContentSize: CGSize {
        let fit = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 320, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(300, fit.height))
    }

    override func draw(_ rect: CGRect) {
        let h = RuledEditor.lineHeight
        UIColor(T.rule2).setFill()
        var y = textContainerInset.top + h - 1
        while y < bounds.height {
            UIRectFill(CGRect(x: 0, y: y, width: bounds.width, height: 1))
            y += h
        }
        super.draw(rect)
    }
}

/// Bare video surface that lets touches through to the SwiftUI gestures on top.
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.isUserInteractionEnabled = false
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }
    func updateUIView(_ v: LayerView, context: Context) { if v.playerLayer.player !== player { v.playerLayer.player = player } }
}

/// The system player: native controls, full screen and picture-in-picture.
struct TVPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = player
        c.allowsPictureInPicturePlayback = true
        c.videoGravity = .resizeAspect
        c.view.backgroundColor = .black
        c.view.layer.cornerRadius = 12
        c.view.layer.masksToBounds = true
        return c
    }
    func updateUIViewController(_ c: AVPlayerViewController, context: Context) { if c.player !== player { c.player = player } }
}

struct WebView: UIViewRepresentable {
    let page: WebPage
    func makeUIView(context: Context) -> WKWebView { page.view }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
