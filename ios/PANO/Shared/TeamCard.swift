import SwiftUI

// MARK: - Model

struct TeamFixture: Identifiable, Hashable {
    let id: String
    let league: String
    let opponent: String
    let opponentLogo: String?
    let home: Bool
    let date: Date
    let goalsFor: Int?
    let goalsAgainst: Int?
    var finished: Bool { goalsFor != nil && goalsAgainst != nil }
    /// "G" win, "B" draw, "M" loss (Turkish galibiyet / beraberlik / mağlubiyet).
    var result: String? {
        guard let f = goalsFor, let a = goalsAgainst else { return nil }
        return f > a ? "G" : f == a ? "B" : "M"
    }
}

struct TableRow: Identifiable, Hashable {
    let rank: Int
    let team: String
    let logo: String?
    let played: Int
    let points: Int
    let goalDiff: String
    let mine: Bool
    var id: Int { rank }
}

struct TeamInfo {
    let query: String          // the name as the user follows it ("Galatasaray")
    let name: String
    let logo: String?
    let league: String
    let next: TeamFixture?
    let recent: [TeamFixture]  // newest first
    let table: [TableRow]      // the whole league table
    let fetched: Date
    var mine: TableRow? { table.first(where: \.mine) }
}

// MARK: - Service (ESPN's public soccer API, no key)

enum TeamService {
    private static let site = "https://site.web.api.espn.com/apis/site/v2/sports/soccer"
    private static let standingsBase = "https://site.web.api.espn.com/apis/v2/sports/soccer"
    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"; return f
    }()

    /// ESPN spells Turkish clubs without Turkish letters.
    private static let turkishNames = ["Fenerbahce": "Fenerbahçe", "Besiktas": "Beşiktaş", "Goztepe": "Göztepe",
        "Istanbul Basaksehir": "Başakşehir", "Kasimpasa": "Kasımpaşa", "Genclerbirligi": "Gençlerbirliği",
        "Caykur Rizespor": "Çaykur Rizespor", "Eyupspor": "Eyüpspor", "Erzurum BB": "Erzurumspor", "Antalyaspor": "Antalyaspor",
        "Sivasspor": "Sivasspor", "Kayserispor": "Kayserispor", "Hatayspor": "Hatayspor", "Bodrum FK": "Bodrum FK"]
    static func display(_ espn: String) -> String { turkishNames[espn] ?? espn }

    private static func json(_ url: String) async throws -> [String: Any] {
        guard let u = URL(string: url),
              let j = try JSONSerialization.jsonObject(with: try await fetch(u, via: appSession)) as? [String: Any] else { throw ServiceError.empty }
        return j
    }

    /// Finds the team in the followed leagues (the domestic league first), then loads its fixtures across all of
    /// them plus its league table.
    static func load(_ query: String) async throws -> TeamInfo {
        let want = Provinces.fold(query)
        var found: (id: String, name: String, logo: String?, slug: String)?
        for league in allLeagues {
            guard let j = try? await json("\(site)/\(league.id)/teams") else { continue }
            let teams = (((j["sports"] as? [[String: Any]])?.first?["leagues"] as? [[String: Any]])?.first?["teams"] as? [[String: Any]] ?? [])
                .compactMap { $0["team"] as? [String: Any] }
            if let t = teams.first(where: { t in
                let n = Provinces.fold(display(t["displayName"] as? String ?? ""))
                return n.contains(want) || want.contains(n)
            }), let id = t["id"] as? String {
                let logo = ((t["logos"] as? [[String: Any]])?.first?["href"] as? String)
                found = (id, display(t["displayName"] as? String ?? query), logo, league.id)
                break
            }
        }
        guard let team = found else { throw ServiceError.empty }

        // fixtures and results from every followed competition, in parallel
        var fixtures: [String: TeamFixture] = [:]
        await withTaskGroup(of: [TeamFixture].self) { g in
            for league in allLeagues {
                for suffix in ["", "?fixture=true"] {
                    g.addTask { (try? await schedule(team.id, league: league, suffix: suffix)) ?? [] }
                }
            }
            for await list in g { for f in list { fixtures[f.id] = f } }
        }
        let all = fixtures.values.sorted { $0.date < $1.date }
        let now = Date()
        let next = all.first { !$0.finished && $0.date > now.addingTimeInterval(-2 * 3600) }
        let recent = Array(all.filter(\.finished).reversed())
        let table = (try? await standings(team.slug, mine: team.id)) ?? []
        return TeamInfo(query: query, name: team.name, logo: team.logo,
                        league: allLeagues.first { $0.id == team.slug }?.name ?? "",
                        next: next, recent: recent, table: table, fetched: now)
    }

    private static func schedule(_ id: String, league: League, suffix: String) async throws -> [TeamFixture] {
        let j = try await json("\(site)/\(league.id)/teams/\(id)/schedule\(suffix)")
        return (j["events"] as? [[String: Any]] ?? []).compactMap { e in
            guard let eid = e["id"] as? String, let comp = (e["competitions"] as? [[String: Any]])?.first,
                  let cs = comp["competitors"] as? [[String: Any]],
                  let me = cs.first(where: { (($0["team"] as? [String: Any])?["id"] as? String) == id }),
                  let them = cs.first(where: { (($0["team"] as? [String: Any])?["id"] as? String) != id }),
                  let date = iso.date(from: (e["date"] as? String) ?? "") else { return nil }
            let state = ((comp["status"] as? [String: Any])?["type"] as? [String: Any])?["state"] as? String ?? "pre"
            func goals(_ c: [String: Any]) -> Int? {
                guard state == "post" else { return nil }
                if let s = c["score"] as? [String: Any] { return (s["value"] as? Double).map { Int($0) } ?? Int(s["displayValue"] as? String ?? "") }
                return Int(c["score"] as? String ?? "")
            }
            let tt = them["team"] as? [String: Any] ?? [:]
            let logo = (tt["logos"] as? [[String: Any]])?.first?["href"] as? String ?? tt["logo"] as? String
            return TeamFixture(id: eid, league: league.name, opponent: display(tt["displayName"] as? String ?? "?"),
                               opponentLogo: logo, home: (me["homeAway"] as? String) == "home", date: date,
                               goalsFor: goals(me), goalsAgainst: goals(them))
        }
    }

    private static func standings(_ slug: String, mine id: String) async throws -> [TableRow] {
        let j = try await json("\(standingsBase)/\(slug)/standings")
        let entries = ((j["children"] as? [[String: Any]])?.first?["standings"] as? [String: Any])?["entries"] as? [[String: Any]] ?? []
        return entries.compactMap { e in
            guard let t = e["team"] as? [String: Any] else { return nil }
            var s: [String: String] = [:]
            for st in e["stats"] as? [[String: Any]] ?? [] {
                if let n = st["name"] as? String, let v = st["displayValue"] as? String { s[n] = v }
            }
            guard let rank = Int(s["rank"] ?? "") else { return nil }
            return TableRow(rank: rank, team: display(t["displayName"] as? String ?? "?"),
                            logo: (t["logos"] as? [[String: Any]])?.first?["href"] as? String,
                            played: Int(s["gamesPlayed"] ?? "") ?? 0, points: Int(s["points"] ?? "") ?? 0,
                            goalDiff: s["pointDifferential"] ?? "0", mine: (t["id"] as? String) == id)
        }.sorted { $0.rank < $1.rank }
    }
}

// MARK: - Card (Bugün)

/// Bugün › Takımım: position, form, next and last match, a slice of the table and the latest news for a
/// followed team. Several followed teams get a small switcher.
struct TeamCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let teams = store.prefs.favoriteTeams
        if !teams.isEmpty {
            let current = teams.contains(store.teamSelected) ? store.teamSelected : teams[0]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "TAKIMIM")
                    if teams.count > 1 {
                        ForEach(teams, id: \.self) { t in
                            Button { store.teamSelected = t } label: { Pill(text: t, selected: t == current) }.buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    LinkText(text: "Maçlar →") { store.screen = .futbol }
                }
                content(current)
            }
            .task(id: current) { await store.refreshTeam(current) }
        }
    }

    @ViewBuilder private func content(_ name: String) -> some View {
        if let info = store.teamInfo[name] {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    header(info).padding(14)
                    Rule(color: T.rule2)
                    HStack(alignment: .top, spacing: 0) {
                        fixtureBlock("SIRADAKİ MAÇ", info.next, upcoming: true).frame(maxWidth: .infinity, alignment: .leading)
                        VRule(color: T.rule2)
                        fixtureBlock("SON MAÇ", info.recent.first, upcoming: false).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !info.table.isEmpty {
                        Rule(color: T.rule2)
                        tableSlice(info).padding(.vertical, 6)
                    }
                    let news = store.sporNews.filter { $0.mentions(name) }.prefix(3)
                    if !news.isEmpty {
                        Rule(color: T.rule2)
                        VStack(alignment: .leading, spacing: 0) {
                            Eyebrow(text: "SON HABERLER", size: 9).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                            ForEach(Array(news)) { n in
                                Button { store.openNews(n) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(n.source.uppercased()).font(.mono(9)).foregroundStyle(T.accent).frame(width: 86, alignment: .leading).lineLimit(1)
                                        Text(n.title).font(.ui(12.5)).foregroundStyle(T.ink2).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(Day.relativeName(n.date).capitalized(with: Locale(identifier: "tr_TR"))).font(.mono(9.5, .regular)).foregroundStyle(T.ink3).fixedSize()
                                    }.padding(.horizontal, 14).padding(.vertical, 6).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }.padding(.bottom, 6)
                    }
                }
            }
        } else if case .failed(let m) = store.teamState {
            EmptyBox(title: m, subtitle: "Ayarlar › Maçlar'dan takım adını kontrol et")
        } else {
            SkeletonCard(title: "YÜKLENİYOR · \(name.uppercased(with: Locale(identifier: "tr_TR")))", widths: [0.7, 0.9, 0.5])
        }
    }

    private func header(_ info: TeamInfo) -> some View {
        HStack(spacing: 12) {
            TeamLogo(url: info.logo, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(info.query).font(.serif(20)).tracking(-0.2)
                if let m = info.mine {
                    Text("\(m.rank). sıra · \(m.points) puan · \(m.played) maç · \(info.league)").font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                } else {
                    Text(info.league).font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                }
            }
            Spacer()
            // last five, oldest → newest left to right
            HStack(spacing: 4) {
                ForEach(Array(info.recent.prefix(5).reversed())) { f in
                    let r = f.result ?? "–"
                    Text(r).font(.mono(10, .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(r == "G" ? T.up : r == "M" ? T.down : T.ink3, in: RoundedRectangle(cornerRadius: 5))
                        .help("\(f.home ? "vs" : "@") \(f.opponent) · \(f.goalsFor ?? 0)–\(f.goalsAgainst ?? 0)")
                }
            }
        }
    }

    private func fixtureBlock(_ title: String, _ f: TeamFixture?, upcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title, size: 9)
            if let f {
                HStack(spacing: 8) {
                    TeamLogo(url: f.opponentLogo, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.opponent).font(.ui(13, .semibold)).lineLimit(1)
                        Text(f.home ? "İç saha" : "Deplasman").font(.mono(9.5, .regular)).foregroundStyle(T.ink3)
                    }
                    Spacer(minLength: 4)
                    if let gf = f.goalsFor, let ga = f.goalsAgainst {
                        Text("\(gf)–\(ga)").font(.mono(16, .semibold))
                            .foregroundStyle(gf > ga ? T.up : gf < ga ? T.down : T.ink2)
                    }
                }
                Text(upcoming ? "\(Day.format(f.date, "d MMMM EEEE · HH:mm")) · \(countdown(f.date))" : Day.format(f.date, "d MMMM") + " · " + f.league)
                    .font(.mono(10, .regular)).foregroundStyle(upcoming ? T.accent : T.ink3).lineLimit(1)
            } else {
                Text(upcoming ? "Planlanmış maç yok" : "Henüz maç oynanmadı").font(.ui(12)).foregroundStyle(T.ink3)
            }
        }
        .padding(14)
    }

    private func countdown(_ d: Date) -> String {
        switch Day.cal.dateComponents([.day], from: Day.cal.startOfDay(for: Date()), to: Day.cal.startOfDay(for: d)).day ?? 0 {
        case ..<1: return "bugün"
        case 1: return "yarın"
        case let n: return "\(n) gün sonra"
        }
    }

    /// The team with two places either side (clamped at the top and bottom of the table).
    private func tableSlice(_ info: TeamInfo) -> some View {
        let rows: [TableRow] = {
            guard let i = info.table.firstIndex(where: \.mine) else { return Array(info.table.prefix(5)) }
            let lo = max(0, min(i - 2, info.table.count - 5)), hi = min(info.table.count, lo + 5)
            return Array(info.table[lo..<hi])
        }()
        return VStack(spacing: 0) {
            ForEach(rows) { r in
                HStack(spacing: 8) {
                    Text("\(r.rank)").font(.mono(10.5, r.mine ? .bold : .regular)).frame(width: 20, alignment: .trailing)
                    TeamLogo(url: r.logo, size: 16)
                    Text(r.team).font(.ui(12.5, r.mine ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    Text("\(r.played)").font(.mono(10.5, .regular)).foregroundStyle(T.ink3).frame(width: 22, alignment: .trailing)
                    Text(r.goalDiff).font(.mono(10.5, .regular)).foregroundStyle(T.ink3).frame(width: 30, alignment: .trailing)
                    Text("\(r.points)").font(.mono(11, .bold)).frame(width: 26, alignment: .trailing)
                }
                .foregroundStyle(r.mine ? T.accent : T.ink)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(r.mine ? T.accentSoft : .clear)
            }
        }
    }
}

struct TeamLogo: View {
    let url: String?
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                CachedImage(url: u) { Circle().fill(T.paper3) }
            } else {
                Circle().fill(T.paper3)
            }
        }
        .frame(width: size, height: size)
    }
}
