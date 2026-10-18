import Foundation

// MARK: - Days

enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.timeZone = .current
        return c
    }()
    private static let keyFmt: DateFormatter = {
        let f = DateFormatter(); f.calendar = cal; f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func key(_ d: Date = Date()) -> String { keyFmt.string(from: d) }
    static func date(_ key: String) -> Date? { keyFmt.date(from: key) }
    static func shift(_ key: String, by days: Int) -> String {
        guard let d = date(key), let n = cal.date(byAdding: .day, value: days, to: d) else { return key }
        return Self.key(n)
    }
    static func format(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.timeZone = .current
        f.dateFormat = pattern; return f.string(from: d)
    }
    static func long(_ d: Date) -> String { format(d, "d MMMM EEEE") }
    static func hm(_ d: Date) -> String { format(d, "HH:mm") }

    /// Whole calendar days between `d` and today (0 = today, 1 = yesterday); future dates count as today.
    static func daysAgo(_ d: Date) -> Int {
        max(0, cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0)
    }
    /// Day separator label for news lists: BUGÜN, DÜN, then the weekday (ÇARŞAMBA …).
    static func relativeName(_ d: Date) -> String {
        switch daysAgo(d) {
        case 0: return "BUGÜN"
        case 1: return "DÜN"
        case 2...6: return format(d, "EEEE").uppercased(with: Locale(identifier: "tr_TR"))
        // older than a week (archive): weekday names would be ambiguous, so spell out the date
        default:
            let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
            return format(d, sameYear ? "d MMMM" : "d MMMM yyyy").uppercased(with: Locale(identifier: "tr_TR"))
        }
    }
}

// MARK: - News

struct NewsSource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let defaultCategory: String
    let blurb: String
    /// WordPress-style feed that serves older items via `?paged=N`, so a full week can be backfilled.
    var pageable = false
    /// For single-branch sports feeds: every story from it belongs to this branch (see `SportBranch`).
    var branch: SportBranch? = nil
}

let allNewsSources: [NewsSource] = [
    .init(id: "aa", name: "Anadolu Ajansı", url: "https://www.aa.com.tr/tr/rss/default?cat=guncel", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "bbc", name: "BBC Türkçe", url: "https://feeds.bbci.co.uk/turkce/rss.xml", defaultCategory: "Dünya", blurb: "Dünya"),
    .init(id: "bloomberght", name: "Bloomberg HT", url: "https://www.bloomberght.com/rss", defaultCategory: "Ekonomi", blurb: "Ekonomi"),
    .init(id: "dunya", name: "Dünya", url: "https://www.dunya.com/rss", defaultCategory: "Ekonomi", blurb: "Ekonomi"),
    .init(id: "cumhuriyet", name: "Cumhuriyet", url: "https://www.cumhuriyet.com.tr/rss/son_dakika.xml", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "hurriyet", name: "Hürriyet", url: "https://www.hurriyet.com.tr/rss/anasayfa", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "ntv", name: "NTV", url: "https://www.ntv.com.tr/gundem.rss", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "webtekno", name: "Webtekno", url: "https://www.webtekno.com/rss.xml", defaultCategory: "Teknoloji", blurb: "Teknoloji"),
    .init(id: "trt", name: "TRT Haber", url: "https://www.trthaber.com/manset_articles.rss", defaultCategory: "Gündem", blurb: "Gündem · Dünya"),
    .init(id: "trtspor", name: "TRT Spor", url: "https://www.trthaber.com/spor_articles.rss", defaultCategory: "Spor", blurb: "Spor"),
    .init(id: "ekonomim", name: "Ekonomim", url: "https://www.ekonomim.com/rss", defaultCategory: "Ekonomi", blurb: "Ekonomi"),
    .init(id: "shiftdelete", name: "ShiftDelete.Net", url: "https://www.shiftdelete.net/feed", defaultCategory: "Teknoloji", blurb: "Teknoloji", pageable: true),
    .init(id: "donanimhaber", name: "Donanımhaber", url: "https://www.donanimhaber.com/rss/tum/", defaultCategory: "Teknoloji", blurb: "Teknoloji"),
    .init(id: "webrazzi", name: "Webrazzi", url: "https://webrazzi.com/feed/", defaultCategory: "Teknoloji", blurb: "Teknoloji · Girişim"),
    .init(id: "sozcu", name: "Sözcü", url: "https://www.sozcu.com.tr/feeds-son-dakika", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "haberturk", name: "Habertürk", url: "https://www.haberturk.com/rss/kategori/gundem.xml", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "odatv", name: "Oda TV", url: "https://www.odatv.com/rss", defaultCategory: "Gündem", blurb: "Gündem"),
    .init(id: "haberturkekonomi", name: "Habertürk Ekonomi", url: "https://www.haberturk.com/rss/kategori/ekonomi.xml", defaultCategory: "Ekonomi", blurb: "Ekonomi"),
    .init(id: "fotomac", name: "Fotomaç", url: "https://www.fotomac.com.tr/rss/anasayfa.xml", defaultCategory: "Spor", blurb: "Futbol"),
    .init(id: "aspor", name: "A Spor", url: "https://www.aspor.com.tr/rss/anasayfa.xml", defaultCategory: "Spor", blurb: "Futbol"),
    .init(id: "sabahspor", name: "Sabah Spor", url: "https://www.sabah.com.tr/rss/spor.xml", defaultCategory: "Spor", blurb: "Futbol"),
    .init(id: "hurriyetteknoloji", name: "Hürriyet Teknoloji", url: "https://www.hurriyet.com.tr/rss/teknoloji", defaultCategory: "Teknoloji", blurb: "Teknoloji"),
    .init(id: "log", name: "LOG", url: "https://www.log.com.tr/feed/", defaultCategory: "Teknoloji", blurb: "Teknoloji", pageable: true),
    .init(id: "cnnturkteknoloji", name: "CNN Türk Teknoloji", url: "https://www.cnnturk.com/feed/rss/teknoloji/news", defaultCategory: "Teknoloji", blurb: "Teknoloji"),
    // Spor: general sports desks plus single-branch feeds, so the Spor tab covers more than football
    .init(id: "hurriyetspor", name: "Hürriyet Spor", url: "https://www.hurriyet.com.tr/rss/spor", defaultCategory: "Spor", blurb: "Spor · tüm branşlar"),
    .init(id: "haberturkspor", name: "Habertürk Spor", url: "https://www.haberturk.com/rss/spor.xml", defaultCategory: "Spor", blurb: "Spor · tüm branşlar"),
    .init(id: "sozcuspor", name: "Sözcü Spor", url: "https://www.sozcu.com.tr/feeds-rss-category-spor", defaultCategory: "Spor", blurb: "Spor · tüm branşlar"),
    .init(id: "asporbasketbol", name: "A Spor Basketbol", url: "https://www.aspor.com.tr/rss/basketbol.xml", defaultCategory: "Spor", blurb: "Basketbol", branch: .basketbol),
    .init(id: "asporvoleybol", name: "A Spor Voleybol", url: "https://www.aspor.com.tr/rss/voleybol.xml", defaultCategory: "Spor", blurb: "Voleybol", branch: .voleybol),
    .init(id: "aspordiger", name: "A Spor Diğer Sporlar", url: "https://www.aspor.com.tr/rss/diger-sporlar.xml", defaultCategory: "Spor", blurb: "Atletizm, güreş, yüzme …"),
    .init(id: "fotomacbasketbol", name: "Fotomaç Basketbol", url: "https://www.fotomac.com.tr/rss/basketbol.xml", defaultCategory: "Spor", blurb: "Basketbol", branch: .basketbol),
    .init(id: "fotomacvoleybol", name: "Fotomaç Voleybol", url: "https://www.fotomac.com.tr/rss/voleybol.xml", defaultCategory: "Spor", blurb: "Voleybol", branch: .voleybol),
    .init(id: "fotomactenis", name: "Fotomaç Tenis", url: "https://www.fotomac.com.tr/rss/tenis.xml", defaultCategory: "Spor", blurb: "Tenis", branch: .tenis)
]

/// Sports branch of a Spor story. Single-branch feeds say it outright; otherwise it's read from the headline
/// and link. Anything that names no other branch counts as football, which leads every Turkish sports desk.
enum SportBranch: String, CaseIterable, Identifiable, Codable {
    case futbol = "Futbol", basketbol = "Basketbol", voleybol = "Voleybol", tenis = "Tenis", motor = "Motor Sporları", diger = "Diğer"
    var id: String { rawValue }

    /// Checked in this order, so "Fenerbahçe Beko" (basketball) is caught before the football club names.
    private static let keywords: [(SportBranch, [String])] = [
        (.basketbol, ["basketbol", "basket", "nba", "euroleague", "eurocup", "12 dev adam", "potada", "beko", "anadolu efes", "türk telekom bsl", "bsl"]),
        (.voleybol, ["voleybol", "filenin", "sultanlar ligi", "efeler ligi", "vnl", "vakıfbank", "eczacıbaşı", "zehra güneş", "melissa vargas"]),
        (.tenis, ["tenis", "wimbledon", "roland garros", "us open", "avustralya açık", "atp", "wta", "grand slam", "djokovic", "alcaraz", "sinner"]),
        (.motor, ["formula 1", "formula1", "f1", "motogp", "grand prix", "verstappen", "hamilton", "leclerc", "razgatlıoğlu", "superbike", "ralli", "nascar"]),
        (.diger, ["atletizm", "yüzme", "güreş", "boks", "judo", "hentbol", "okçuluk", "halter", "bisiklet", "golf", "kayak", "eskrim",
                  "olimpiyat", "paralimpik", "taekwondo", "karate", "satranç", "jimnastik", "kürek", "yelken", "madalya", "maraton", "buz hokeyi", "badminton"]),
    ]

    static func of(_ n: NewsItem) -> SportBranch {
        if let b = allNewsSources.first(where: { $0.id == n.sourceID })?.branch { return b }
        let tr = Locale(identifier: "tr_TR")
        let text = " " + (n.title + " " + (n.link?.path ?? "")).lowercased(with: tr) + " "
        for (branch, words) in keywords where words.contains(where: { w in
            // short tokens (nba, f1, atp, bsl) must stand alone so they don't match inside other words
            w.count <= 4 ? text.range(of: "(^|[^a-zçğıöşü0-9])\(NSRegularExpression.escapedPattern(for: w))($|[^a-zçğıöşü0-9])", options: .regularExpression) != nil
                         : text.contains(w)
        }) { return branch }
        return n.sourceID == "aspordiger" ? .diger : .futbol
    }
}

/// Sources added after a user may already have a saved (and thus stale) enabled-sources list —
/// unioned in on decode so a new tab like Teknoloji isn't empty, or a newly added source silently off, for existing installs.
/// Sources added together with the Spor tab; they start enabled for existing installs.
let sourcesAddedWithSpor: Set<String> = [
    "hurriyetspor", "haberturkspor", "sozcuspor", "asporbasketbol", "asporvoleybol", "aspordiger",
    "fotomacbasketbol", "fotomacvoleybol", "fotomactenis"
]

let sourcesAutoEnabledOnUpgrade: Set<String> = [
    "shiftdelete", "donanimhaber", "webrazzi",
    "sozcu", "haberturk", "odatv", "haberturkekonomi", "fotomac", "aspor", "sabahspor",
    "hurriyetteknoloji", "log", "cnnturkteknoloji"
]

let newsCategories = ["Gündem", "Ekonomi", "Dünya", "Spor", "Teknoloji"]

struct NewsItem: Identifiable, Codable, Hashable {
    let id: String
    let sourceID: String
    let source: String
    let category: String
    let title: String
    let summary: String
    let link: URL?
    let imageURL: URL?
    let date: Date

    /// Case- and accent-insensitive "contains", in Turkish (so "istanbul" matches "İstanbul").
    func mentions(_ word: String) -> Bool {
        title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) != nil
    }

    func dated(_ d: Date) -> NewsItem {
        NewsItem(id: id, sourceID: sourceID, source: source, category: category, title: title, summary: summary, link: link, imageURL: imageURL, date: d)
    }
}

/// A story saved to Arşiv. The whole item is kept, so it outlives the one-week news window.
struct Bookmark: Codable, Identifiable, Hashable {
    let item: NewsItem
    let savedAt: Date
    var id: String { item.id }
}

// MARK: - Economy

struct Instrument: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let unit: String
    let decimals: Int
    let blurb: String
}

let allInstruments: [Instrument] = [
    .init(id: "usd", code: "DOLAR/TL", name: "Dolar / Türk lirası", unit: "₺", decimals: 4, blurb: "Serbest piyasa"),
    .init(id: "eur", code: "EURO/TL", name: "Euro / Türk lirası", unit: "₺", decimals: 4, blurb: "Serbest piyasa"),
    .init(id: "gram", code: "GRAM ALTIN", name: "Gram altın", unit: "₺", decimals: 2, blurb: "Ons × Dolar/TL ÷ 31,1035"),
    .init(id: "bist", code: "BIST 100", name: "BIST 100 endeksi", unit: "", decimals: 2, blurb: "Borsa İstanbul"),
    .init(id: "brent", code: "BRENT", name: "Brent petrol", unit: "$", decimals: 2, blurb: "ICE vadeli"),
    .init(id: "btc", code: "BITCOIN", name: "Bitcoin", unit: "₺", decimals: 0, blurb: "TL karşılığı"),
    .init(id: "ceyrek", code: "ÇEYREK", name: "Çeyrek altın", unit: "₺", decimals: 2, blurb: "Hesaplanan (1,603 g)")
]

struct Currency: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

let allCurrencies: [Currency] = [
    Currency(code: "TRY", name: "Türk lirası"), Currency(code: "USD", name: "ABD doları"), Currency(code: "EUR", name: "Euro"),
    Currency(code: "GBP", name: "İngiliz sterlini"), Currency(code: "CHF", name: "İsviçre frangı"), Currency(code: "JPY", name: "Japon yeni"),
    Currency(code: "SAR", name: "Suudi riyali"), Currency(code: "AED", name: "BAE dirhemi"), Currency(code: "KWD", name: "Kuveyt dinarı"),
    Currency(code: "QAR", name: "Katar riyali"), Currency(code: "AZN", name: "Azerbaycan manatı"), Currency(code: "RUB", name: "Rus rublesi"),
    Currency(code: "CNY", name: "Çin yuanı"), Currency(code: "CAD", name: "Kanada doları"), Currency(code: "AUD", name: "Avustralya doları"),
    Currency(code: "SEK", name: "İsveç kronu"), Currency(code: "NOK", name: "Norveç kronu"), Currency(code: "DKK", name: "Danimarka kronu"),
    Currency(code: "BGN", name: "Bulgar levası"), Currency(code: "PLN", name: "Polonya zlotisi"),
    Currency(code: "GRAM", name: "Gram altın")
]

struct ChartPoint: Codable, Hashable { let t: Date; let v: Double }

struct Quote: Codable {
    var price: Double
    var prev: Double
    var high: Double
    var low: Double
    var points: [ChartPoint]
    var change: Double { prev == 0 ? 0 : (price - prev) / prev * 100 }
    var isUp: Bool { price >= prev }
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1G", week = "1H", month = "1A", year = "1Y"
    var id: String { rawValue }
    var yahooRange: String { switch self { case .day: "1d"; case .week: "5d"; case .month: "1mo"; case .year: "1y" } }
    var interval: String { switch self { case .day: "5m"; case .week: "30m"; case .month: "1d"; case .year: "1wk" } }
    var axisFormat: String { switch self { case .day: "HH:mm"; case .week, .month: "d MMM"; case .year: "MMM yy" } }
}

// MARK: - Football

struct League: Identifiable, Hashable {
    let id: String        // ESPN league slug
    let name: String
    let teamsOnly: Bool   // "Yalnızca takımlarım"
}

let allLeagues: [League] = [
    .init(id: "tur.1", name: "Süper Lig", teamsOnly: false),
    .init(id: "uefa.champions", name: "Şampiyonlar Ligi", teamsOnly: false),
    .init(id: "uefa.europa", name: "Avrupa Ligi", teamsOnly: true),
    .init(id: "eng.1", name: "Premier Lig", teamsOnly: false),
    .init(id: "esp.1", name: "LaLiga", teamsOnly: false),
    .init(id: "ita.1", name: "Serie A", teamsOnly: false)
]
/// International competitions (friendlies, Nations League, qualifiers, World Cup, Euro) — filtered to Türkiye.
let nationalSlugs: Set<String> = ["fifa.friendly", "uefa.nations", "fifa.worldq.uefa", "uefa.euroq", "fifa.world", "uefa.euro"]

enum MatchKind { case live, brk, upcoming, finished }

struct Match: Identifiable, Codable, Hashable {
    let id: String
    let leagueID: String
    let league: String
    let home: String
    let away: String
    let homeCode: String
    let awayCode: String
    let homeLogo: String?
    let awayLogo: String?
    let homeGoals: Int?
    let awayGoals: Int?
    let state: String        // pre / in / post
    let statusName: String   // ESPN status name, e.g. STATUS_HALFTIME
    let clock: String
    let kickoff: Date
    let venue: String
    let events: [MatchEvent]

    var kind: MatchKind {
        switch state {
        case "in": return statusName.contains("HALFTIME") || statusName.contains("END_OF") ? .brk : .live
        case "post": return statusName.contains("POSTPONED") || statusName.contains("CANCELED") ? .upcoming : .finished
        default: return .upcoming
        }
    }
    /// Being played right now, half-time included — these all count (and look) as live.
    var inPlay: Bool { kind == .live || kind == .brk }
    var scoreText: String {
        guard let h = homeGoals, let a = awayGoals, kind != .upcoming else { return "– – –" }
        return "\(h) – \(a)"
    }
    var statusText: String {
        if statusName.contains("POSTPONED") { return "Ertelendi" }
        if statusName.contains("CANCELED") { return "İptal" }
        if statusName.contains("DELAYED") || statusName.contains("SUSPENDED") { return "Durdu" }
        switch kind {
        case .live: return clock.isEmpty ? "CANLI" : clock
        case .brk: return statusName.contains("HALFTIME") ? "İY" : "Ara"
        case .finished: return "MS"
        case .upcoming: return Day.hm(kickoff)
        }
    }
}

struct MatchEvent: Identifiable, Codable, Hashable {
    let minute: String
    let icon: String
    let isYellow: Bool
    let title: String
    let note: String
    var id: String { "\(minute)|\(icon)|\(title)" }
}

struct MatchStat: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let home: String
    let away: String
    let ratio: Double
}

// MARK: - Notebook

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var time: String?
    var note: String?
    var done = false
    var day: String
}

struct JournalEntry: Codable, Hashable {
    var day: String
    var text: String
    var tags: [String]
    var savedAt: Date
}

// MARK: - Weather

struct Weather: Codable, Hashable {
    var temp: Double
    var code: Int
    var wind: Double      // km/h
    var isDay: Bool

    var isWindy: Bool { wind >= 35 && code <= 3 }

    /// Turkish description and SF Symbol for the WMO weather code.
    var summary: (text: String, symbol: String) { Self.describe(code: code, isDay: isDay, wind: wind) }
    var tempText: String { "\(Int(temp.rounded()))°" }

    static func describe(code: Int, isDay: Bool, wind: Double = 0) -> (text: String, symbol: String) {
        if wind >= 35 && code <= 3 { return ("Rüzgârlı", "wind") }
        switch code {
        case 0: return isDay ? ("Güneşli", "sun.max.fill") : ("Açık", "moon.stars.fill")
        case 1: return ("Az bulutlu", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 2: return ("Parçalı bulutlu", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Bulutlu", "cloud.fill")
        case 45, 48: return ("Sisli", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Çisenti", "cloud.drizzle.fill")
        case 61, 63, 80, 81: return ("Yağmurlu", "cloud.rain.fill")
        case 65, 82: return ("Şiddetli yağmur", "cloud.heavyrain.fill")
        case 66, 67: return ("Buzlu yağmur", "cloud.sleet.fill")
        case 71, 73, 75, 77, 85, 86: return ("Karlı", "cloud.snow.fill")
        case 95: return ("Gök gürültülü", "cloud.bolt.fill")
        case 96, 99: return ("Dolulu fırtına", "cloud.bolt.rain.fill")
        default: return ("Değişken", "cloud.fill")
        }
    }
}

/// One point of the hourly strip.
struct HourWeather: Codable, Hashable, Identifiable {
    let time: Date
    let temp: Double
    let code: Int
    let precipChance: Int
    var id: Date { time }
    var isDay: Bool { let h = Day.cal.component(.hour, from: time); return h >= 7 && h < 19 }
    var summary: (text: String, symbol: String) { Weather.describe(code: code, isDay: isDay) }
}

/// One day of the 7-day outlook.
struct DayWeather: Codable, Hashable, Identifiable {
    let date: Date
    let code: Int
    let tempMax: Double
    let tempMin: Double
    let precipChance: Int
    let sunrise: Date
    let sunset: Date
    let uvMax: Double
    var id: Date { date }
    var summary: (text: String, symbol: String) { Weather.describe(code: code, isDay: true) }
}

/// Full detail behind the Hava Durumu tab: current conditions plus the hourly and 7-day outlook.
struct WeatherDetail: Codable, Hashable {
    var current: Weather
    var feelsLike: Double
    var humidity: Int
    var pressure: Double
    var uvIndex: Double
    var windDir: Double
    var hourly: [HourWeather]
    var daily: [DayWeather]

    var windCompass: String {
        let dirs = ["K", "KKD", "KD", "DKD", "D", "DGD", "GD", "GGD", "G", "GGB", "GB", "BGB", "B", "BKB", "KB", "KKB"]
        return dirs[Int((windDir / 22.5).rounded()) % 16]
    }
    var uvLabel: String {
        switch uvIndex { case ..<3: "Düşük"; case ..<6: "Orta"; case ..<8: "Yüksek"; case ..<11: "Çok yüksek"; default: "Aşırı" }
    }
}

