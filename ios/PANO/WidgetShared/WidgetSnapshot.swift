import Foundation

/// What the widgets show, written by the app after each refresh into the shared App Group container and read by
/// the widget extension (which never goes online itself).
struct WidgetSnapshot: Codable {
    struct Rate: Codable { let label: String; let value: String; let change: Double }
    struct Headline: Codable { let id: String; let source: String; let title: String }
    struct Game: Codable { let home: String; let away: String; let score: String?; let status: String; let live: Bool }

    var updated: Date
    var city: String
    var temp: Int?
    var condition: String?
    var symbol: String?
    var high: Int?
    var low: Int?
    var rain: Int?
    var rates: [Rate]
    var headlines: [Headline]
    var game: Game?

    static let group = "group.com.ruzname.pano"
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(self).write(to: url, options: .atomic)
    }

    /// Shown in the widget gallery and before the app has run once.
    static let sample = WidgetSnapshot(
        updated: Date(), city: "İstanbul", temp: 18, condition: "Parçalı bulutlu", symbol: "cloud.sun.fill", high: 21, low: 13, rain: 10,
        rates: [Rate(label: "Dolar", value: "41,25", change: 0.12), Rate(label: "Euro", value: "47,80", change: -0.08),
                Rate(label: "Gram altın", value: "5.420", change: 0.64)],
        headlines: [Headline(id: "", source: "PANO", title: "Gündemin öne çıkan başlıkları burada görünür"),
                    Headline(id: "", source: "PANO", title: "Habere dokununca uygulamada açılır"),
                    Headline(id: "", source: "PANO", title: "Kurlar, hava durumu ve takımının maçı da")],
        game: nil)
}
