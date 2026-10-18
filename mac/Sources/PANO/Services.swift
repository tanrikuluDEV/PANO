import Foundation

enum ServiceError: LocalizedError {
    case http(Int)
    case api(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let c): return "Kaynak yanıt vermiyor (\(c))."
        case .api(let m): return m
        case .empty: return "Kaynak boş yanıt verdi."
        }
    }
}

let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 15
    c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) PANO/1.0"]
    return URLSession(configuration: c)
}()

func fetch(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
    var req = URLRequest(url: url)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let (data, resp) = try await session.data(for: req)
    if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw ServiceError.http(h.statusCode) }
    return data
}

// MARK: - RSS

private final class RSSParser: NSObject, XMLParserDelegate {
    struct Raw { var title = "", desc = "", link = "", guid = "", date = "", image = "", category = "" }
    var items: [Raw] = []
    private var cur: Raw?
    private var text = ""
    private var stack: [String] = []

    func parse(_ data: Data) -> [Raw] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        stack.append(name)
        text = ""
        switch name {
        case "item", "entry": cur = Raw()
        case "media:thumbnail", "media:content":
            if cur != nil, cur!.image.isEmpty, let u = a["url"], (a["medium"] ?? "image") == "image" { cur!.image = u }
        case "enclosure":
            if cur != nil, cur!.image.isEmpty, let u = a["url"], (a["type"] ?? "image").hasPrefix("image") { cur!.image = u }
        case "link":
            if cur != nil, let h = a["href"], cur!.link.isEmpty { cur!.link = h }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(data: CDATABlock, encoding: .utf8) ?? "" }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { _ = stack.popLast() }
        guard cur != nil else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": if cur!.title.isEmpty { cur!.title = t }
        case "description", "summary": if cur!.desc.isEmpty { cur!.desc = t }
        case "content:encoded", "content": if cur!.desc.isEmpty { cur!.desc = t }
        case "link": if !t.isEmpty { cur!.link = t }
        case "guid", "id": cur!.guid = t
        case "pubDate", "published", "updated", "dc:date": if cur!.date.isEmpty { cur!.date = t }
        case "category": if cur!.category.isEmpty { cur!.category = t }
        case "item", "entry": items.append(cur!); cur = nil
        default: break
        }
        text = ""
    }
}

private let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z"].map {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
}

/// Whether a feed date claims to be UTC ("GMT", "Z", "+0000" …) — the label some Turkish feeds put on local time.
private func labelledUTC(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespaces).range(of: "(GMT|UTC|UT|Z|[+-]00:?00)$", options: .regularExpression) != nil
}

/// Sources whose "GMT" times are really Türkiye time, learned when one of their stories turns up in the future.
/// Remembered, so the correction still applies at night when nothing new is "in the future" to give it away.
private enum MislabelledFeeds {
    private static let key = "feedsWithLocalTimeAsUTC"
    static func contains(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id) }
    static func insert(_ id: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !list.contains(id) { list.append(id); UserDefaults.standard.set(list, forKey: key) }
    }
}

private func parseDate(_ s: String) -> Date? {
    let iso = ISO8601DateFormatter()
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    for f in rfc822 { if let d = f.date(from: s) { return d } }
    return nil
}

func stripHTML(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let named = try! NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]{1,8});")
    for m in named.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed() {
        let ns = out as NSString
        let name = ns.substring(with: m.range(at: 1))
        let rep: String? = name == "nbsp" ? " " : ["quot": "\"", "apos": "'", "lt": "<", "gt": ">"][name] ?? htmlEntities[name]
        if let rep { out = ns.replacingCharacters(in: m.range, with: rep) }
    }
    // numeric entities (&#8217; / &#x2019;)
    let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
    for m in numeric.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed() {
        let ns = out as NSString
        let hex = ns.substring(with: m.range(at: 1)).lowercased() == "x"
        if let code = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let u = Unicode.Scalar(code) {
            out = ns.replacingCharacters(in: m.range, with: String(Character(u)))
        }
    }
    out = out.replacingOccurrences(of: "&amp;", with: "&")
    return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func classify(_ link: String, _ raw: String, default d: String) -> String {
    let l = link.lowercased(), c = raw.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { l.contains($0) || c.contains($0) } }
    if has(["/spor", "spor/", "futbol", "basketbol"]) { return "Spor" }
    if has(["/ekonomi", "ekonomi/", "/finans", "borsa", "/piyasalar"]) { return "Ekonomi" }
    if has(["/dunya", "dunya/", "/world", "/dünya"]) && d != "Ekonomi" { return "Dünya" }
    if has(["/teknoloji", "teknoloji/", "/bilim", "/tech"]) { return "Teknoloji" }
    return d
}

enum NewsService {
    /// Start of the news window: today plus the six days before it (BUGÜN, DÜN … a full week).
    static var cutoff: Date { Day.cal.date(byAdding: .day, value: -6, to: Day.cal.startOfDay(for: Date())) ?? Date() }

    /// Every item the feed carries within the week. With `backfill`, a pageable feed is also walked
    /// page by page (`?paged=2`, `3` …) until it reaches past the window, runs dry, or hits the page cap.
    static func fetch(_ src: NewsSource, backfill: Bool = false) async throws -> [NewsItem] {
        guard let url = URL(string: src.url) else { return [] }
        let cutoff = cutoff
        var items = try parse(await PANO.fetch(url), src)
        if backfill, src.pageable {
            var seen = Set(items.map(\.id))
            for page in 2...15 {
                guard let oldest = items.map(\.date).min(), oldest >= cutoff,
                      let u = URL(string: src.url + (src.url.contains("?") ? "&" : "?") + "paged=\(page)"),
                      let more = try? parse(await PANO.fetch(u), src) else { break }
                let new = more.filter { seen.insert($0.id).inserted }
                if new.isEmpty { break }
                items += new
            }
        }
        return items.filter { $0.date >= cutoff }
    }

    private static func parse(_ data: Data, _ src: NewsSource) throws -> [NewsItem] {
        let raws = RSSParser().parse(data)
        if raws.isEmpty { throw ServiceError.empty }
        // A "GMT" time more than 10 minutes ahead of now means the feed writes Türkiye time with a UTC label
        // (CNN Türk does): read all of this source's UTC-labelled times as Türkiye time from now on.
        let now = Date()
        let tr = TimeZone(identifier: "Europe/Istanbul") ?? .current
        if raws.contains(where: { labelledUTC($0.date) && (parseDate($0.date) ?? now) > now.addingTimeInterval(600) }) {
            MislabelledFeeds.insert(src.id)
        }
        let shift = MislabelledFeeds.contains(src.id)
        return raws.compactMap { r in
            let title = stripHTML(r.title)
            guard !title.isEmpty else { return nil }
            let link = r.link.isEmpty ? r.guid : r.link
            var date = parseDate(r.date) ?? now
            if shift, labelledUTC(r.date) { date -= TimeInterval(tr.secondsFromGMT(for: date)) }
            date = min(date, now)   // whatever else a feed gets wrong, a story can't be from the future
            return NewsItem(
                id: src.id + "|" + (r.guid.isEmpty ? link : r.guid),
                sourceID: src.id, source: src.name,
                category: classify(link, r.category, default: src.defaultCategory),
                title: title, summary: stripHTML(r.desc),
                link: URL(string: link),
                imageURL: URL(string: r.image),
                date: date
            )
        }
    }

    /// Returns items plus per-source failures, so one dead feed never hides the rest.
    /// Sources listed in `backfill` are paged back through the whole week.
    static func fetchAll(_ sources: [NewsSource], backfill: Set<String> = []) async -> (items: [NewsItem], failed: [String]) {
        await withTaskGroup(of: (String, [NewsItem]?).self) { group in
            for s in sources { group.addTask { (s.name, try? await fetch(s, backfill: backfill.contains(s.id))) } }
            var items: [NewsItem] = [], failed: [String] = []
            for await (name, r) in group { if let r { items += r } else { failed.append(name) } }
            return (items.sorted { $0.date > $1.date }, failed)
        }
    }
}

// MARK: - Markets (Yahoo Finance chart endpoint, no key)

enum MarketService {
    private struct Resp: Decodable {
        struct Chart: Decodable {
            struct Result: Decodable {
                struct Meta: Decodable {
                    let regularMarketPrice: Double?
                    let chartPreviousClose: Double?
                    let regularMarketDayHigh: Double?
                    let regularMarketDayLow: Double?
                }
                struct Ind: Decodable { struct Q: Decodable { let close: [Double?]? }; let quote: [Q] }
                let meta: Meta
                let timestamp: [Int]?
                let indicators: Ind
            }
            let result: [Result]?
        }
        let chart: Chart
    }

    private static func base(_ symbol: String, _ range: ChartRange) async throws -> Quote {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=\(range.yahooRange)&interval=\(range.interval)")!
        let r = try JSONDecoder().decode(Resp.self, from: try await fetch(url))
        guard let res = r.chart.result?.first, let price = res.meta.regularMarketPrice else { throw ServiceError.empty }
        let closes = res.indicators.quote.first?.close ?? []
        let ts = res.timestamp ?? []
        var pts: [ChartPoint] = []
        for (i, t) in ts.enumerated() where i < closes.count {
            if let v = closes[i] { pts.append(ChartPoint(t: Date(timeIntervalSince1970: TimeInterval(t)), v: v)) }
        }
        // Yahoo intraday data contains bad ticks; drop points far from their neighbours' median.
        if range == .day || range == .week { pts = despike(pts, tolerance: symbol.hasSuffix("TRY=X") ? 0.004 : 0.03) }
        let vals = pts.map(\.v)
        let clean = vals.count > 3
        return Quote(price: price, prev: res.meta.chartPreviousClose ?? vals.first ?? price,
                     high: clean ? max(vals.max()!, price) : res.meta.regularMarketDayHigh ?? price,
                     low: clean ? min(vals.min()!, price) : res.meta.regularMarketDayLow ?? price, points: pts)
    }

    private static func despike(_ pts: [ChartPoint], tolerance: Double) -> [ChartPoint] {
        guard pts.count > 9 else { return pts }
        let v = pts.map(\.v)
        return pts.enumerated().filter { i, p in
            let lo = max(0, i - 4), hi = min(v.count - 1, i + 4)
            let med = v[lo...hi].sorted()[(hi - lo + 1) / 2]
            return abs(p.v - med) / med <= tolerance
        }.map(\.element)
    }

    private static func scaled(_ q: Quote, _ k: Double, prevK: Double? = nil) -> Quote {
        Quote(price: q.price * k, prev: q.prev * (prevK ?? k), high: q.high * k, low: q.low * k,
              points: q.points.map { ChartPoint(t: $0.t, v: $0.v * k) })
    }

    static func quote(_ id: String, range: ChartRange) async throws -> Quote {
        let gramDiv = 31.1035
        switch id {
        case "usd": return try await base("USDTRY=X", range)
        case "eur": return try await base("EURTRY=X", range)
        case "bist": return try await base("XU100.IS", range)
        case "brent": return try await base("BZ=F", range)
        case "gram", "ceyrek":
            async let g = base("GC=F", range)
            async let fx = base("USDTRY=X", .day)
            let (gold, usd) = try await (g, fx)
            let extra = id == "ceyrek" ? 1.603 : 1.0
            let k = usd.price / gramDiv * extra
            let prevK = range == .day ? usd.prev / gramDiv * extra : k
            return scaled(gold, k, prevK: prevK)
        case "btc":
            async let b = base("BTC-USD", range)
            async let fx = base("USDTRY=X", .day)
            let (btc, usd) = try await (b, fx)
            return scaled(btc, usd.price, prevK: range == .day ? usd.prev : usd.price)
        default: throw ServiceError.empty
        }
    }

    /// Units of each currency per 1 USD (open.er-api.com, no key, refreshed daily on their side).
    static func fxRates() async -> [String: Double]? {
        struct R: Decodable { let result: String; let rates: [String: Double] }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD"),
              let r = try? JSONDecoder().decode(R.self, from: try await fetch(url)), r.result == "success" else { return nil }
        return r.rates
    }

    static func weather(lat: Double, lon: Double) async -> Weather? {
        await weatherDetail(lat: lat, lon: lon)?.current
    }

    private static let hourFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    private static let dayFmt2: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// Current conditions plus a 48-hour and 7-day outlook, all in the location's own timezone.
    static func weatherDetail(lat: Double, lon: Double) async -> WeatherDetail? {
        struct W: Decodable {
            struct C: Decodable {
                let temperature_2m: Double, apparent_temperature: Double, relative_humidity_2m: Int, weather_code: Int
                let wind_speed_10m: Double, wind_direction_10m: Double, is_day: Int, surface_pressure: Double, uv_index: Double
            }
            struct H: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]; let precipitation_probability: [Int] }
            struct D: Decodable {
                let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]
                let precipitation_probability_max: [Int]; let sunrise: [String]; let sunset: [String]; let uv_index_max: [Double]
            }
            let current: C; let hourly: H; let daily: D; let timezone: String
        }
        let params = "current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,surface_pressure,uv_index" +
            "&hourly=temperature_2m,weather_code,precipitation_probability" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max" +
            "&timezone=auto&forecast_days=7"
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&\(params)"),
              let w = try? JSONDecoder().decode(W.self, from: try await fetch(url)) else { return nil }
        let tz = TimeZone(identifier: w.timezone) ?? .current
        hourFmt.timeZone = tz; dayFmt2.timeZone = tz
        let now = Date()
        let hourly = zip(w.hourly.time.indices, w.hourly.time).compactMap { i, t -> HourWeather? in
            guard let d = hourFmt.date(from: t), d >= now.addingTimeInterval(-3600) else { return nil }
            return HourWeather(time: d, temp: w.hourly.temperature_2m[i], code: w.hourly.weather_code[i], precipChance: w.hourly.precipitation_probability[i])
        }
        let daily = (0..<w.daily.time.count).compactMap { i -> DayWeather? in
            guard let d = dayFmt2.date(from: w.daily.time[i]), let sr = hourFmt.date(from: w.daily.sunrise[i]), let ss = hourFmt.date(from: w.daily.sunset[i]) else { return nil }
            return DayWeather(date: d, code: w.daily.weather_code[i], tempMax: w.daily.temperature_2m_max[i], tempMin: w.daily.temperature_2m_min[i],
                              precipChance: w.daily.precipitation_probability_max[i], sunrise: sr, sunset: ss, uvMax: w.daily.uv_index_max[i])
        }
        let c = w.current
        return WeatherDetail(
            current: Weather(temp: c.temperature_2m, code: c.weather_code, wind: c.wind_speed_10m, isDay: c.is_day == 1),
            feelsLike: c.apparent_temperature, humidity: c.relative_humidity_2m, pressure: c.surface_pressure,
            uvIndex: c.uv_index, windDir: c.wind_direction_10m, hourly: Array(hourly.prefix(48)), daily: daily)
    }
}

// MARK: - Cities (Open-Meteo geocoding, no key)

struct City: Identifiable, Hashable {
    let name: String
    let region: String
    let lat: Double
    let lon: Double
    var id: String { "\(name)|\(lat)|\(lon)" }
    var subtitle: String { region }
}

/// Handy one-tap choices (coordinates of the city centres).
let quickCities: [City] = [
    City(name: "İstanbul", region: "İstanbul", lat: 41.01, lon: 28.98), City(name: "Ankara", region: "Ankara", lat: 39.93, lon: 32.86),
    City(name: "İzmir", region: "İzmir", lat: 38.41, lon: 27.14), City(name: "Bursa", region: "Bursa", lat: 40.18, lon: 29.07),
    City(name: "Antalya", region: "Antalya", lat: 36.90, lon: 30.70), City(name: "Adana", region: "Adana", lat: 37.00, lon: 35.32),
    City(name: "Konya", region: "Konya", lat: 37.87, lon: 32.48), City(name: "Trabzon", region: "Trabzon", lat: 41.00, lon: 39.72)
]

enum CityService {
    static func search(_ text: String) async -> [City] {
        struct R: Decodable {
            struct I: Decodable { let name: String; let admin1: String?; let country: String?; let latitude: Double; let longitude: Double; let feature_code: String? }
            let results: [I]?
        }
        let enc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=10&language=tr&format=json"),
              let r = try? JSONDecoder().decode(R.self, from: try await fetch(url)) else { return [] }
        return (r.results ?? []).filter { ($0.feature_code ?? "PPL").hasPrefix("PPL") || ($0.feature_code ?? "").hasPrefix("ADM") }.map {
            City(name: $0.name, region: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                 lat: $0.latitude, lon: $0.longitude)
        }
    }
}

// MARK: - Football (ESPN public scoreboard API — no key)

enum FootballService {
    private static let base = "https://site.api.espn.com/apis/site/v2/sports/soccer"
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f
    }()
    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"; return f
    }()

    private static func json(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw ServiceError.empty }
        guard let j = try JSONSerialization.jsonObject(with: try await fetch(url)) as? [String: Any] else { throw ServiceError.empty }
        return j
    }

    /// `day` is a local "yyyy-MM-dd" key; nil returns ESPN's default window (used for national-team competitions).
    static func scoreboard(slug: String, leagueName: String?, day: String?) async throws -> [Match] {
        var q = ""
        if let day, let d = Day.date(day) { q = "?dates=" + dayFmt.string(from: d) }
        let j = try await json("/\(slug)/scoreboard\(q)")
        let fallbackName = ((j["leagues"] as? [[String: Any]])?.first?["name"] as? String) ?? slug
        return (j["events"] as? [[String: Any]] ?? []).compactMap { e in
            guard let id = e["id"] as? String, let comp = (e["competitions"] as? [[String: Any]])?.first,
                  let comps = comp["competitors"] as? [[String: Any]] else { return nil }
            func side(_ s: String) -> [String: Any]? { comps.first { ($0["homeAway"] as? String) == s } }
            guard let h = side("home"), let a = side("away"),
                  let ht = h["team"] as? [String: Any], let at = a["team"] as? [String: Any] else { return nil }
            let st = (comp["status"] as? [String: Any]) ?? [:]
            let type = (st["type"] as? [String: Any]) ?? [:]
            let state = type["state"] as? String ?? "pre"
            var names: [String: String] = [:]
            for t in [ht, at] { if let i = t["id"] as? String { names[i] = t["displayName"] as? String ?? "" } }
            let started = state != "pre"
            return Match(
                id: id, leagueID: slug, league: leagueName ?? fallbackName,
                home: ht["displayName"] as? String ?? "?", away: at["displayName"] as? String ?? "?",
                homeCode: ht["abbreviation"] as? String ?? "", awayCode: at["abbreviation"] as? String ?? "",
                homeLogo: ht["logo"] as? String, awayLogo: at["logo"] as? String,
                homeGoals: started ? Int(h["score"] as? String ?? "") : nil,
                awayGoals: started ? Int(a["score"] as? String ?? "") : nil,
                state: state, statusName: type["name"] as? String ?? "", clock: st["displayClock"] as? String ?? "",
                kickoff: iso.date(from: (comp["date"] as? String) ?? (e["date"] as? String) ?? "") ?? Date(),
                venue: (comp["venue"] as? [String: Any])?["fullName"] as? String ?? "",
                events: events(comp["details"] as? [[String: Any]] ?? [], names: names))
        }
    }

    private static func events(_ details: [[String: Any]], names: [String: String]) -> [MatchEvent] {
        details.compactMap { d in
            let minute = (d["clock"] as? [String: Any])?["displayValue"] as? String ?? ""
            let player = ((d["athletesInvolved"] as? [[String: Any]])?.first?["displayName"] as? String) ?? "—"
            let team = names[(d["team"] as? [String: Any])?["id"] as? String ?? ""] ?? ""
            if d["scoringPlay"] as? Bool == true {
                let note = d["ownGoal"] as? Bool == true ? "Kendi kalesine · \(team)" : d["penaltyKick"] as? Bool == true ? "Penaltı · \(team)" : team
                return MatchEvent(minute: minute, icon: "⚽", isYellow: false, title: player, note: note)
            }
            if d["redCard"] as? Bool == true { return MatchEvent(minute: minute, icon: "▮", isYellow: false, title: player, note: "Kırmızı kart · \(team)") }
            if d["yellowCard"] as? Bool == true { return MatchEvent(minute: minute, icon: "▮", isYellow: true, title: player, note: "Sarı kart · \(team)") }
            return nil
        }
    }

    static func stats(slug: String, id: String) async throws -> [MatchStat] {
        let j = try await json("/\(slug)/summary?event=\(id)")
        let teams = (j["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]] ?? []
        func table(_ side: String) -> [String: String] {
            guard let t = teams.first(where: { ($0["homeAway"] as? String) == side }) else { return [:] }
            var out: [String: String] = [:]
            for s in t["statistics"] as? [[String: Any]] ?? [] {
                if let n = s["name"] as? String, let v = s["displayValue"] as? String { out[n] = v }
            }
            return out
        }
        let h = table("home"), a = table("away")
        let wanted: [(String, String, Bool)] = [("possessionPct", "Topla oynama", true), ("shotsOnTarget", "İsabetli şut", false),
                                                ("totalShots", "Toplam şut", false), ("wonCorners", "Korner", false), ("foulsCommitted", "Faul", false)]
        return wanted.compactMap { key, label, pct in
            guard let x = h[key], let y = a[key], let nx = Double(x), let ny = Double(y) else { return nil }
            func f(_ v: Double) -> String { pct ? "%\(Int(v.rounded()))" : String(Int(v)) }
            return MatchStat(name: label, home: f(nx), away: f(ny), ratio: nx + ny == 0 ? 0.5 : nx / (nx + ny))
        }
    }
}
