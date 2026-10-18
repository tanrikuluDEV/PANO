import SwiftUI

struct FutbolView: View {
    @Environment(AppStore.self) private var store

    private var days: [(id: String, label: String)] {
        let t = Day.key()
        return [(Day.shift(t, by: -1), "Dün"), (t, "Bugün"), (Day.shift(t, by: 1), "Yarın")]
    }

    private var groups: [(name: String, matches: [Match])] {
        var order: [String] = [], map: [String: [Match]] = [:]
        for m in store.footballMatches where store.footballLiveOnly || !nationalSlugs.contains(m.leagueID) {
            let name = nationalSlugs.contains(m.leagueID) ? "Milli takım" : (allLeagues.first { $0.id == m.leagueID }?.name ?? m.league)
            if map[name] == nil { order.append(name) }
            map[name, default: []].append(m)
        }
        return order.map { ($0, map[$0]!) }
    }
    private var national: [Match] { store.footballLiveOnly ? [] : store.matches(on: store.footballDay).filter { nationalSlugs.contains($0.leagueID) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Maçlar").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    HStack(spacing: 10) {
                        liveButton
                        Segmented(items: days, selection: Binding(get: { store.footballDay }, set: { store.selectFootballDay($0) }), radius: 8, hPad: 14,
                                  highlight: !store.footballLiveOnly)
                    }
                }
                HStack(spacing: 8) {
                    Eyebrow(text: "TAKİP EDİLENLER", size: 9.5)
                    ForEach(store.prefs.favoriteTeams, id: \.self) { chip($0, fav: true) }
                    ForEach(allLeagues.filter { store.prefs.enabledLeagues.contains($0.id) }) { chip($0.name, fav: false) }
                    if store.prefs.nationalTeam { chip("Milli takım", fav: false) }
                    Spacer()
                }.lineLimit(1)
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            .overlay(alignment: .bottom) { Rule() }

            if case .failed(let m) = store.footballState, (store.matches[store.footballDay] ?? []).isEmpty {
                ErrorCard(eyebrow: "HATA · MAÇLAR", message: m) { Task { await store.refreshFootball() } }
                    .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if store.footballState == .loading && groups.isEmpty { SkeletonCard(title: "YÜKLENİYOR · MAÇLAR").frame(maxWidth: 340) }
                            ForEach(groups, id: \.name) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 9) { Eyebrow(text: g.name.uppercased()); Rectangle().fill(T.rule2).frame(height: 1) }
                                    ForEach(g.matches) { MatchRow(m: $0) }
                                }
                            }
                            if !store.footballLiveOnly { VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 9) { Eyebrow(text: "MİLLİ TAKIM MAÇLARI"); Rectangle().fill(T.rule2).frame(height: 1) }
                                if national.isEmpty {
                                    EmptyBox(title: "Bugün takip ettiğin maç yok")
                                } else { ForEach(national) { MatchRow(m: $0) } }
                            } }
                            if groups.isEmpty && store.footballState != .loading {
                                if store.footballLiveOnly {
                                    EmptyBox(title: "Şu an canlı maç yok", subtitle: "Maçlar başladığında burada görünür")
                                } else {
                                    EmptyBox(title: "Bu gün takip ettiğin maç yok", actionTitle: "Lig ekle") { store.openSettingsAction?() }
                                }
                            }
                            RelatedNews(title: "FUTBOL HABERLERİ", items: store.futbolNews,
                                        emptyTitle: "Futbol haberi yok", emptySubtitle: "Ayarlar'dan haber kaynağı etkinleştir") {
                                store.sporQuery = ""; store.sporSourceFilter = nil; store.sporBranch = .futbol; store.screen = .spor
                            }
                        }.padding(.init(top: 16, leading: 20, bottom: 24, trailing: 20))
                    }
                    MatchDetailPanel().frame(width: 340)
                }
            }
        }
    }

    private var liveButton: some View {
        let on = store.footballLiveOnly
        let n = store.liveMatches.count
        return Button {
            if on { store.selectFootballDay(Day.key()) } else { store.openFootball(liveOnly: true) }
        } label: {
            HStack(spacing: 7) {
                PulseDot(color: on ? T.accentInk : T.down, pulsing: n > 0, size: 7)
                Text("Canlı").font(.ui(12, .semibold))
                if n > 0 { Text("\(n)").font(.mono(11)) }
            }
            .foregroundStyle(on ? T.accentInk : T.down)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? T.down : T.downSoft, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.down, lineWidth: on ? 0 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func chip(_ text: String, fav: Bool) -> some View {
        Text(text).font(.ui(11.5)).foregroundStyle(fav ? T.accent : T.ink2)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(fav ? T.accentSoft : T.paper2, in: Capsule())
            .overlay(Capsule().stroke(fav ? T.accent : T.rule, lineWidth: 1))
    }
}

struct MatchRow: View {
    @Environment(AppStore.self) private var store
    let m: Match
    var body: some View {
        let sel = m.id == store.selectedMatch?.id
        let live = m.inPlay
        Button { store.selectedMatchID = m.id; Task { await store.loadMatchDetail() } } label: {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    PulseDot(color: live ? T.down : m.kind == .upcoming ? .clear : T.ink3, pulsing: m.kind == .live)
                    Text(m.statusText).font(.mono(11)).foregroundStyle(live ? T.down : T.ink3)
                }.frame(width: 76, alignment: .leading)
                HStack(spacing: 14) {
                    HStack(spacing: 9) {
                        Spacer(minLength: 0)
                        Text(m.home).font(.ui(14, store.isFavorite(m.home) ? .semibold : .regular)).lineLimit(1)
                        TeamBadge(code: m.homeCode, logo: m.homeLogo, size: 26)
                    }
                    Text(m.scoreText).font(.mono(17)).tracking(0.3).foregroundStyle(m.kind == .upcoming ? T.ink3 : T.ink)
                    HStack(spacing: 9) {
                        TeamBadge(code: m.awayCode, logo: m.awayLogo, size: 26)
                        Text(m.away).font(.ui(14, store.isFavorite(m.away) ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Text(m.venue).font(.mono(10, .regular)).foregroundStyle(T.ink3).lineLimit(1).frame(maxWidth: 110, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(sel ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? T.accent : T.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct MatchDetailPanel: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let m = store.selectedMatch {
                    let live = m.inPlay
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "MAÇ DETAYI")
                        HStack(alignment: .center, spacing: 8) {
                            VStack(spacing: 7) {
                                TeamBadge(code: m.homeCode, logo: m.homeLogo, size: 46)
                                Text(m.home).font(.serif(15)).lineLimit(2).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                            Text(m.kind == .upcoming ? Day.hm(m.kickoff) : m.scoreText)
                                .font(.mono(m.kind == .upcoming ? 15 : 22)).tracking(0.5)
                                .foregroundStyle(m.kind == .upcoming ? T.ink3 : T.ink).fixedSize()
                            VStack(spacing: 7) {
                                TeamBadge(code: m.awayCode, logo: m.awayLogo, size: 46)
                                Text(m.away).font(.serif(15)).lineLimit(2).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }.padding(.vertical, 4)
                        HStack(spacing: 8) {
                            PulseDot(color: live ? T.down : m.kind == .upcoming ? .clear : T.ink3, pulsing: m.kind == .live)
                            Text(m.statusText).font(.mono(11)).foregroundStyle(live ? T.down : T.ink3)
                            Text("· \(m.venue)").font(.mono(11, .regular)).foregroundStyle(T.ink3).lineLimit(1)
                        }
                    }
                    Rule()
                    if m.kind == .upcoming {
                        Text("Maç henüz başlamadı. Başlama saati \(Day.hm(m.kickoff)).").font(.ui(13)).foregroundStyle(T.ink2)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "GOLLER VE OLAYLAR")
                            let ev = m.events
                            if ev.isEmpty { Text("Kayıtlı olay yok").font(.ui(13)).foregroundStyle(T.ink3) }
                            // newest event first
                            ForEach(Array(ev.reversed().enumerated()), id: \.offset) { _, o in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Text(o.minute).font(.mono(11)).foregroundStyle(T.ink3).frame(width: 34, alignment: .leading)
                                    Text(o.icon).font(.system(size: 11)).foregroundStyle(o.isYellow ? T.yellow : T.ink2).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(o.title).font(.ui(13)); Text(o.note).font(.ui(11.5)).foregroundStyle(T.ink3)
                                    }
                                }
                            }
                        }
                        Rule()
                        VStack(alignment: .leading, spacing: 9) {
                            Eyebrow(text: "İSTATİSTİK")
                            let st = store.stats[m.id] ?? []
                            if st.isEmpty { Text("İstatistik yok").font(.ui(13)).foregroundStyle(T.ink3) }
                            ForEach(st) { s in
                                HStack(spacing: 8) {
                                    Text(s.home).font(.mono(11.5)).frame(width: 38, alignment: .leading)
                                    VStack(spacing: 4) {
                                        Text(s.name).font(.ui(11)).foregroundStyle(T.ink3)
                                        GeometryReader { g in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(T.paper3)
                                                Capsule().fill(T.accent).frame(width: g.size.width * s.ratio)
                                            }
                                        }.frame(height: 4)
                                    }
                                    Text(s.away).font(.mono(11.5)).frame(width: 38, alignment: .trailing)
                                }
                            }
                        }
                    }
                } else {
                    Eyebrow(text: "MAÇ DETAYI")
                    Text("Bir maç seç").font(.ui(13)).foregroundStyle(T.ink3)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(T.paper2)
        .overlay(alignment: .leading) { VRule() }
        .task(id: store.selectedMatch?.id) { await store.loadMatchDetail() }
    }
}
