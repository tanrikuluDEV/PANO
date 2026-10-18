import SwiftUI
import Network
#if os(macOS)
import ServiceManagement
#endif
import UserNotifications

enum Screen: String, CaseIterable, Identifiable {
    case bugun = "Bugün", haberler = "Haberler", yerel = "Yerel", ekonomi = "Ekonomi", futbol = "Maçlar", spor = "Spor", teknoloji = "Teknoloji", radyo = "Radyo", canliTV = "Canlı TV", iptv = "IPTV", hava = "Hava Durumu", yol = "Yol Durumu", deprem = "Deprem", defter = "Defter", arsiv = "Arşiv", ayarlar = "Ayarlar"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .bugun: return "sun.horizon"
        case .haberler: return "newspaper"
        case .yerel: return "mappin.and.ellipse"
        case .ekonomi: return "chart.line.uptrend.xyaxis"
        case .futbol: return "soccerball"
        case .spor: return "figure.run"
        case .teknoloji: return "cpu"
        case .radyo: return "dot.radiowaves.left.and.right"
        case .canliTV: return "tv"
        case .iptv: return "globe"
        case .hava: return "cloud.sun"
        case .yol: return "car"
        case .deprem: return "waveform.path.ecg"
        case .defter: return "book.closed"
        case .arsiv: return "bookmark"
        case .ayarlar: return "gearshape"
        }
    }

    /// Name shown in the menu. The raw value is what's saved in the menu order, so it stays "Bugün";
    /// the phone calls that screen Anasayfa.
    var title: String { isPhone && self == .bugun ? "Anasayfa" : rawValue }

    /// The tabs with the big TV player (the mini player stays hidden on them).
    var isTV: Bool { self == .canliTV || self == .iptv }
}

enum NewsMode: String { case list, morning, daily, weekly }   // morning: phone only (Haberler › Sabah Özeti)

enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

enum ArticleState {
    case loading
    case loaded([ArticleBlock])
    case partial([ArticleBlock])   // only the feed summary could be shown
    case failed(String)
}

private struct Cache: Codable {
    var news: [NewsItem] = []
    var quotes: [String: Quote] = [:]
    var matches: [String: [Match]] = [:]
    var weather: Weather?
    var lastSync: Date?
    var rates: [String: Double]?
}

@MainActor @Observable
final class AppStore {
    // Preferences
    var prefs = Prefs.load() {
        didSet { guard prefs != oldValue else { return }; prefs.save(); prefsChanged(old: oldValue) }
    }

    /// nil = follow the system; otherwise "light" / "dark".
    var appearance: String? = UserDefaults.standard.string(forKey: "appearance") {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }

    // Navigation / selection
    var screen: Screen = .bugun {
        didSet { navRequest &+= 1; if screen != oldValue { screenChanged(from: oldValue) } }
    }
    /// Bumped on every `screen` assignment, even to the same screen: the phone's tab bar routes on it, since
    /// "go to Maçlar" must still work when `screen` already says Maçlar but another tab is showing.
    var navRequest = 0
    var newsMode: NewsMode = .list
    var newsCategory = "Gündem"
    var newsSourceFilter: String?
    var newsQuery = ""
    var selectedNewsID: String?
    var teknolojiQuery = ""
    var teknolojiSourceFilter: String?
    var selectedTeknolojiID: String?
    var sporBranch: SportBranch?          // nil = every branch
    var sporQuery = ""
    var sporSourceFilter: String?
    var selectedSporID: String?
    var arsivQuery = ""
    var selectedArsivID: String?
    var selectedIndicator = "usd"
    var range: ChartRange = .day
    var footballDay = Day.key()
    var footballLiveOnly = false
    var selectedMatchID: String?
    var journalDay = Day.key()

    // Data
    var news: [NewsItem] = [] { didSet { storyCluster = StoryClusters.build(news) } }
    /// Story id → id of the newest story covering the same event (only stories with duplicates). See Dedup.swift.
    var storyCluster: [String: String] = [:]
    var newsState: LoadState = .idle
    var failedSources: [String] = []
    var quotes: [String: Quote] = [:]
    /// Currency units per 1 USD, for the converter.
    var fxRates: [String: Double] = [:]
    var rangeQuotes: [String: Quote] = [:]
    var econState: LoadState = .idle
    var matches: [String: [Match]] = [:]
    var footballState: LoadState = .idle
    var stats: [String: [MatchStat]] = [:]
    var weather: Weather?
    var weatherDetail: WeatherDetail?
    var weatherDetailState: LoadState = .idle
    var lastSync: Date?
    var isOffline = false
    var articles: [String: ArticleState] = [:]
    /// The page's own picture (og:image) for stories whose feed carries none, found when the article is loaded.
    var articleImages: [String: URL] = [:]
    let radio = RadioStore()
    let tv = TVStore()
    let iptv = IPTVStore()
    let yerel = YerelStore()
    /// The TV tab the mini player goes back to when clicked (Canlı TV or IPTV, whichever was last open).
    var lastTVTab: Screen = .canliTV
    let quakes = QuakeStore()
    let fuel = FuelStore()
    let traffic = TrafficStore()
    let takvim = TakvimStore()
    @ObservationIgnored private var lastQuakes = Date.distantPast

    var todos: [TodoItem] = Storage.load([TodoItem].self, "todos.json") ?? []
    var journal: [String: JournalEntry] = Storage.load([String: JournalEntry].self, "journal.json") ?? [:]
    var bookmarks: [Bookmark] = Storage.load([Bookmark].self, "bookmarks.json") ?? []

    /// Newest story date the user had seen when they last left Haberler. Anything newer counts as "new":
    /// the sidebar badge, the popover and the "Kaldığın yer" marker all read it.
    var newsSeenUpTo: Date? = UserDefaults.standard.object(forKey: "newsSeenUpTo") as? Date {
        didSet { UserDefaults.standard.set(newsSeenUpTo, forKey: "newsSeenUpTo") }
    }
    /// `newsSeenUpTo` as it was when the current Haberler visit began — where the "Kaldığın yer" line goes.
    var newsReadMark: Date?
    /// Bugün › Takımım: loaded per followed team, kept for 30 minutes.
    var teamInfo: [String: TeamInfo] = [:]
    var teamState: LoadState = .idle
    var teamSelected = UserDefaults.standard.string(forKey: "teamSelected") ?? "" {
        didSet { UserDefaults.standard.set(teamSelected, forKey: "teamSelected") }
    }
    /// Sleep timer for radio / TV: when it runs out, whatever is playing fades out and stops.
    var sleepUntil: Date?
    /// Whole minutes left (rounded up), refreshed by the 1-second tick so the 🌙 labels stay current.
    var sleepMinutesLeft: Int?
    /// Page shown in the in-app browser panel (WebOverlay); nil = closed.
    var webURL: URL?

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private var lastSlow = Date.distantPast
    @ObservationIgnored private var lastFootball = Date.distantPast
    @ObservationIgnored private var lastNational = Date.distantPast
    @ObservationIgnored private var lastRates = Date.distantPast
    @ObservationIgnored private var lastCacheSave = Date.distantPast
    @ObservationIgnored private var slowBusy = false
    @ObservationIgnored private var footballBusy = false
    @ObservationIgnored private var lastScores: [String: String] = [:]
    /// Pageable sources already walked back through the week this session.
    @ObservationIgnored private var backfilled = Set<String>()
    @ObservationIgnored var openSettingsAction: (() -> Void)?
    /// Opens (or re-opens) the main window; set by RootView, used when a notification is clicked.
    @ObservationIgnored var openMainAction: (() -> Void)?
    @ObservationIgnored private let launchedAt = Date()
    @ObservationIgnored private var notifiedNews = Set<String>()

    init() {
        if let c = Storage.load(Cache.self, "cache.json") {
            // stories cached with a future time (from a feed's timezone mix-up, before it was caught) are dropped;
            // the next refresh brings them back with the right time
            news = c.news.filter { $0.date >= NewsService.cutoff && $0.date <= Date().addingTimeInterval(600) }; quotes = c.quotes; matches = c.matches; weather = c.weather; fxRates = c.rates ?? [:]; lastSync = c.lastSync
            if !news.isEmpty { newsState = .loaded }
            if !quotes.isEmpty { econState = .loaded }
            if !(matches[Day.key()] ?? []).isEmpty { footballState = .loaded }
        }
        if prefs.userName.isEmpty { prefs.userName = NSFullUserName().split(separator: " ").first.map(String.init) ?? "" }
        applyAppearance()
        ColorTheme.current = ColorTheme(rawValue: prefs.colorTheme) ?? .lacivert
        UIStyle.current = UIStyle(rawValue: prefs.uiStyle) ?? .cam
        // a read mark set from a future-dated story (a feed's timezone mix-up) would hide real new stories until then
        if let m = newsSeenUpTo, m > Date() { newsSeenUpTo = Date() }
        // one sound source at a time: a TV channel stops the radio, a radio station stops the TV
        tv.onStart = { [radio] in if radio.isPlaying { radio.halt() } }
        radio.onStart = { [tv] in tv.stop() }
        startMonitor()
        startScheduler()
        traffic.seedIfNeeded(city: prefs.cityName)
        // `-screenshots YES` (simulator only, from the command line) skips the permission prompt
        if !UserDefaults.standard.bool(forKey: "screenshots"), prefs.goalNotify || wantsKeywordAlerts || prefs.morningBrief || prefs.eveningBrief || prefs.quakeNotify || prefs.fuelNotify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in } }
    }

    func applyAppearance() {
        #if os(macOS)
        NSApplication.shared.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
        #endif   // iOS: the root view applies `colorScheme`
    }

    // MARK: Derived

    var greeting: String {
        let h = Day.cal.component(.hour, from: Date())
        let base = h < 5 ? "İyi geceler" : h < 12 ? "Günaydın" : h < 18 ? "İyi günler" : "İyi akşamlar"
        return prefs.userName.isEmpty ? base : "\(base) \(prefs.userName)"
    }

    var visibleInstruments: [Instrument] { allInstruments.filter { prefs.enabledIndicators.contains($0.id) } }

    /// Sidebar order: the user's saved order, then any screen not yet in it (e.g. one added in an update). Ayarlar is excluded — it stays pinned.
    var orderedScreens: [Screen] {
        let known = prefs.navOrder.compactMap { Screen(rawValue: $0) }.filter { $0 != .ayarlar }
        let missing = Screen.allCases.filter { $0 != .ayarlar && !known.contains($0) }
        return known + missing
    }
    /// Window roots use this as their `.id`, so a theme or style change redraws every already-rendered surface.
    var lookID: String { prefs.colorTheme + "|" + prefs.uiStyle }
    func setNavOrder(_ screens: [Screen]) { prefs.navOrder = screens.map(\.rawValue) }
    var activeSources: [NewsSource] { allNewsSources.filter { prefs.enabledSources.contains($0.id) } }

    var filteredNews: [NewsItem] {
        let q = newsQuery.trimmingCharacters(in: .whitespaces)
        return news.filter { n in
            guard prefs.enabledSources.contains(n.sourceID), newsSourceFilter == nil || n.sourceID == newsSourceFilter else { return false }
            // a search term looks across every category; otherwise the selected pill applies
            if !q.isEmpty {
                return n.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || n.summary.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            return newsCategory == "Gündem" ? n.category != "Spor" : n.category == newsCategory
        }
    }
    var selectedNews: NewsItem? {
        let list = filteredNews
        return list.first { $0.id == selectedNewsID } ?? list.first
    }

    /// Sources that have actually produced a Teknoloji-tagged story recently — the dedicated tech
    /// sources always, plus any general source whose classifier occasionally tags one as Teknoloji.
    var teknolojiSources: [NewsSource] {
        let ids = Set(visibleNews.filter { $0.category == "Teknoloji" }.map(\.sourceID))
        return allNewsSources.filter { ids.contains($0.id) }
    }
    var filteredTeknoloji: [NewsItem] {
        let q = teknolojiQuery.trimmingCharacters(in: .whitespaces)
        return visibleNews.filter { n in
            guard n.category == "Teknoloji", teknolojiSourceFilter == nil || n.sourceID == teknolojiSourceFilter else { return false }
            guard !q.isEmpty else { return true }
            return n.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || n.summary.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
    var selectedTeknoloji: NewsItem? {
        let list = filteredTeknoloji
        return list.first { $0.id == selectedTeknolojiID } ?? list.first
    }
    /// Newest headline per source, so one busy feed can't fill the whole list.
    var topHeadlines: [NewsItem] {
        var seen = Set<String>()
        let pool = news.filter { prefs.enabledSources.contains($0.sourceID) && $0.category != "Spor" }
        return Array(pool.filter { seen.insert($0.sourceID).inserted }.prefix(6))
    }

    /// News filtered to enabled sources, most recent first (`news` is already kept in that order).
    var visibleNews: [NewsItem] { news.filter { prefs.enabledSources.contains($0.sourceID) } }

    /// Shown under Ekonomi's chart: the same "Ekonomi" category Haberler uses.
    var ekonomiNews: [NewsItem] { visibleNews.filter { $0.category == "Ekonomi" } }

    /// Shown under Maçlar's fixtures: Spor stories whose branch is football.
    var futbolNews: [NewsItem] { sporNews.filter { branch(of: $0) == .futbol } }

    // MARK: Spor

    /// Branch per story id, worked out once — the headline scan isn't free and lists redraw often.
    @ObservationIgnored private var branchCache: [String: SportBranch] = [:]
    func branch(of n: NewsItem) -> SportBranch {
        if let b = branchCache[n.id] { return b }
        let b = SportBranch.of(n); branchCache[n.id] = b; return b
    }
    var sporNews: [NewsItem] { visibleNews.filter { $0.category == "Spor" } }
    /// Branch pills show how many stories each branch has right now.
    var sporBranchCounts: [SportBranch: Int] {
        Dictionary(grouping: sporNews.filter { sporSourceFilter == nil || $0.sourceID == sporSourceFilter }) { branch(of: $0) }.mapValues(\.count)
    }
    var sporSources: [NewsSource] {
        let ids = Set(sporNews.map(\.sourceID))
        return allNewsSources.filter { ids.contains($0.id) }
    }
    var filteredSpor: [NewsItem] {
        let q = sporQuery.trimmingCharacters(in: .whitespaces)
        return sporNews.filter { n in
            guard sporSourceFilter == nil || n.sourceID == sporSourceFilter else { return false }
            if !q.isEmpty { return n.mentions(q) || n.summary.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return sporBranch == nil || branch(of: n) == sporBranch
        }
    }
    var selectedSpor: NewsItem? {
        let list = filteredSpor
        return list.first { $0.id == selectedSporID } ?? list.first
    }

    /// Multi-word phrases specific enough to forecasts/warnings that they don't false-positive on unrelated
    /// stories — a bare "hava" would also match "havayolu"/"havalimanı" (airline/airport), and a bare "kar"
    /// is ambiguous with "kâr" (profit) once the circumflex is dropped in casual headlines.
    private static let weatherPhrases = ["hava durumu", "meteoroloji", "sağanak yağış", "kar yağışı", "dolu yağışı",
                                         "fırtına uyarısı", "sel felaketi", "aşırı sıcak", "sıcak hava dalgası",
                                         "soğuk hava dalgası", "yoğun sis", "hortum", "kuraklık", "don olayı",
                                         "rüzgar hızı", "rüzgâr hızı", "şiddetli yağış", "yıldırım düştü", "hava nasıl olacak", "hava tahmini",
                                         "meteorolojiden uyarı", "sıcaklık düşecek", "sıcaklıklar düşecek", "kar yağacak", "kar geliyor",
                                         "yağış bekleniyor", "fırtına geliyor", "sağanak bekleniyor", "hava sıcaklığı"]

    /// Weather-related stories, with any mentioning the selected city surfaced first. Restricted to Gündem/Dünya
    /// so an Ekonomi piece using "kar" to mean profit, or a Spor piece, can't slip in via the phrase match alone.
    var weatherNews: [NewsItem] {
        let city = prefs.cityName
        let pool = visibleNews.filter { ["Gündem", "Dünya"].contains($0.category) }
        let matches = pool.filter { n in
            let text = n.title + " " + n.summary
            return Self.weatherPhrases.contains { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        func mentionsCity(_ n: NewsItem) -> Bool {
            n.title.range(of: city, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || n.summary.range(of: city, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return matches.sorted { a, b in
            let am = mentionsCity(a), bm = mentionsCity(b)
            return am != bm ? am : a.date > b.date
        }
    }

    var activeQuote: Quote? { rangeQuotes["\(selectedIndicator)|\(range.rawValue)"] ?? (range == .day ? quotes[selectedIndicator] : nil) }

    /// Matches that pass the user's league/team filters for a given day.
    func matches(on day: String) -> [Match] {
        (matches[day] ?? []).filter { m in
            let fav = isFavorite(m.home) || isFavorite(m.away)
            if nationalSlugs.contains(m.leagueID) { return prefs.nationalTeam && isTurkey(m) }
            guard prefs.enabledLeagues.contains(m.leagueID), let l = allLeagues.first(where: { $0.id == m.leagueID }) else { return false }
            return !l.teamsOnly || fav
        }
        .sorted { ($0.inPlay ? 0 : 1, $0.kickoff) < ($1.inPlay ? 0 : 1, $1.kickoff) }
    }
    func isTurkey(_ m: Match) -> Bool { [m.home, m.away].contains { ["turkey", "türkiye", "turkiye"].contains($0.lowercased()) } }
    func isFavorite(_ name: String) -> Bool {
        prefs.favoriteTeams.contains { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var todayMatches: [Match] { matches(on: Day.key()) }
    /// In play right now (half-time counts).
    var liveMatches: [Match] { todayMatches.filter(\.inPlay) }
    /// Bugün's compact card: what's in play now plus the next kick-off (design), else the day's first fixtures.
    var glanceMatches: [Match] {
        let all = todayMatches
        let rank: (Match) -> Int = { self.isFavorite($0.home) || self.isFavorite($0.away) ? 0 : 1 }
        let live = all.filter(\.inPlay).sorted { rank($0) < rank($1) }.prefix(2)
        let next = all.filter { $0.kind == .upcoming }.sorted { (rank($0), $0.kickoff) < (rank($1), $1.kickoff) }.prefix(1)
        let picked = Array(live) + Array(next)
        return picked.isEmpty ? Array(all.prefix(3)) : picked
    }
    var headlineMatch: Match? {
        liveMatches.first { isFavorite($0.home) || isFavorite($0.away) } ?? liveMatches.first
            ?? todayMatches.first { $0.kind == .upcoming && (isFavorite($0.home) || isFavorite($0.away)) }
            ?? todayMatches.first
    }
    /// What the Maçlar screen lists: the chosen day, or everything in play today when the Canlı filter is on.
    var footballMatches: [Match] { footballLiveOnly ? liveMatches : matches(on: footballDay) }
    var selectedMatch: Match? {
        let all = footballMatches
        return all.first { $0.id == selectedMatchID } ?? all.first
    }

    var menuBarText: String {
        var parts: [String] = []
        if prefs.showFXInMenu, let q = quotes["usd"] { parts.append(format(q.price, decimals: 2) + " ₺") }
        if prefs.showScoreInMenu, let m = liveMatches.first(where: { isFavorite($0.home) || isFavorite($0.away) }) {
            parts.append("\(m.homeCode) \(m.homeGoals ?? 0)–\(m.awayGoals ?? 0) \(m.awayCode)")
        }
        return parts.joined(separator: "  ")
    }

    // MARK: Refresh

    /// Manual refresh (sidebar button, network recovery): everything at once.
    func refresh() async {
        async let slow: () = refreshSlow(force: true)
        async let ball: () = refreshFootball(force: true)
        _ = await (slow, ball)
    }

    /// News, economy and weather — on the user's refresh interval (1 minute by default).
    func refreshSlow(force: Bool = false) async {
        guard !slowBusy else { return }
        slowBusy = true
        defer { slowBusy = false }
        lastSlow = Date()
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.refreshNews() }
            g.addTask { await self.refreshEconomy() }
            g.addTask { await self.refreshWeather() }
            g.addTask { await self.refreshFuel() }
        }
        if !isOffline || !news.isEmpty { lastSync = Date() }
        saveCache()
    }

    func refreshWeather() async {
        let (name, lat, lon) = (prefs.cityName, prefs.cityLat, prefs.cityLon)
        if weatherDetailState == .idle || screen == .hava { weatherDetailState = .loading }
        let d = await MarketService.weatherDetail(lat: lat, lon: lon)
        guard name == prefs.cityName else { return }   // ignore a reply for a city that was just changed
        if let d {
            weather = d.current; weatherDetail = d; weatherDetailState = .loaded
        } else if weatherDetail == nil {
            weatherDetailState = .failed(isOffline ? "İnternet bağlantısı yok." : "Kaynak yanıt vermiyor.")
        }
    }

    func setCity(_ c: City) {
        prefs.cityName = c.name; prefs.cityLat = c.lat; prefs.cityLon = c.lon
    }

    /// Football polls much faster than the rest: while Bugün/Maçlar is showing, or any match is in play.
    var footballInterval: TimeInterval {
        let fast = Double(max(prefs.liveSeconds, 5))
        if screen == .bugun || screen == .futbol || !liveMatches.isEmpty { return fast }
        return prefs.refreshSeconds > 0 ? max(Double(prefs.refreshSeconds), fast) : .infinity
    }

    private func startScheduler() {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tick() {
        let now = Date()
        checkSleepTimer(now)
        #if os(macOS)
        checkMorningBrief(now)
        checkEveningBrief(now)
        #endif   // iPhone: scheduled ahead with the system (iOS/Notifications.swift), so they come with the app closed
        // earthquakes every 2 minutes, whatever tab is open — alerts depend on it
        if now.timeIntervalSince(lastQuakes) >= 120 { lastQuakes = now; Task { await refreshQuakes() } }
        if !slowBusy, prefs.refreshSeconds > 0 || lastSlow == .distantPast,
           now.timeIntervalSince(lastSlow) >= Double(max(prefs.refreshSeconds, 1)) {
            Task { await refreshSlow() }
        }
        if !footballBusy, now.timeIntervalSince(lastFootball) >= footballInterval {
            Task { await refreshFootball() }
        }
    }

    func refreshNews() async {
        if news.isEmpty { newsState = .loading }
        let backfill = Set(activeSources.filter { $0.pageable && !backfilled.contains($0.id) }.map(\.id))
        let r = await NewsService.fetchAll(activeSources, backfill: backfill)
        failedSources = r.failed
        backfilled.formUnion(backfill.intersection(r.items.map(\.sourceID)))
        if !r.items.isEmpty {
            let known = Set(news.map(\.id)), firstLoad = news.isEmpty
            // Merge rather than replace: most feeds only reach back a day or two, so the week is built
            // up from what earlier refreshes (and the cache) already saw. A re-fetched story keeps the
            // date it was first seen with, so an undated item doesn't jump back to "now" every refresh.
            var byID = Dictionary(news.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // keep the earlier of the two dates: an undated story keeps the time it was first seen, and a time that
            // was wrong before (a feed's timezone mix-up) is replaced by the corrected, earlier one
            for n in r.items { byID[n.id] = byID[n.id].map { n.dated(min($0.date, n.date)) } ?? n }
            let cutoff = NewsService.cutoff
            news = byID.values.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
            newsState = .loaded
            if !firstLoad { notifyKeywords(r.items.filter { !known.contains($0.id) }) }
            if screen == .haberler { markNewsSeen() }
        } else if activeSources.isEmpty {
            news = []; newsState = .loaded
        } else if news.isEmpty {
            newsState = .failed(isOffline ? "İnternet bağlantısı yok." : "Kaynak yanıt vermiyor.")
        }
    }

    func refreshEconomy() async {
        if quotes.isEmpty { econState = .loading }
        let ids = allInstruments.map(\.id).filter { prefs.enabledIndicators.contains($0) || ["usd", "eur", "gram"].contains($0) }
        var got = 0
        await withTaskGroup(of: (String, Quote?).self) { g in
            for id in ids { g.addTask { (id, try? await MarketService.quote(id, range: .day)) } }
            for await (id, q) in g { if let q { quotes[id] = q; got += 1 } }
        }
        if fxRates.isEmpty || Date().timeIntervalSince(lastRates) > 1800, let r = await MarketService.fxRates() { fxRates = r; lastRates = Date() }
        rangeQuotes = rangeQuotes.filter { !$0.key.hasSuffix("|1G") }
        if got > 0 { econState = .loaded } else if quotes.isEmpty { econState = .failed(isOffline ? "İnternet bağlantısı yok." : "Kaynak yanıt vermiyor.") }
        await loadRange()
    }

    // MARK: Converter

    /// Units of `code` per 1 USD. TRY, EUR and gold use the live market quotes; the rest use the daily FX table.
    func perUSD(_ code: String) -> Double? {
        let usdTRY = quotes["usd"]?.price ?? fxRates["TRY"]
        switch code {
        case "USD": return 1
        case "TRY": return usdTRY
        case "EUR":
            if let u = quotes["usd"]?.price, let e = quotes["eur"]?.price, e > 0 { return u / e }
            return fxRates["EUR"]
        case "GRAM":
            guard let u = usdTRY, let g = quotes["gram"]?.price, g > 0 else { return nil }
            return u / g   // grams of gold per USD
        default: return fxRates[code]
        }
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perUSD(from), let b = perUSD(to), a > 0 else { return nil }
        return amount / a * b
    }

    func loadRange() async {
        guard range != .day else { return }
        let key = "\(selectedIndicator)|\(range.rawValue)"
        guard rangeQuotes[key] == nil else { return }
        if let q = try? await MarketService.quote(selectedIndicator, range: range) { rangeQuotes[key] = q }
    }

    func refreshFootball(force: Bool = false) async {
        guard !footballBusy else { return }
        footballBusy = true
        defer { footballBusy = false }
        lastFootball = Date()
        let today = Day.key()
        let cutoff = Day.shift(today, by: -2)
        matches = matches.filter { $0.key >= cutoff }
        if footballState == .idle { footballState = .loading }

        var days = [today]
        if footballDay != today { days.append(footballDay) }
        typealias Job = (slug: String, name: String?, day: String?)
        var jobs: [Job] = []
        for l in allLeagues where prefs.enabledLeagues.contains(l.id) { for d in days { jobs.append((l.id, l.name, d)) } }
        // national-team fixtures barely change, so they ride along only about once a minute
        let withNational = force || Date().timeIntervalSince(lastNational) >= 60
        if prefs.nationalTeam, withNational {
            lastNational = Date()
            for s in nationalSlugs.sorted() { jobs.append((s, "Milli takım", nil)) }
        }
        if jobs.isEmpty { footballState = .loaded; return }

        let results = await withTaskGroup(of: [Match]?.self) { g -> [[Match]?] in
            for j in jobs { g.addTask { try? await FootballService.scoreboard(slug: j.slug, leagueName: j.name, day: j.day) } }
            var out: [[Match]?] = []
            for await r in g { out.append(r) }
            return out
        }
        let ok = results.compactMap { $0 }
        guard !ok.isEmpty else {
            if matches.isEmpty { footballState = .failed(isOffline ? "İnternet bağlantısı yok." : "Kaynak yanıt vermiyor.") }
            return
        }
        for m in ok.flatMap({ $0 }) where !nationalSlugs.contains(m.leagueID) || isTurkey(m) {
            let k = Day.key(m.kickoff)
            guard k >= cutoff else { continue }
            var arr = matches[k] ?? []
            if let i = arr.firstIndex(where: { $0.id == m.id }) { arr[i] = m } else { arr.append(m) }
            matches[k] = arr
        }
        footballState = .loaded
        if !isOffline { lastSync = Date() }
        notifyGoals(matches[today] ?? [])
        if Date().timeIntervalSince(lastCacheSave) >= 60 { saveCache() }
        await loadMatchDetail()
    }

    func loadMatchDetail() async {
        guard let m = selectedMatch, m.kind != .upcoming else { return }
        if m.kind == .finished, stats[m.id] != nil { return }
        if let st = try? await FootballService.stats(slug: m.leagueID, id: m.id) { stats[m.id] = st }
    }

    /// Jump to the Maçlar screen; with `liveOnly` the Canlı filter is switched on.
    /// Jump to Haberler with a specific story selected — from Bugün, the popover, or any "İlgili haberler" section.
    func openNews(_ item: NewsItem) {
        // phone: the story opens on top of whatever is showing, so Back returns there (not to Haberler › its category)
        if isPhone { phoneStory = item; return }
        newsQuery = ""; newsSourceFilter = nil; newsMode = .list
        newsCategory = item.category
        selectedNewsID = item.id
        pendingNewsID = item.id
        screen = .haberler
    }
    /// A story opened from outside Haberler; the phone's Haberler opens it as a page when it appears.
    var pendingNewsID: String?
    /// Phone: a story opened from a card, pushed on the current screen's navigation stack.
    var phoneStory: NewsItem?
    /// Phone: the summary page to show ("morning" / "evening") — from its notification or Bugün's buttons.
    var briefToShow: String?

    // MARK: Read position ("Kaldığın yer")

    private func screenChanged(from old: Screen) {
        tv.onTVTab = screen.isTV
        if screen.isTV { lastTVTab = screen }
        if screen == .haberler { newsReadMark = newsSeenUpTo; markNewsSeen() }
        if old == .haberler { markNewsSeen() }
    }
    /// Everything currently loaded counts as seen (future-dated items too, so they don't stay "new").
    func markNewsSeen() {
        guard let newest = visibleNews.map(\.date).max() else { return }
        if newsSeenUpTo.map({ newest > $0 }) ?? true { newsSeenUpTo = newest }
    }
    func isUnread(_ n: NewsItem) -> Bool { newsSeenUpTo.map { n.date > $0 } ?? false }
    var unreadNewsCount: Int { newsSeenUpTo.map { m in visibleNews.filter { $0.date > m }.count } ?? 0 }

    // MARK: Keyword alerts

    var wantsKeywordAlerts: Bool { prefs.keywordNotify && !prefs.alertKeywords.isEmpty }
    func matchedKeyword(_ n: NewsItem) -> String? { prefs.alertKeywords.first { n.mentions($0) } }

    /// One notification per matching new story (up to three), then one summary for the rest. Only stories
    /// published around or after launch qualify, so a backfill of older items never floods the screen.
    private func notifyKeywords(_ fresh: [NewsItem]) {
        guard wantsKeywordAlerts else { return }
        let since = launchedAt.addingTimeInterval(-15 * 60)
        var hits: [(NewsItem, String)] = []
        for n in fresh where n.date >= since && prefs.enabledSources.contains(n.sourceID) && !notifiedNews.contains(n.id) {
            if let k = matchedKeyword(n) { hits.append((n, k)); notifiedNews.insert(n.id) }
        }
        let center = UNUserNotificationCenter.current()
        for (n, k) in hits.prefix(3) {
            let c = UNMutableNotificationContent()
            c.title = "\(k) · \(n.source)"
            c.body = n.title
            c.userInfo = ["newsID": n.id]
            center.add(UNNotificationRequest(identifier: "kw-\(n.id)", content: c, trigger: nil))
        }
        if hits.count > 3 {
            let c = UNMutableNotificationContent()
            c.title = "Takip ettiğin kelimelerde \(hits.count - 3) haber daha"
            c.body = Array(Set(hits.dropFirst(3).map(\.1))).sorted().joined(separator: ", ")
            center.add(UNNotificationRequest(identifier: "kw-more-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
        }
    }

    /// From a clicked notification: bring the window up with the story selected.
    func openNews(id: String) {
        if let n = news.first(where: { $0.id == id }) { openNews(n) }
        else if isBookmarked(id) { arsivQuery = ""; selectedArsivID = id; screen = .arsiv }
    }

    func openFootball(match: Match? = nil, liveOnly: Bool = false) {
        footballLiveOnly = liveOnly
        footballDay = Day.key()
        selectedMatchID = match?.id ?? (liveOnly ? liveMatches.first?.id : nil)
        screen = .futbol
        Task { await refreshFootball() }
    }

    func selectFootballDay(_ d: String) {
        if (matches[d] ?? []).isEmpty { footballState = .loading }
        footballLiveOnly = false
        footballDay = d
        selectedMatchID = nil
        Task { await refreshFootball() }
    }

    private func notifyGoals(_ list: [Match]) {
        for m in list where m.inPlay {
            let score = m.scoreText
            if prefs.goalNotify, let old = lastScores[m.id], old != score, isFavorite(m.home) || isFavorite(m.away) {
                let c = UNMutableNotificationContent()
                c.title = "GOL · \(m.home) \(score) \(m.away)"
                c.body = m.statusText
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "goal-\(m.id)-\(score)", content: c, trigger: nil))
            }
            lastScores[m.id] = score
        }
    }

    private func saveCache() {
        lastCacheSave = Date()
        var c = Cache()
        c.news = news; c.quotes = quotes; c.matches = matches; c.weather = weather; c.rates = fxRates; c.lastSync = lastSync
        Storage.save(c, "cache.json")
    }

    private func startMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let offline = path.status != .satisfied
                let recovered = self.isOffline && !offline
                self.isOffline = offline
                if recovered { await self.refresh() }
            }
        }
        m.start(queue: DispatchQueue(label: "net"))
        monitor = m
    }

    private func prefsChanged(old: Prefs) {
        if old.colorTheme != prefs.colorTheme { ColorTheme.current = ColorTheme(rawValue: prefs.colorTheme) ?? .lacivert }
        if old.uiStyle != prefs.uiStyle { UIStyle.current = UIStyle(rawValue: prefs.uiStyle) ?? .cam }
        #if os(macOS)
        if old.launchAtLogin != prefs.launchAtLogin {
            do {
                if prefs.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("launch at login: \(error)") }
        }
        #endif
        if old.cityName != prefs.cityName || old.cityLat != prefs.cityLat { weather = nil; Task { await refreshWeather() } }
        if old.enabledSources != prefs.enabledSources { Task { await refreshNews() } }
        if old.enabledIndicators != prefs.enabledIndicators { Task { await refreshEconomy() } }
        let keywordsTurnedOn = wantsKeywordAlerts && (old.alertKeywords != prefs.alertKeywords || old.keywordNotify != prefs.keywordNotify)
        let morningTurnedOn = prefs.morningBrief && !old.morningBrief
        let quakesTurnedOn = prefs.quakeNotify && !old.quakeNotify
        let eveningTurnedOn = prefs.eveningBrief && !old.eveningBrief
        let fuelTurnedOn = prefs.fuelNotify && !old.fuelNotify
        if !UserDefaults.standard.bool(forKey: "screenshots"), (old.goalNotify != prefs.goalNotify && prefs.goalNotify) || keywordsTurnedOn || morningTurnedOn || eveningTurnedOn || fuelTurnedOn || quakesTurnedOn {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: Articles

    /// Loads the full text of a story so it can be read in the app. Falls back to the feed summary.
    func loadArticle(_ n: NewsItem) async {
        if case .loaded = articles[n.id] { return }
        if case .loading = articles[n.id] { return }
        articles[n.id] = .loading
        let fallback = n.summary.isEmpty ? [] : [ArticleBlock(text: n.summary, isHeading: false)]
        guard var url = n.link else { articles[n.id] = .partial(fallback); return }
        if url.host == "news.google.com" { url = await GoogleNews.resolve(url) ?? url }
        do {
            let (blocks, image) = try await ArticleService.loadPage(url)
            if n.imageURL == nil, let image { articleImages[n.id] = image }
            let chars = blocks.reduce(0) { $0 + $1.text.count }
            // A page that yields less than the feed's own summary means extraction failed (paywall, JS-rendered body …).
            articles[n.id] = chars >= max(200, n.summary.count) ? .loaded(blocks) : .partial(fallback.isEmpty ? blocks : fallback)
        } catch {
            articles[n.id] = fallback.isEmpty ? .failed(error.localizedDescription) : .partial(fallback)
        }
        if articles.count > 80, let keep = articles[n.id] { articles = [n.id: keep] }
    }

    // MARK: Todos

    func todos(on day: String) -> [TodoItem] { todos.filter { $0.day == day } }

    func addTodo(_ title: String, day: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        todos.append(TodoItem(title: t, day: day)); saveTodos()
    }
    func toggle(_ id: UUID) {
        if let i = todos.firstIndex(where: { $0.id == id }) { todos[i].done.toggle(); saveTodos() }
    }
    func moveToTomorrow(_ id: UUID) {
        if let i = todos.firstIndex(where: { $0.id == id }) { todos[i].day = Day.shift(todos[i].day, by: 1); saveTodos() }
    }
    func moveRemainingToTomorrow(from day: String) {
        for i in todos.indices where todos[i].day == day && !todos[i].done { todos[i].day = Day.shift(day, by: 1) }
        saveTodos()
    }
    /// Edits a to-do's title, time and note (empty time / note clears them; an empty title is ignored).
    func updateTodo(_ id: UUID, title: String, time: String, note: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { todos[i].title = t }
        let tm = time.trimmingCharacters(in: .whitespaces), n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        todos[i].time = tm.isEmpty ? nil : tm
        todos[i].note = n.isEmpty ? nil : n
        saveTodos()
    }
    func deleteTodo(_ id: UUID) { todos.removeAll { $0.id == id }; saveTodos() }
    private func saveTodos() { Storage.save(todos, "todos.json") }

    // MARK: Journal

    func entry(_ day: String) -> JournalEntry? { journal[day] }

    func setText(_ text: String, day: String) {
        var e = journal[day] ?? JournalEntry(day: day, text: "", tags: [], savedAt: Date())
        e.text = text; e.savedAt = Date()
        journal[day] = e.text.isEmpty && e.tags.isEmpty ? nil : e
        Storage.save(journal, "journal.json")
    }
    func addTag(_ tag: String, day: String) {
        let t = tag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty else { return }
        var e = journal[day] ?? JournalEntry(day: day, text: "", tags: [], savedAt: Date())
        if !e.tags.contains(t) { e.tags.append(t) }
        journal[day] = e; Storage.save(journal, "journal.json")
    }
    func removeTag(_ tag: String, day: String) {
        guard var e = journal[day] else { return }
        e.tags.removeAll { $0 == tag }
        journal[day] = e.text.isEmpty && e.tags.isEmpty ? nil : e
        Storage.save(journal, "journal.json")
    }
    func appendNote(_ line: String, day: String = Day.key()) {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty else { return }
        let cur = journal[day]?.text ?? ""
        setText(cur.isEmpty ? l : cur + "\n\n" + l, day: day)
    }
    // MARK: Deprem

    func refreshQuakes() async {
        await quakes.refresh(prefs: prefs, cityLat: prefs.cityLat, cityLon: prefs.cityLon)
    }

    // MARK: Takımım

    func refreshTeam(_ name: String) async {
        if let t = teamInfo[name], Date().timeIntervalSince(t.fetched) < 1800 { return }
        if teamInfo[name] == nil { teamState = .loading }
        do {
            teamInfo[name] = try await TeamService.load(name)
            teamState = .loaded
        } catch {
            if teamInfo[name] == nil { teamState = .failed(isOffline ? "İnternet bağlantısı yok." : "“\(name)” bulunamadı.") }
        }
    }

    // MARK: Sleep timer

    static let sleepChoices = [15, 30, 45, 60, 90]

    func setSleepTimer(minutes: Int?) {
        sleepUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        sleepMinutesLeft = minutes
        fadeAudio(1)
    }

    /// Fades the sound over the last 30 seconds, then stops radio and TV and clears itself.
    private func checkSleepTimer(_ now: Date) {
        guard let until = sleepUntil else { return }
        let left = until.timeIntervalSince(now)
        if left <= 0 {
            if radio.isPlaying { radio.halt() }
            tv.stop()
            sleepUntil = nil; sleepMinutesLeft = nil
            fadeAudio(1)
            return
        }
        let mins = Int((left / 60).rounded(.up))
        if mins != sleepMinutesLeft { sleepMinutesLeft = mins }
        fadeAudio(left < 30 ? left / 30 : 1)
    }

    private func fadeAudio(_ f: Double) {
        radio.fade(f)
        tv.player.volume = Float(f)
    }

    // MARK: In-app browser

    func openWeb(_ url: URL) { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { webURL = url } }
    func closeWeb() { withAnimation(.easeOut(duration: 0.2)) { webURL = nil } }

    // MARK: Arşiv

    func isBookmarked(_ id: String) -> Bool { bookmarks.contains { $0.id == id } }
    func toggleBookmark(_ n: NewsItem) {
        if isBookmarked(n.id) { bookmarks.removeAll { $0.id == n.id } } else { bookmarks.insert(Bookmark(item: n, savedAt: Date()), at: 0) }
        Storage.save(bookmarks, "bookmarks.json")
    }
    /// Archived stories, newest story first (so the list groups by day like Haberler), filtered by the search box.
    var filteredArsiv: [NewsItem] {
        let q = arsivQuery.trimmingCharacters(in: .whitespaces)
        return bookmarks.map(\.item)
            .filter { q.isEmpty || $0.mentions(q) || $0.summary.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil || $0.source.localizedCaseInsensitiveContains(q) }
            .sorted { $0.date > $1.date }
    }
    var selectedArsiv: NewsItem? {
        let list = filteredArsiv
        return list.first { $0.id == selectedArsivID } ?? list.first
    }

    func saveArticle(_ n: NewsItem) {
        appendNote("— \(n.title) (\(n.source))" + (n.link.map { " \($0.absoluteString)" } ?? ""))
    }
}

// MARK: - Number formatting (tr-TR)

private let trFormatters = NSCache<NSNumber, NumberFormatter>()

func format(_ v: Double, decimals: Int) -> String {
    let key = NSNumber(value: decimals)
    let f: NumberFormatter
    if let c = trFormatters.object(forKey: key) { f = c } else {
        f = NumberFormatter(); f.locale = Locale(identifier: "tr_TR"); f.numberStyle = .decimal
        f.minimumFractionDigits = decimals; f.maximumFractionDigits = decimals; f.usesGroupingSeparator = true
        trFormatters.setObject(f, forKey: key)
    }
    return f.string(from: NSNumber(value: v)) ?? String(v)
}

func percent(_ v: Double) -> String { "%" + format(abs(v), decimals: 2) }
