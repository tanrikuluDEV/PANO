import WidgetKit
import SwiftUI

/// Home-screen (small / medium / large) and lock-screen (inline / rectangular / circular) widgets. They show the
/// snapshot the app last wrote (WidgetSnapshot): weather, Dolar / Euro / gram altın, top headlines, the followed
/// team's match. Tapping opens the matching screen, a headline opens that story.
@main
struct PANOWidgets: WidgetBundle {
    var body: some Widget { PANOWidget() }
}

struct PANOWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PANO", provider: Provider()) { entry in
            WidgetView(snap: entry.snap)
        }
        .configurationDisplayName("PANO")
        .description("Hava durumu, kurlar, manşetler ve takımının maçı.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct Entry: TimelineEntry { let date: Date; let snap: WidgetSnapshot }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: context.isPreview ? .sample : WidgetSnapshot.load() ?? .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // the app reloads the widgets whenever it has new data; this is only a fallback re-read
        let e = Entry(date: Date(), snap: WidgetSnapshot.load() ?? .sample)
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

// MARK: - Look

private enum W {
    static let navyTop = Color(red: 0.09, green: 0.15, blue: 0.31)
    static let navyBottom = Color(red: 0.14, green: 0.24, blue: 0.45)
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.72)
    static let ink3 = Color.white.opacity(0.5)
    static let rule = Color.white.opacity(0.14)
    static let up = Color(red: 0.45, green: 0.85, blue: 0.6)
    static let down = Color(red: 1.0, green: 0.55, blue: 0.5)
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

private func url(screen: String) -> URL {
    var c = URLComponents(); c.scheme = "pano"; c.host = "screen"; c.queryItems = [.init(name: "name", value: screen)]
    return c.url!
}
private func url(news id: String) -> URL {
    var c = URLComponents(); c.scheme = "pano"; c.host = "news"; c.queryItems = [.init(name: "id", value: id)]
    return c.url!
}

private func changeText(_ c: Double) -> String {
    let s = String(format: "%.2f", abs(c)).replacingOccurrences(of: ".", with: ",")
    return (c >= 0 ? "▲" : "▼") + "%" + s
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snap: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .systemMedium: home { medium }
        case .systemLarge: home { large }
        default: home { small }
        }
    }

    private func home<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .foregroundStyle(W.ink)
            .containerBackground(for: .widget) { LinearGradient(colors: [W.navyTop, W.navyBottom], startPoint: .top, endPoint: .bottom) }
    }

    // MARK: Home screen

    private var weatherBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(snap.city).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let s = snap.symbol { Image(systemName: s).symbolRenderingMode(.multicolor).font(.system(size: 13)) }
            }
            Text(snap.temp.map { "\($0)°" } ?? "—").font(W.serif(34, .regular)).minimumScaleFactor(0.7)
            Text(snap.condition ?? "").font(.system(size: 11)).foregroundStyle(W.ink2).lineLimit(1)
            if let h = snap.high, let l = snap.low {
                Text("\(h)° / \(l)°" + (snap.rain.map { $0 >= 20 ? " · ☂ %\($0)" : "" } ?? ""))
                    .font(W.mono(10)).foregroundStyle(W.ink3)
            }
        }
    }

    private func rateRow(_ r: WidgetSnapshot.Rate, compact: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(r.label).font(.system(size: compact ? 11 : 12)).foregroundStyle(W.ink2).lineLimit(1)
            Spacer(minLength: 4)
            Text(r.value).font(W.mono(compact ? 12 : 13)).lineLimit(1)
            if !compact {
                Text(changeText(r.change)).font(W.mono(9.5)).foregroundStyle(r.change >= 0 ? W.up : W.down).frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var updated: some View {
        Text("PANO · \(snap.updated.formatted(.dateTime.hour().minute()))").font(W.mono(8.5)).foregroundStyle(W.ink3)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            weatherBlock
            Spacer(minLength: 6)
            if let usd = snap.rates.first {
                HStack(spacing: 4) {
                    Text("$").font(W.mono(12)).foregroundStyle(W.ink2)
                    Text(usd.value).font(W.mono(13))
                    Text(changeText(usd.change)).font(W.mono(9)).foregroundStyle(usd.change >= 0 ? W.up : W.down)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(url(screen: "Hava Durumu"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Link(destination: url(screen: "Hava Durumu")) {
                weatherBlock.frame(maxHeight: .infinity, alignment: .topLeading)
            }
            Rectangle().fill(W.rule).frame(width: 1)
            Link(destination: url(screen: "Ekonomi")) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(snap.rates, id: \.label) { rateRow($0) }
                    Spacer(minLength: 0)
                    if let h = snap.headlines.first {
                        Text(h.title).font(W.serif(11.5, .medium)).foregroundStyle(W.ink2).lineLimit(2)
                    }
                    updated
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Link(destination: url(screen: "Hava Durumu")) { weatherBlock }
                Spacer(minLength: 0)
                Link(destination: url(screen: "Ekonomi")) {
                    VStack(alignment: .leading, spacing: 6) { ForEach(snap.rates, id: \.label) { rateRow($0, compact: true) } }
                        .frame(width: 150)
                }
            }
            if let g = snap.game {
                Link(destination: url(screen: "Maçlar")) { gameRow(g) }
            }
            Rectangle().fill(W.rule).frame(height: 1)
            Text("MANŞETLER").font(W.mono(9)).tracking(1).foregroundStyle(W.ink3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(snap.headlines.prefix(snap.game == nil ? 5 : 4).enumerated()), id: \.offset) { _, h in
                    Link(destination: h.id.isEmpty ? url(screen: "Haberler") : url(news: h.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.source.uppercased()).font(W.mono(8.5)).foregroundStyle(W.ink3)
                            Text(h.title).font(W.serif(13, .medium)).lineLimit(2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            updated
        }
    }

    private func gameRow(_ g: WidgetSnapshot.Game) -> some View {
        HStack(spacing: 8) {
            if g.live { Circle().fill(W.down).frame(width: 6, height: 6) }
            Text("\(g.home) \(g.score ?? "–") \(g.away)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(g.status).font(W.mono(10)).foregroundStyle(W.ink2).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Lock screen

    private var inline: some View {
        let usd = snap.rates.first.map { " · $ \($0.value)" } ?? ""
        return Group {
            if let s = snap.symbol { Text("\(Image(systemName: s)) \(snap.temp.map { "\($0)°" } ?? "")\(usd)") }
            else { Text("\(snap.temp.map { "\($0)°" } ?? "PANO")\(usd)") }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(url(screen: "Bugün"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let g = snap.game, g.live {
                Text("● CANLI · \(g.status)").font(.system(size: 11, weight: .semibold))
                Text("\(g.home) \(g.score ?? "–") \(g.away)").font(.system(size: 13, weight: .semibold)).lineLimit(2)
            } else {
                ForEach(snap.rates, id: \.label) { r in
                    HStack(spacing: 4) {
                        Text(r.label).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(r.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        Text(r.change >= 0 ? "▲" : "▼").font(.system(size: 8))
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(url(screen: snap.game?.live == true ? "Maçlar" : "Ekonomi"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if let s = snap.symbol { Image(systemName: s).font(.system(size: 14)) }
                Text(snap.temp.map { "\($0)°" } ?? "—").font(.system(size: 17, weight: .semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(url(screen: "Hava Durumu"))
    }
}
