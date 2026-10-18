import SwiftUI

extension Instrument {
    func priceText(_ q: Quote) -> String { format(q.price, decimals: decimals) }
}
extension Quote {
    var color: Color { isUp ? T.up : T.down }
    var arrow: String { isUp ? "▲" : "▼" }
    var changeText: String { "\(arrow) \(percent(change))" }
}

struct BugunView: View {
    @Environment(AppStore.self) private var store

    private var dateLine: String { "\(Day.long(Date())) · \(store.prefs.cityName)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.greeting).font(.serif(29)).tracking(-0.4)
                        HStack(spacing: 8) {
                            Text(dateLine).font(.ui(13)).foregroundStyle(T.ink2)
                            if let w = store.weather {
                                Text("·").foregroundStyle(T.ink3)
                                Button { store.screen = .hava } label: { WeatherBadge(weather: w) }.buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer()
                    if !store.liveMatches.isEmpty {
                        Button { store.openFootball(liveOnly: true) } label: {
                            HStack(spacing: 8) {
                                PulseDot(color: T.down, pulsing: true)
                                Text("\(store.liveMatches.count) CANLI MAÇ").font(.mono(11))
                                Text("→").font(.ui(11)).foregroundStyle(T.ink3)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(T.paper2, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rule, lineWidth: 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }

                EconStrip()

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        FeaturedNews()
                        TeamCard()
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        FootballGlance()
                        TodayTodos()
                        TakvimCard()
                        DayNote()
                        TrafficGlance()
                        SehrimCard()
                    }.frame(width: 384)
                }
            }
            .padding(.init(top: 30, leading: 28, bottom: 24, trailing: 28))
        }
        .onAppear { AppStore.clearBadge() }
    }
}

struct EconStrip: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if case .failed(let msg) = store.econState, store.quotes.isEmpty {
            ErrorCard(eyebrow: "HATA · EKONOMİ", message: msg) { Task { await store.refreshEconomy() } }
        } else if store.quotes.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · EKONOMİ")
        } else {
            let items = Array(store.visibleInstruments.prefix(6))
            HStack(spacing: 10) {
                ForEach(items) { inst in
                    if let q = store.quotes[inst.id] {
                        Button { store.selectedIndicator = inst.id; store.screen = .ekonomi } label: { EconTile(inst: inst, q: q) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct EconTile: View {
    let inst: Instrument
    let q: Quote
    var body: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(inst.code).font(.mono(9.5)).tracking(0.8).foregroundStyle(T.ink3).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(inst.priceText(q)).font(.mono(17)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.6)
                    Text(inst.unit).font(.mono(11)).foregroundStyle(T.ink3)
                }
                HStack(alignment: .bottom) {
                    Text(q.changeText).font(.mono(11)).foregroundStyle(q.color)
                    Spacer(minLength: 4)
                    Sparkline(points: q.points, color: q.color).frame(width: 52, height: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FeaturedNews: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "ÖNE ÇIKAN HABERLER", link: "Tümü →") { store.screen = .haberler }
            switch store.newsState {
            case .failed(let m) where store.news.isEmpty:
                ErrorCard(eyebrow: "HATA · HABERLER", message: m) { Task { await store.refreshNews() } }
            case .loading, .idle:
                if store.news.isEmpty { SkeletonCard(title: "YÜKLENİYOR · HABERLER", widths: [0.8, 0.95, 0.6, 0.9, 0.7]) } else { list }
            default:
                if store.topHeadlines.isEmpty {
                    EmptyBox(title: "Gösterilecek haber yok", subtitle: "Ayarlar'dan haber kaynağı etkinleştir", actionTitle: "Kaynakları aç") { store.openSettingsAction?() }
                } else { list }
            }
        }
    }

    private var list: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(store.topHeadlines.enumerated()), id: \.element.id) { i, h in
                    if i > 0 { Rule(color: T.rule2) }
                    Button { store.openNews(h) } label: {
                        HStack(alignment: .top, spacing: 13) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(h.source.uppercased()).font(.mono(9.5)).tracking(0.6).foregroundStyle(T.accent)
                                    Circle().fill(T.ink3).frame(width: 3, height: 3)
                                    Text(Day.hm(h.date)).font(.mono(10, .regular)).foregroundStyle(T.ink3)
                                }
                                Text(h.title).font(.serif(16.5)).lineSpacing(3).multilineTextAlignment(.leading).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            NewsImage(url: h.imageURL).frame(width: 74, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.rule2, lineWidth: 1))
                        }
                        .padding(.horizontal, 15).padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct FootballGlance: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "MAÇLAR", link: "Tümü →") { store.screen = .futbol }
            if store.todayMatches.isEmpty {
                EmptyBox(title: "Bugün takip ettiğin maç yok")
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(store.glanceMatches.enumerated()), id: \.element.id) { _, m in
                            CompactMatch(m: m)
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}

struct CompactMatch: View {
    @Environment(AppStore.self) private var store
    let m: Match
    var body: some View {
        Button { store.openFootball(match: m) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    teamLine(m.homeCode, m.homeLogo, m.home, store.isFavorite(m.home))
                    teamLine(m.awayCode, m.awayLogo, m.away, store.isFavorite(m.away))
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(m.kind == .upcoming ? "–" : "\(m.homeGoals ?? 0)"); Text(m.kind == .upcoming ? "–" : "\(m.awayGoals ?? 0)")
                }
                .font(.mono(13)).lineSpacing(3).foregroundStyle(m.kind == .upcoming ? T.ink3 : T.ink)
                HStack(spacing: 5) {
                    PulseDot(color: m.inPlay ? T.down : m.kind == .upcoming ? .clear : T.ink3, pulsing: m.kind == .live, size: 5)
                    Text(m.statusText).font(.mono(10)).foregroundStyle(m.inPlay ? T.down : T.ink3)
                }.frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(m.inPlay ? T.downSoft.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func teamLine(_ code: String, _ logo: String?, _ name: String, _ fav: Bool) -> some View {
        HStack(spacing: 7) {
            TeamBadge(code: code, logo: logo)
            Text(name).font(.ui(12.5, fav ? .semibold : .regular)).lineLimit(1)
        }
    }
}

struct TodayTodos: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "BUGÜN YAPILACAKLAR")
            Card {
                VStack(spacing: 0) {
                    ForEach(store.todos(on: Day.key())) { TodoRow(todo: $0) }
                    HStack(spacing: 10) {
                        Text("+").font(.ui(11)).foregroundStyle(T.ink3).frame(width: 15, height: 15)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                        TextField("Yeni görev ekle", text: $draft).textFieldStyle(.plain).font(.ui(13))
                            .onSubmit { store.addTodo(draft, day: Day.key()); draft = "" }
                    }
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .overlay(alignment: .top) { Rule(color: T.rule2) }
                    .padding(.top, 4)
                }.padding(.vertical, 6)
            }
        }
    }
}

struct DayNote: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let e = store.entry(Day.key())
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "GÜNÜN NOTU", link: "Defteri aç →") { store.journalDay = Day.key(); store.screen = .defter }
            Card(padding: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    if let e, !e.text.isEmpty {
                        Text(e.text).font(.serif(14, .regular)).lineSpacing(4).foregroundStyle(T.ink2).lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Bugün için henüz not yok. Defteri açıp ilk satırı yaz.").font(.serif(14, .regular)).foregroundStyle(T.ink3)
                    }
                    if let e, !e.tags.isEmpty {
                        HStack(spacing: 6) { ForEach(Array(e.tags.enumerated()), id: \.offset) { i, t in Tag(text: i == 0 ? t : "#\(t)", accent: i == 0) } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
