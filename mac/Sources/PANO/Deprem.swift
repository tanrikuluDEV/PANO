import Foundation
import CoreLocation
import UserNotifications

// MARK: - Model

struct Quake: Identifiable, Codable, Hashable {
    let id: String
    let magnitude: Double
    let magType: String
    let location: String
    let province: String?
    let lat: Double
    let lon: Double
    let depth: Double
    let date: Date

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var magText: String { String(format: "%.1f", magnitude).replacingOccurrences(of: ".", with: ",") }

    /// Great-circle distance in km.
    func distance(toLat la: Double, lon lo: Double) -> Double {
        let r = 6371.0, p = Double.pi / 180
        let a = sin((la - lat) * p / 2), b = sin((lo - lon) * p / 2)
        let h = a * a + cos(lat * p) * cos(la * p) * b * b
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

// MARK: - Service (AFAD's public event API, no key)

enum QuakeService {
    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    /// AFAD's dates carry no zone but are UTC (checked against Kandilli's Türkiye-time list).
    private static func date(_ s: String) -> Date? { fmt.date(from: s.hasSuffix("Z") ? s : s + "Z") }

    static func fetch(hours: Int, minMag: Double) async throws -> [Quake] {
        let end = Date(), start = end.addingTimeInterval(-Double(hours) * 3600)
        let q = "start=\(fmt.string(from: start).dropLast())&end=\(fmt.string(from: end).dropLast())&minmag=\(minMag)"
        guard let url = URL(string: "https://deprem.afad.gov.tr/apiv2/event/filter?" + q) else { throw ServiceError.empty }
        guard let rows = try JSONSerialization.jsonObject(with: try await PANO.fetch(url)) as? [[String: Any]] else { throw ServiceError.empty }
        func num(_ v: Any?) -> Double? { (v as? Double) ?? Double(v as? String ?? "") }
        return rows.compactMap { r in
            guard let id = r["eventID"] as? String ?? (r["eventID"] as? Int).map(String.init),
                  let m = num(r["magnitude"]), let la = num(r["latitude"]), let lo = num(r["longitude"]),
                  let d = date(r["date"] as? String ?? "") else { return nil }
            return Quake(id: id, magnitude: m, magType: r["type"] as? String ?? "", location: r["location"] as? String ?? "?",
                         province: r["province"] as? String, lat: la, lon: lo, depth: num(r["depth"]) ?? 0, date: d)
        }
        .sorted { $0.date > $1.date }   // the API ignores orderby
    }
}

// MARK: - Store

@MainActor @Observable
final class QuakeStore {
    var day: [Quake] = Storage.load([Quake].self, "quakes.json") ?? []
    var week: [Quake] = []
    var state: LoadState = .idle
    var weekState: LoadState = .idle
    var selectedID: String?
    var lastUpdate: Date?
    @ObservationIgnored private var lastWeek = Date.distantPast
    @ObservationIgnored private var notified = Set(UserDefaults.standard.stringArray(forKey: "quakeNotified") ?? [])
    @ObservationIgnored private var busy = false

    /// Last 24 hours (every 2 minutes from AppStore's tick); raises alerts for new events that qualify.
    func refresh(prefs: Prefs, cityLat: Double, cityLon: Double) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        if day.isEmpty { state = .loading }
        do {
            let list = try await QuakeService.fetch(hours: 24, minMag: 0.5)
            let known = Set(day.map(\.id))
            day = list; state = .loaded; lastUpdate = Date()
            Storage.save(list, "quakes.json")
            notify(list.filter { !known.contains($0.id) }, prefs: prefs, lat: cityLat, lon: cityLon)
        } catch {
            if day.isEmpty { state = .failed("AFAD verisine ulaşılamadı.") }
        }
    }

    /// Last 7 days (magnitude 1.5+ to keep it light), fetched when that range is shown, at most every 10 minutes.
    func loadWeek() async {
        guard Date().timeIntervalSince(lastWeek) > 600 else { return }
        if week.isEmpty { weekState = .loading }
        do { week = try await QuakeService.fetch(hours: 24 * 7, minMag: 1.5); weekState = .loaded; lastWeek = Date() }
        catch { if week.isEmpty { weekState = .failed("AFAD verisine ulaşılamadı.") } }
    }

    /// New events at or above the alert magnitude within the alert radius of the weather city. Only events from
    /// the last 30 minutes count, so the first fetch after launch doesn't replay the whole day.
    private func notify(_ fresh: [Quake], prefs: Prefs, lat: Double, lon: Double) {
        guard prefs.quakeNotify else { return }
        let recent = Date().addingTimeInterval(-30 * 60)
        for q in fresh where q.date >= recent && q.magnitude >= prefs.quakeMinMag && !notified.contains(q.id) {
            let km = q.distance(toLat: lat, lon: lon)
            guard prefs.quakeRadius == 0 || km <= Double(prefs.quakeRadius) else { continue }
            notified.insert(q.id)
            let c = UNMutableNotificationContent()
            c.title = "Deprem · \(q.magText) (\(q.magType))"
            c.body = "\(q.location) · \(Day.hm(q.date)) · derinlik \(Int(q.depth.rounded())) km · \(prefs.cityName) şehrine \(Int(km.rounded())) km"
            c.sound = q.magnitude >= 5 ? .defaultCritical : .default
            c.userInfo = ["screen": Screen.deprem.rawValue, "quakeID": q.id]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "quake-\(q.id)", content: c, trigger: nil))
        }
        UserDefaults.standard.set(Array(notified.suffix(300)), forKey: "quakeNotified")
    }
}
