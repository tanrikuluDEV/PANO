import SwiftUI
#if os(macOS)
#if os(macOS)
import AppKit
#endif
#endif

// MARK: - Text helpers

struct Eyebrow: View {
    let text: String
    var size: CGFloat = 10
    var body: some View {
        Text(text).font(.mono(size)).tracking(size * 0.12).foregroundStyle(T.ink3)
    }
}

struct LinkText: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(text).font(.ui(12)).foregroundStyle(T.accent) }.buttonStyle(.plain)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    var radius: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        if T.glass {
            // frosted pane: live blur of the backdrop, a milky tint, a rim of light and a soft lift
            let shape = RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
            content
                .padding(padding)
                .background { shape.fill(.ultraThinMaterial); shape.fill(T.paper2) }
                .overlay(shape.strokeBorder(T.glassEdge, lineWidth: 1))
                .clipShape(shape)
                .shadow(color: T.glassShadow, radius: 18, y: 8)
        } else {
            content
                .padding(padding)
                .background(T.paper2, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(T.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

/// Window background. Glass: the desktop blurred through the window, washed with the theme's colour and three
/// soft light pools (theme hue and its two neighbours) for the panes to frost over. Klasik: plain paper.
/// The pools are radial gradients rather than blurred shapes, so the backdrop costs nothing to redraw.
struct AppBackdrop: View {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var body: some View {
        if T.glass {
            let h = ColorTheme.current.hue
            GeometryReader { g in
                let r = max(g.size.width, g.size.height)
                ZStack {
                    VisualEffect(material: material)
                    LinearGradient(colors: [dyn(oklch(0.95, 0.02, h, 0.78), oklch(0.19, 0.035, h, 0.84)),
                                            dyn(oklch(0.91, 0.035, h + 35, 0.78), oklch(0.14, 0.03, h + 35, 0.84))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    pool(dyn(oklch(0.78, 0.13, h, 0.60), oklch(0.45, 0.14, h, 0.55)), at: UnitPoint(x: 0.12, y: 0.10), radius: r * 0.55)
                    pool(dyn(oklch(0.82, 0.11, h + 60, 0.50), oklch(0.40, 0.12, h + 60, 0.45)), at: UnitPoint(x: 0.92, y: 0.30), radius: r * 0.50)
                    pool(dyn(oklch(0.84, 0.10, h - 70, 0.50), oklch(0.38, 0.12, h - 70, 0.45)), at: UnitPoint(x: 0.45, y: 1.05), radius: r * 0.60)
                }
            }
        } else {
            T.paper
        }
    }

    private func pool(_ c: Color, at p: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0)], center: p, startRadius: 0, endRadius: radius)
    }
}

extension View {
    /// Background for bars that sit over scrolling content (pinned day headers): frosted in glass, paper otherwise.
    @ViewBuilder func barBackground() -> some View {
        if T.glass { self.background(.regularMaterial) } else { self.background(T.paper) }
    }
    /// Background for a large side panel (the sidebar, the popover): a translucent frosted sheet in glass,
    /// the original vibrancy + tint in klasik.
    @ViewBuilder func panelBackground(_ material: NSVisualEffectView.Material = .sidebar) -> some View {
        if T.glass {
            self.background { ZStack { Rectangle().fill(.ultraThinMaterial); T.sidebar } }
        } else {
            self.background(ZStack { VisualEffect(material: material); T.sidebar })
        }
    }
}

struct Rule: View {
    var color: Color = T.rule
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

struct VRule: View {
    var color: Color = T.rule
    var body: some View { Rectangle().fill(color).frame(width: 1) }
}

#if os(macOS)
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = material; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
#endif

// MARK: - Controls

/// Small segmented control used for day / range / interval pickers (paper-3 track, paper-2 thumb).
struct Segmented<ID: Hashable>: View {
    let items: [(id: ID, label: String)]
    @Binding var selection: ID
    var mono = false
    var radius: CGFloat = 7
    var hPad: CGFloat = 11
    var highlight = true
    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.id) { it in
                let sel = highlight && it.id == selection
                Button { selection = it.id } label: {
                    Text(it.label)
                        .font(mono ? .mono(11) : .ui(12, sel ? .semibold : .regular))
                        .foregroundStyle(sel ? T.ink : T.ink2)
                        .padding(.horizontal, hPad).padding(.vertical, 6)
                        .background(sel ? T.paper2 : .clear, in: RoundedRectangle(cornerRadius: radius - 2))
                        .shadow(color: .black.opacity(sel ? 0.06 : 0), radius: 1, y: 0.5)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(T.paper3, in: RoundedRectangle(cornerRadius: radius))
    }
}

struct Pill: View {
    let text: String
    var selected = false
    var body: some View {
        Text(text)
            .font(.ui(12, selected ? .semibold : .regular))
            .foregroundStyle(selected ? T.accentInk : T.ink2)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(selected ? T.accent : T.paper2, in: Capsule())
            .overlay(Capsule().stroke(selected ? T.accent : T.rule, lineWidth: 1))
            .contentShape(Capsule())
    }
}

struct Checkbox: View {
    let checked: Bool
    var size: CGFloat = 15
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(checked ? T.accent : T.rule, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(checked ? T.accent : .clear))
            .overlay { if checked { Text("✓").font(.system(size: size * 0.66, weight: .bold)).foregroundStyle(T.accentInk) } }
            .frame(width: size, height: size)
    }
}

struct ToggleSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() } } label: {
            Capsule().fill(isOn ? T.accent : T.rule).frame(width: 36, height: 21)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 17, height: 17).shadow(color: .black.opacity(0.25), radius: 1, y: 1).padding(2)
                }
        }.buttonStyle(.plain)
    }
}

struct PulseDot: View {
    let color: Color
    var pulsing = false
    var size: CGFloat = 6
    @State private var dim = false
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(pulsing && dim ? 0.25 : 1)
            .onAppear { updatePulse() }
            .onChange(of: pulsing) { updatePulse() }
    }

    /// Restarts (or stops) the blink whenever `pulsing` changes, e.g. half-time → second half.
    private func updatePulse() {
        dim = false
        guard pulsing else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Team crest from ESPN when available, otherwise the 3-letter code.
struct TeamBadge: View {
    let code: String
    var logo: String? = nil
    var size: CGFloat = 17
    var body: some View {
        let r: CGFloat = size < 20 ? 4 : 5
        ZStack {
            if let logo, let url = URL(string: logo) {
                CachedImage(url: url) { codeText }
                    .padding(size * 0.1)
            } else { codeText }
        }
        .frame(width: size, height: size)
        .background(T.paper3, in: RoundedRectangle(cornerRadius: r))
        .overlay(RoundedRectangle(cornerRadius: r).stroke(T.rule2, lineWidth: 1))
    }
    private var codeText: some View {
        Text(code).font(.mono(size < 20 ? 7 : 8, .bold)).foregroundStyle(T.ink2).minimumScaleFactor(0.6).lineLimit(1)
    }
}

/// Small in-memory image cache so crests don't flicker when the scores refresh every few seconds.
enum ImageCache {
    static let store = NSCache<NSURL, NSImage>()
}

struct CachedImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { placeholder }
        }
        .task(id: url) {
            if let hit = ImageCache.store.object(forKey: url as NSURL) { image = hit; return }
            guard let data = try? await fetch(url), let img = NSImage(data: data) else { return }
            ImageCache.store.setObject(img, forKey: url as NSURL)
            image = img
        }
    }
}

struct Tag: View {
    let text: String
    var accent = false
    var body: some View {
        Text(text).font(.mono(10, .regular)).foregroundStyle(accent ? T.accent : T.ink2)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(accent ? T.accentSoft : T.paper3, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Images / charts

struct Striped: View {
    var label = "görsel"
    var labelSize: CGFloat = 7
    var spacing: CGFloat = 7
    var body: some View {
        ZStack {
            T.paper3
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += spacing
                }
                ctx.stroke(p, with: .color(T.stripe), lineWidth: 1)
            }
            Text(label).font(.mono(labelSize, .regular)).foregroundStyle(T.ink3)
        }
    }
}

struct NewsImage: View {
    let url: URL?
    var label = "görsel"
    var labelSize: CGFloat = 7
    var spacing: CGFloat = 7
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Striped(label: label, labelSize: labelSize, spacing: spacing)
                }
            }
        } else {
            Striped(label: label, labelSize: labelSize, spacing: spacing)
        }
    }
}

func normalized(_ pts: [ChartPoint], into rect: CGRect, pad: CGFloat = 2) -> [CGPoint] {
    guard pts.count > 1 else { return [] }
    var mn = pts.map(\.v).min()!, mx = pts.map(\.v).max()!
    // Keep a minimum visible span (0.4 % of the level) so tiny tick noise isn't blown up into a mountain range.
    let minSpan = max(abs(mx + mn) / 2 * 0.004, 1e-9)
    if mx - mn < minSpan { let mid = (mx + mn) / 2; mn = mid - minSpan / 2; mx = mid + minSpan / 2 }
    let d = mx - mn
    return pts.enumerated().map { i, p in
        CGPoint(x: rect.minX + CGFloat(i) / CGFloat(pts.count - 1) * rect.width,
                y: rect.maxY - pad - CGFloat((p.v - mn) / d) * (rect.height - pad * 2))
    }
}

struct Sparkline: View {
    let points: [ChartPoint]
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let pts = normalized(points, into: CGRect(origin: .zero, size: size))
            guard let first = pts.first else { return }
            var p = Path(); p.move(to: first); pts.dropFirst().forEach { p.addLine(to: $0) }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }
}

struct AreaChart: View {
    let points: [ChartPoint]
    var decimals = 2
    var unit = ""
    var range: ChartRange = .day
    @State private var hover: Int?

    private func plotRect(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 6, width: size.width, height: size.height - 14) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pts = normalized(points, into: plotRect(size), pad: 4)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    for i in 0..<4 {
                        let y = 10 + CGFloat(i) * 70 / 230 * size.height
                        var g = Path(); g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(g, with: .color(T.rule2), lineWidth: 1)
                    }
                    guard let first = pts.first, let last = pts.last else { return }
                    var line = Path(); line.move(to: first); pts.dropFirst().forEach { line.addLine(to: $0) }
                    var area = line
                    area.addLine(to: CGPoint(x: last.x, y: size.height - 6)); area.addLine(to: CGPoint(x: first.x, y: size.height - 6)); area.closeSubpath()
                    ctx.fill(area, with: .color(T.accentSoft))
                    ctx.stroke(line, with: .color(T.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
                if let i = hover, i < pts.count, i < points.count { marker(pts[i], points[i], size) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    guard points.count > 1, size.width > 0 else { return }
                    hover = max(0, min(points.count - 1, Int((loc.x / size.width * CGFloat(points.count - 1)).rounded())))
                case .ended:
                    hover = nil
                }
            }
        }
    }

    /// Crosshair, dot and a tooltip with the value and its date / time.
    private func marker(_ p: CGPoint, _ pt: ChartPoint, _ size: CGSize) -> some View {
        let tipW: CGFloat = 150
        let x = min(max(p.x, tipW / 2 + 4), size.width - tipW / 2 - 4)
        let below = p.y < size.height / 2
        return ZStack {
            Rectangle().fill(T.ink3.opacity(0.45)).frame(width: 1, height: size.height).position(x: p.x, y: size.height / 2)
            Circle().fill(T.accent).frame(width: 9, height: 9)
                .overlay(Circle().stroke(T.paper2, lineWidth: 2)).position(p)
            VStack(alignment: .leading, spacing: 3) {
                Text(format(pt.v, decimals: decimals) + (unit.isEmpty ? "" : " " + unit)).font(.mono(13)).foregroundStyle(T.ink)
                Text(Day.format(pt.t, range == .day || range == .week ? "d MMMM yyyy · HH:mm" : "d MMMM yyyy")).font(.mono(10, .regular)).foregroundStyle(T.ink3)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: tipW, alignment: .leading)
            .background(T.paper2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .position(x: x, y: below ? min(p.y + 44, size.height - 30) : max(p.y - 44, 30))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - State cards

struct SkeletonCard: View {
    let title: String
    var widths: [CGFloat] = [0.72, 0.96, 0.58, 0.84]
    @State private var shift: CGFloat = 0
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: title, size: 9.5)
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [T.paper3, T.rule2, T.paper3],
                                                     startPoint: UnitPoint(x: -1 + shift * 2, y: 0),
                                                     endPoint: UnitPoint(x: shift * 2, y: 0)))
                                .frame(width: geo.size.width * w)
                        }.frame(height: 12)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { shift = 1 } }
    }
}

struct ErrorCard: View {
    var eyebrow: String?
    var title = "Veri alınamadı"
    let message: String
    var actionTitle = "Tekrar dene"
    let action: () -> Void
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if let eyebrow { Eyebrow(text: eyebrow, size: 9.5) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("!").font(.ui(14)).foregroundStyle(T.down).frame(width: 26, height: 26).background(T.downSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.ui(13, .semibold))
                        Text(message).font(.ui(12)).foregroundStyle(T.ink3)
                    }
                    Button(action: action) {
                        Text(actionTitle).font(.ui(12, .medium)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(T.paper, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                    }.buttonStyle(.plain)
                }.padding(.vertical, 10)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyBox: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(.ui(13)).foregroundStyle(T.ink2)
            if let subtitle { Text(subtitle).font(.ui(12)).foregroundStyle(T.ink3) }
            if let actionTitle, let action { LinkText(text: actionTitle, action: action) }
        }
        .frame(maxWidth: .infinity).padding(22)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

struct OfflineBanner: View {
    let lastSync: Date?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(T.ink3).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("İnternet bağlantısı yok, son kaydedilen veriler gösteriliyor").font(.ui(13))
                if let lastSync { Text("Son senkron: \(Day.hm(lastSync))").font(.mono(11, .regular)).foregroundStyle(T.ink3) }
            }
            Spacer()
        }
        .padding(10).background(T.paper3, in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Section header used all over: eyebrow on the left, optional link on the right.
struct SectionHeader: View {
    let title: String
    var link: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Eyebrow(text: title)
            Spacer()
            if let link, let action { LinkText(text: link, action: action) }
        }
    }
}

/// Açık / Koyu switch shown in the window's top-right corner.
struct AppearanceSwitch: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            option("light", "Açık", "sun.max.fill")
            option("dark", "Koyu", "moon.fill")
        }
        .padding(2)
        .background(T.paper2, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule, lineWidth: 1))
    }

    private func option(_ id: String, _ label: String, _ icon: String) -> some View {
        let sel = (scheme == .dark ? "dark" : "light") == id
        return Button { store.appearance = id } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.ui(11.5, .semibold))
            }
            .foregroundStyle(sel ? T.accentInk : T.ink2)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(sel ? T.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Wrapping row of small views (chips).
struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        WrapLayout(spacing: 8) { ForEach(items) { content($0) } }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// Weather condition icon + text, e.g. ☀︎ Güneşli, 24°.
struct WeatherBadge: View {
    let weather: Weather
    var size: CGFloat = 13
    var showText = true
    var body: some View {
        let sm = weather.summary
        HStack(spacing: 6) {
            Image(systemName: sm.symbol).symbolRenderingMode(.multicolor).font(.system(size: size + 1))
            if showText { Text("\(sm.text), \(weather.tempText)").font(.ui(size)).foregroundStyle(T.ink2) }
            else { Text(weather.tempText).font(.mono(size - 1)).foregroundStyle(T.ink2) }
        }
        .help("Rüzgâr \(Int(weather.wind.rounded())) km/sa")
    }
}

/// The PANO. wordmark: bold sans, tight tracking, the full stop in the accent colour (design: section 06 — Logo).
struct PanoWordmark: View {
    var size: CGFloat = 19
    var mono = false   // single-colour use: the dot follows the ink
    var body: some View {
        (Text("PANO").tracking(-0.035 * size).foregroundStyle(T.ink)
         + Text(".").tracking(-0.035 * size).foregroundStyle(mono ? T.ink : T.accent))
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .fixedSize()
    }
}

/// The app icon tile (cream rounded square with a blue "P."), shown before the wordmark.
struct PanoMark: View {
    var size: CGFloat = 34
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.226, style: .continuous)
            .fill(LinearGradient(colors: [Color(nsColor: oklch(0.985, 0.012, 85)), Color(nsColor: oklch(0.935, 0.020, 82))],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.226, style: .continuous).stroke(Color(nsColor: oklch(0.87, 0.018, 82)), lineWidth: 0.5))
            .overlay(
                (Text("P").tracking(-0.05 * size * 0.57).foregroundStyle(Color(nsColor: oklch(0.42, 0.11, 262)))
                 + Text(".").tracking(-0.05 * size * 0.57).foregroundStyle(Color(nsColor: oklch(0.62, 0.15, 262))))
                    .font(.system(size: size * 0.57, weight: .bold))
                    .offset(x: size * 0.01)
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: size * 0.06, y: size * 0.03)
    }
}

/// Row of tappable swatches for choosing the colour theme — each shows that theme's page colour with its
/// accent as the inner dot — with a ring on the current one.
struct ColorThemeSwatches: View {
    @Binding var selection: String
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: 9) {
            ForEach(ColorTheme.allCases) { theme in
                let sel = selection == theme.rawValue
                Button { selection = theme.rawValue } label: {
                    Circle().fill(theme.paperSwatch).frame(width: size, height: size)
                        .overlay(Circle().fill(theme.swatch).padding(size * 0.26))
                        .overlay(Circle().strokeBorder(T.ink, lineWidth: sel ? 2 : 0).padding(-3))
                        .overlay(Circle().stroke(T.rule, lineWidth: sel ? 0 : 1))
                }
                .buttonStyle(.plain)
                .help(theme.name)
            }
        }
    }
}

/// Compact "related headlines" list reused by Ekonomi, Maçlar and Hava Durumu — each shows the
/// same news the Haberler category already carries, so there's no separate fetch or state to keep.
struct RelatedNews: View {
    @Environment(AppStore.self) private var store
    let title: String
    let items: [NewsItem]
    var emptyTitle = "İlgili haber yok"
    var emptySubtitle: String?
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, link: onViewAll != nil ? "Tümü →" : nil) { onViewAll?() }
            if items.isEmpty {
                EmptyBox(title: emptyTitle, subtitle: emptySubtitle)
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { i, h in
                            if i > 0 { Rule(color: T.rule2) }
                            Button { store.openNews(h) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 7) {
                                            Text(h.source.uppercased()).font(.mono(9, .regular)).tracking(0.5).foregroundStyle(T.accent)
                                            Circle().fill(T.ink3).frame(width: 3, height: 3)
                                            Text(Day.hm(h.date)).font(.mono(9.5, .regular)).foregroundStyle(T.ink3)
                                        }
                                        Text(h.title).font(.ui(13, .medium)).foregroundStyle(T.ink).lineLimit(2).multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// 🌙 sleep-timer menu, shared by the radio bar, the popover and Canlı TV (one timer for both).
/// Shows the minutes left while it runs.
struct SleepTimerMenu: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let left = store.sleepMinutesLeft
        Menu {
            Section("Uyku zamanlayıcısı") {
                ForEach(AppStore.sleepChoices, id: \.self) { m in
                    Button("\(m) dakika sonra kapat") { store.setSleepTimer(minutes: m) }
                }
            }
            if store.sleepUntil != nil {
                Divider()
                Button("Zamanlayıcıyı iptal et") { store.setSleepTimer(minutes: nil) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: left == nil ? "moon.zzz" : "moon.zzz.fill").font(.system(size: 11, weight: .medium))
                if let left { Text("\(left) dk").font(.mono(10, .medium)).monospacedDigit() }
            }
            .foregroundStyle(left == nil ? T.ink3 : T.accent)
            .padding(.horizontal, left == nil ? 4 : 7).frame(height: 26)
            .background(left == nil ? Color.clear : T.accentSoft, in: Capsule())
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(left.map { "Uyku zamanlayıcısı: \($0) dakika sonra kapanacak" } ?? "Uyku zamanlayıcısı")
    }
}

// MARK: - Phone / Mac layout

/// True in the iPhone build: screens stack their Mac side-by-side columns and use tighter margins.
#if os(iOS)
let isPhone = true
#else
let isPhone = false
#endif

/// Side by side on the Mac, stacked on the phone.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        if isPhone {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: .top, spacing: spacing) { content }
        }
    }
}

extension EdgeInsets {
    /// Padding of a screen's title block: the Mac's roomy top (under the window's traffic lights), tighter on the phone.
    static var screenHeader: EdgeInsets {
        isPhone ? .init(top: 4, leading: 16, bottom: 12, trailing: 16) : .init(top: 34, leading: 24, bottom: 14, trailing: 24)
    }
}

extension View {
    /// A row of pills: as is on the Mac, scrolled sideways on the phone.
    @ViewBuilder func phoneScroll() -> some View {
        if isPhone { ScrollView(.horizontal, showsIndicators: false) { self } } else { self }
    }
}

/// A day-by-day story list with the story beside it on the Mac; on the phone the list fills the screen and a story
/// opens on its own page.
struct NewsFeedPane: View {
    let items: [NewsItem]
    let selected: NewsItem?
    var fold = true
    var onSelect: (NewsItem) -> Void
    @State private var pushed: NewsItem?

    var body: some View {
        if isPhone {
            NewsDayList(items: items, selectedID: nil, fold: fold) { onSelect($0); pushed = $0 }
                .navigationDestination(item: $pushed) { NewsDetail(item: $0) }
        } else {
            HStack(spacing: 0) {
                NewsDayList(items: items, selectedID: selected?.id, fold: fold) { onSelect($0) }
                    .frame(width: 432)
                    .overlay(alignment: .trailing) { VRule() }
                if let n = selected { NewsDetail(item: n) }
            }
        }
    }
}
