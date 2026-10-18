import SwiftUI
import AVFoundation

/// Floating mini player for Canlı TV while another tab is open. Drag it anywhere; on release it snaps to the
/// nearest corner (a quick flick counts), and that corner is remembered. Hover shows the channel, a way back
/// to the full player and ✕; clicking the video also goes back. Same AVPlayer as the tab, so nothing restarts.
struct MiniTVPlayer: View {
    @Environment(AppStore.self) private var store
    @State private var corner = Corner(rawValue: UserDefaults.standard.string(forKey: "miniTVCorner") ?? "") ?? .bottomTrailing
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var hover = false

    enum Corner: String, CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    private let size = CGSize(width: 320, height: 180)
    private let margin: CGFloat = 16
    /// Keeps the top corners clear of the light/dark switch and each screen's title row.
    private let topInset: CGFloat = 52

    var body: some View {
        GeometryReader { g in
            let home = center(of: corner, in: g.size)
            card
                .frame(width: size.width, height: size.height)
                .scaleEffect(dragging ? 1.03 : 1)
                .position(x: home.x + drag.width, y: home.y + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in dragging = true; drag = v.translation }
                        .onEnded { v in
                            let end = CGPoint(x: home.x + v.predictedEndTranslation.width, y: home.y + v.predictedEndTranslation.height)
                            let target = Corner.allCases.min { dist(center(of: $0, in: g.size), end) < dist(center(of: $1, in: g.size), end) } ?? corner
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                corner = target; drag = .zero; dragging = false
                            }
                            UserDefaults.standard.set(target.rawValue, forKey: "miniTVCorner")
                        }
                )
        }
    }

    private func center(of c: Corner, in s: CGSize) -> CGPoint {
        let left = margin + size.width / 2, right = s.width - margin - size.width / 2
        let top = topInset + size.height / 2, bottom = s.height - margin - size.height / 2
        switch c {
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: bottom)
        case .bottomTrailing: return CGPoint(x: right, y: bottom)
        }
    }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private var card: some View {
        let tv = store.tv
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            Color.black
            VideoLayerView(player: tv.player)
            if tv.state == .loading { ProgressView().controlSize(.small).tint(.white) }
            if case .failed = tv.state {
                Label("Yayın açılamadı", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.ui(11.5)).foregroundStyle(.white.opacity(0.85))
            }
            if hover || dragging { controls }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(T.glass ? AnyShapeStyle(T.glassEdge) : AnyShapeStyle(Color.white.opacity(0.15)), lineWidth: 1))
        .shadow(color: .black.opacity(dragging ? 0.4 : 0.3), radius: dragging ? 26 : 18, y: dragging ? 12 : 8)
        .contentShape(shape)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture { store.screen = store.lastTVTab }
        .help("Büyütmek için tıkla · köşeye taşımak için sürükle")
        .onAppear { DispatchQueue.main.async { tv.ensurePlaying() } }
    }

    private var controls: some View {
        let tv = store.tv
        return VStack {
            HStack {
                Spacer()
                miniButton("arrow.up.left.and.arrow.down.right", "Canlı TV'ye dön") { store.screen = store.lastTVTab }
                miniButton("xmark", "Kapat") { tv.stop() }
            }
            Spacer()
            HStack(spacing: 6) {
                if tv.state == .playing {
                    Text("● CANLI").font(.mono(8.5, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(T.down, in: Capsule())
                }
                Text(tv.current?.name ?? "").font(.ui(12, .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
            }
        }
        .padding(8)
        .background(LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        .transition(.opacity)
    }

    private func miniButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(.black.opacity(0.45), in: Circle())
        }.buttonStyle(.plain).help(help)
    }
}

/// Bare video surface. It ignores the mouse, so the SwiftUI drag / tap / hover on top of it get every event
/// (an AVPlayerView would swallow them).
struct VideoLayerView: NSViewRepresentable {
    let player: AVPlayer
    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() { super.layout(); playerLayer.frame = bounds }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> LayerView { let v = LayerView(); v.playerLayer.player = player; return v }
    func updateNSView(_ v: LayerView, context: Context) { if v.playerLayer.player !== player { v.playerLayer.player = player } }
}
