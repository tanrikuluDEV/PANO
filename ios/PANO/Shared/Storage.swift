import Foundation

/// JSON files under ~/Library/Application Support/PANO (moved over from the app's former name on first launch).
enum Storage {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("PANO", isDirectory: true)
        let old = base.appendingPathComponent("Ruzname", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: d)
        }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}

struct Prefs: Codable, Equatable {
    var userName: String = ""
    var showMenuIcon = true
    var showFXInMenu = true
    var showScoreInMenu = false
    var launchAtLogin = false
    var stayInMenuBar = true
    var enabledSources: Set<String> = Set(allNewsSources.map(\.id))
    var enabledLeagues: Set<String> = Set(allLeagues.map(\.id))
    var nationalTeam = true
    var goalNotify = true
    var favoriteTeams: [String] = ["Galatasaray"]
    var enabledIndicators: Set<String> = ["usd", "eur", "gram", "bist", "brent", "btc"]
    /// News, economy and weather refresh interval in seconds (0 = manual).
    var refreshSeconds = 60
    /// Football score polling while Bugün/Maçlar is open or a match is live.
    var liveSeconds = 15
    var cityName = "İstanbul"
    var cityLat = 41.01
    var cityLon = 28.98
    /// Sidebar order (Ayarlar is pinned at the bottom and never part of this).
    var navOrder: [String] = Screen.allCases.filter { $0 != .ayarlar }.map(\.rawValue)
    var colorTheme: String = ColorTheme.lacivert.rawValue
    /// Words that trigger a notification when a new headline contains them.
    var alertKeywords: [String] = []
    var keywordNotify = true
    /// Fold the same story from several outlets into one row with a "+N kaynak" label.
    var foldDuplicates = true
    /// Sidebar narrowed to icons only (drag its edge, or ⌃⌘S).
    var sidebarCollapsed = false
    /// "cam" (glass) or "klasik".
    var uiStyle: String = UIStyle.cam.rawValue
    /// Sabah özeti notification, sent once a day at `morningHour`:00.
    var morningBrief = true
    var morningHour = 8
    /// Günün özeti notification, sent once a day at `eveningMinute` (minutes after midnight; 19:30 by default).
    var eveningBrief = true
    var eveningMinute = 19 * 60 + 30
    /// Notify when pump prices change in the city chosen under Ekonomi › Akaryakıt.
    var fuelNotify = true
    /// Show today's events from the Mac's Calendar app on Bugün (asks for access when switched on).
    var showCalendarEvents = false
    /// Earthquake alerts: magnitude at least `quakeMinMag`, within `quakeRadius` km of the weather city (0 = anywhere).
    var quakeNotify = true
    var quakeMinMag = 4.0
    var quakeRadius = 300
    /// Every source id this install has already offered. A source missing from it is new in this version
    /// and starts enabled; after that, switching it off sticks.
    var seenSources: Set<String> = Set(allNewsSources.map(\.id))

    init() {}

    // Missing keys fall back to defaults, so adding a preference never wipes the saved ones.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decodeIfPresent(String.self, forKey: .userName) { userName = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .showMenuIcon) { showMenuIcon = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .showFXInMenu) { showFXInMenu = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .showScoreInMenu) { showScoreInMenu = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) { launchAtLogin = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .stayInMenuBar) { stayInMenuBar = v }
        let allIDs = Set(allNewsSources.map(\.id))
        if let saved = try? c.decodeIfPresent(Set<String>.self, forKey: .enabledSources) {
            if let seen = try? c.decodeIfPresent(Set<String>.self, forKey: .seenSources) {
                // only sources this install has never offered start enabled; switching one off sticks
                enabledSources = saved.union(allIDs.subtracting(seen))
            } else {
                // prefs from before `seenSources`: the old code forced `sourcesAutoEnabledOnUpgrade` on at every
                // launch — honour that one last time, and switch on the sources added with the Spor tab
                enabledSources = saved.union(sourcesAutoEnabledOnUpgrade).union(sourcesAddedWithSpor)
            }
        }
        seenSources = allIDs
        if let v = try? c.decodeIfPresent(Set<String>.self, forKey: .enabledLeagues) { enabledLeagues = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .nationalTeam) { nationalTeam = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .goalNotify) { goalNotify = v }
        if let v = try? c.decodeIfPresent([String].self, forKey: .favoriteTeams) { favoriteTeams = v }
        if let v = try? c.decodeIfPresent(Set<String>.self, forKey: .enabledIndicators) { enabledIndicators = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .refreshSeconds) { refreshSeconds = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .liveSeconds) { liveSeconds = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .cityName) { cityName = v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: .cityLat) { cityLat = v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: .cityLon) { cityLon = v }
        if var v = try? c.decodeIfPresent([String].self, forKey: .navOrder) {
            // "Futbol" became "Maçlar"; the new Spor tab goes right after it
            v = v.map { $0 == "Futbol" ? Screen.futbol.rawValue : $0 }
            if !v.contains(Screen.deprem.rawValue) {
                v.insert(Screen.deprem.rawValue, at: (v.firstIndex(of: Screen.hava.rawValue) ?? v.count - 1) + 1)
            }
            if !v.contains(Screen.canliTV.rawValue) {
                v.insert(Screen.canliTV.rawValue, at: (v.firstIndex(of: Screen.radyo.rawValue) ?? v.count - 1) + 1)
            }
            if !v.contains(Screen.yerel.rawValue) {
                v.insert(Screen.yerel.rawValue, at: (v.firstIndex(of: Screen.haberler.rawValue) ?? v.count - 1) + 1)
            }
            if !v.contains(Screen.iptv.rawValue) {
                v.insert(Screen.iptv.rawValue, at: (v.firstIndex(of: Screen.canliTV.rawValue) ?? v.count - 1) + 1)
            }
            if !v.contains(Screen.yol.rawValue) {
                v.insert(Screen.yol.rawValue, at: (v.firstIndex(of: Screen.hava.rawValue) ?? v.count - 1) + 1)
            }
            if !v.contains(Screen.spor.rawValue) {
                v.insert(Screen.spor.rawValue, at: (v.firstIndex(of: Screen.futbol.rawValue) ?? v.count - 1) + 1)
            }
            navOrder = v
        }
        if let v = try? c.decodeIfPresent(String.self, forKey: .colorTheme) { colorTheme = v }
        if let v = try? c.decodeIfPresent([String].self, forKey: .alertKeywords) { alertKeywords = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .keywordNotify) { keywordNotify = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .foldDuplicates) { foldDuplicates = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) { sidebarCollapsed = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .uiStyle) { uiStyle = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .morningBrief) { morningBrief = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .morningHour) { morningHour = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .eveningBrief) { eveningBrief = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .eveningMinute) { eveningMinute = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .fuelNotify) { fuelNotify = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .showCalendarEvents) { showCalendarEvents = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .quakeNotify) { quakeNotify = v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: .quakeMinMag) { quakeMinMag = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .quakeRadius) { quakeRadius = v }
    }

    static func load() -> Prefs {
        guard let d = UserDefaults.standard.data(forKey: "prefs"), let p = try? JSONDecoder().decode(Prefs.self, from: d) else { return Prefs() }
        p.save()   // write back migrations (renamed tabs, newly offered sources) so they run only once
        return p
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "prefs") }
    }
}
