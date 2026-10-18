import Foundation
import UserNotifications

/// Pump prices per province (city centre), VAT included, from Petrol Ofisi's price page — one request covers all
/// 81 provinces (İstanbul as Avrupa and Anadolu). No key; the page is HTML, so this reads the table rows.
struct FuelPrice: Codable, Identifiable, Hashable {
    let id: String          // Petrol Ofisi's row id
    let name: String        // "İzmir", "İstanbul (Avrupa)"
    let province: String?
    let benzin: Double?     // V/Max Kurşunsuz 95, TL/L
    let motorin: Double?    // V/Max Diesel, TL/L
    let lpg: Double?        // PO/gaz Otogaz, TL/L
}

/// The prices at one moment; a new one is kept only when something changed.
struct FuelSnapshot: Codable, Hashable {
    let date: Date
    let benzin: Double?
    let motorin: Double?
    let lpg: Double?
}

enum FuelKind: String, CaseIterable {
    case benzin = "Benzin", motorin = "Motorin", lpg = "LPG"
    var detail: String {
        switch self { case .benzin: "Kurşunsuz 95"; case .motorin: "Dizel"; case .lpg: "Otogaz" }
    }
    func value(_ p: FuelPrice) -> Double? { switch self { case .benzin: p.benzin; case .motorin: p.motorin; case .lpg: p.lpg } }
    func value(_ s: FuelSnapshot) -> Double? { switch self { case .benzin: s.benzin; case .motorin: s.motorin; case .lpg: s.lpg } }
}

enum FuelService {
    static let pageURL = URL(string: "https://www.petrolofisi.com.tr/akaryakit-fiyatlari")!

    static func fetch() async throws -> [FuelPrice] {
        let data = try await PANO.fetch(pageURL, headers: ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36"])
        guard let html = String(data: data, encoding: .utf8) else { throw ServiceError.empty }
        let list = parse(html)
        if list.isEmpty { throw ServiceError.empty }
        return list
    }

    private static let rowRx = try! NSRegularExpression(
        pattern: #"<tr class="price-row[^"]*" data-disctrict-id="(\d+)" data-disctrict-name="([^"]+)">(.*?)</tr>"#,
        options: [.dotMatchesLineSeparators])
    private static let cellRx = try! NSRegularExpression(pattern: #"<td>(.*?)</td>"#, options: [.dotMatchesLineSeparators])
    private static let priceRx = try! NSRegularExpression(pattern: #"<span class="with-tax">\s*([\d.,]+)\s*</span>"#)

    /// Columns: Kurşunsuz 95, Diesel, Gazyağı, Kalorifer Yakıtı, Fuel Oil, Otogaz — the first cell is the name.
    static func parse(_ html: String) -> [FuelPrice] {
        var seen = Set<String>()
        return rowRx.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let id = group(m, 1, html), let raw = group(m, 2, html), let body = group(m, 3, html), seen.insert(id).inserted else { return nil }
            let cells = cellRx.matches(in: body, range: NSRange(body.startIndex..., in: body)).map { group($0, 1, body) ?? "" }
            func price(_ i: Int) -> Double? {
                guard i < cells.count, let pm = priceRx.firstMatch(in: cells[i], range: NSRange(cells[i].startIndex..., in: cells[i])),
                      let s = group(pm, 1, cells[i]) else { return nil }
                return Double(s.replacingOccurrences(of: ",", with: "."))
            }
            let province = Provinces.match(raw)
            return FuelPrice(id: id, name: displayName(raw, province), province: province, benzin: price(1), motorin: price(2), lpg: price(6))
        }
    }

    /// "ISTANBUL (AVRUPA)" → "İstanbul (Avrupa)"; unknown names are just title-cased.
    private static func displayName(_ raw: String, _ province: String?) -> String {
        let tr = Locale(identifier: "tr_TR")
        let base = province ?? raw.components(separatedBy: " (").first!.capitalized(with: tr)
        guard let open = raw.firstIndex(of: "(") else { return base }
        return base + " " + String(raw[open...]).capitalized(with: tr)
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        Range(m.range(at: i), in: s).map { String(s[$0]) }
    }
}

@MainActor @Observable
final class FuelStore {
    var prices: [FuelPrice] = Storage.load([FuelPrice].self, "fuel.json") ?? []
    var state: LoadState = .idle
    var lastFetch: Date? = UserDefaults.standard.object(forKey: "fuelLastFetch") as? Date
    /// Row id → snapshots, oldest first; a snapshot is added only when a price changed.
    var history: [String: [FuelSnapshot]] = Storage.load([String: [FuelSnapshot]].self, "fuel-history.json") ?? [:]
    /// Row id picked in Ekonomi; nil follows the weather city.
    var pickedID: String? = UserDefaults.standard.string(forKey: "fuelCity") {
        didSet { UserDefaults.standard.set(pickedID, forKey: "fuelCity") }
    }

    /// The row to show: the user's pick, else the weather city's province (İstanbul → Avrupa), else İstanbul.
    func selected(weatherCity: String) -> FuelPrice? {
        if let id = pickedID, let p = prices.first(where: { $0.id == id }) { return p }
        let prov = Provinces.match(weatherCity) ?? "İstanbul"
        return prices.first { $0.province == prov } ?? prices.first { $0.province == "İstanbul" } ?? prices.first
    }

    /// Latest change of one fuel in a row: how much and when (nil until a change has been seen).
    func lastChange(_ kind: FuelKind, id: String) -> (delta: Double, date: Date)? {
        let snaps = history[id] ?? []
        guard snaps.count >= 2 else { return nil }
        for i in stride(from: snaps.count - 1, to: 0, by: -1) {
            if let a = kind.value(snaps[i]), let b = kind.value(snaps[i - 1]), abs(a - b) >= 0.005 { return (a - b, snaps[i].date) }
        }
        return nil
    }

    /// Fetches at most every 30 minutes (prices change a few times a month). Returns the changes seen in
    /// this fetch per row id, so the caller can announce the ones for the chosen city.
    @discardableResult
    func refresh(force: Bool = false) async -> [String: [(FuelKind, Double, Double)]] {
        if !force, let l = lastFetch, Date().timeIntervalSince(l) < 30 * 60, !prices.isEmpty { return [:] }
        if prices.isEmpty { state = .loading }
        guard let list = try? await FuelService.fetch() else {
            if prices.isEmpty { state = .failed("Akaryakıt fiyatları alınamadı.") }
            return [:]
        }
        let now = Date()
        var changes: [String: [(FuelKind, Double, Double)]] = [:]
        for p in list {
            let snap = FuelSnapshot(date: now, benzin: p.benzin, motorin: p.motorin, lpg: p.lpg)
            var snaps = history[p.id] ?? []
            if let last = snaps.last {
                let diffs = FuelKind.allCases.compactMap { k -> (FuelKind, Double, Double)? in
                    guard let old = k.value(last), let new = k.value(snap), abs(old - new) >= 0.005 else { return nil }
                    return (k, old, new)
                }
                guard !diffs.isEmpty else { continue }
                changes[p.id] = diffs
            }
            snaps.append(snap)
            history[p.id] = Array(snaps.suffix(40))
        }
        prices = list
        state = .loaded
        lastFetch = now
        UserDefaults.standard.set(now, forKey: "fuelLastFetch")
        Storage.save(list, "fuel.json")
        Storage.save(history, "fuel-history.json")
        return changes
    }
}

extension AppStore {
    /// Refreshes pump prices and, when the chosen city's prices moved, sends one notification.
    func refreshFuel(force: Bool = false) async {
        let changes = await fuel.refresh(force: force)
        guard prefs.fuelNotify, let row = fuel.selected(weatherCity: prefs.cityName), let diffs = changes[row.id] else { return }
        let ups = diffs.filter { $0.2 > $0.1 }.count
        let c = UNMutableNotificationContent()
        c.title = "⛽ " + (ups == diffs.count ? "Akaryakıta zam" : ups == 0 ? "Akaryakıta indirim" : "Akaryakıt fiyatları değişti")
        c.subtitle = row.name
        c.body = diffs.map { k, old, new in
            "\(k.rawValue): \(Fuel.tl(old)) → \(Fuel.tl(new)) TL (\(new > old ? "+" : "−")\(Fuel.tl(abs(new - old))))"
        }.joined(separator: "\n")
        c.sound = .default
        c.userInfo = ["screen": Screen.ekonomi.rawValue]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "fuel-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
    }
}

enum Fuel {
    private static let fmt: NumberFormatter = {
        let f = NumberFormatter(); f.locale = Locale(identifier: "tr_TR"); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2; return f
    }()
    static func tl(_ v: Double) -> String { fmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v) }
}
