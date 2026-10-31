import Foundation
import WidgetKit

extension AppStore {
    /// Writes what the widgets show and asks them to redraw — after each refresh, and when the app goes to the background.
    func updateWidgets() {
        let w = weather.map { Weather.describe(code: $0.code, isDay: $0.isDay, wind: $0.wind) }
        let today = weatherDetail?.daily.first
        let rates: [WidgetSnapshot.Rate] = [("usd", "Dolar", 2), ("eur", "Euro", 2), ("gram", "Gram altın", 0)].compactMap { id, label, dec in
            quotes[id].map { WidgetSnapshot.Rate(label: label, value: format($0.price, decimals: dec), change: $0.change) }
        }
        let game = headlineMatch.flatMap { m -> WidgetSnapshot.Game? in
            guard isFavorite(m.home) || isFavorite(m.away) else { return nil }
            return WidgetSnapshot.Game(home: m.home, away: m.away, score: m.kind == .upcoming ? nil : m.scoreText,
                                       status: m.kind == .upcoming ? Day.hm(m.kickoff) : m.statusText, live: m.inPlay)
        }
        let snap = WidgetSnapshot(
            updated: lastSync ?? Date(), city: prefs.cityName,
            temp: weather.map { Int($0.temp.rounded()) }, condition: w?.text, symbol: w?.symbol,
            high: today.map { Int($0.tempMax.rounded()) }, low: today.map { Int($0.tempMin.rounded()) }, rain: today?.precipChance,
            rates: rates,
            headlines: topHeadlines.prefix(5).map { WidgetSnapshot.Headline(id: $0.id, source: $0.source, title: $0.title) },
            game: game)
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// pano://screen?name=<Ekran> or pano://news?id=<story id> — from a tap on a widget.
    func openWidgetURL(_ url: URL) {
        guard url.scheme == "pano", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        let value = { (k: String) in items.first { $0.name == k }?.value }
        switch url.host {
        case "news": if let id = value("id"), !id.isEmpty { openNews(id: id) }
        case "screen": if let s = value("name").flatMap(Screen.init(rawValue:)) { screen = s }
        default: break
        }
    }
}
