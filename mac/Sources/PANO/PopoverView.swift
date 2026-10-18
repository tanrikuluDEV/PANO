import SwiftUI
import AppKit

struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PanoWordmark(size: 16)
                Spacer()
                if let w = store.weather { WeatherBadge(weather: w, size: 11, showText: false) }
                Text(Day.hm(Date())).font(.mono(10, .regular)).foregroundStyle(T.ink3)
            }.padding(.horizontal, 15).padding(.vertical, 13).overlay(alignment: .bottom) { Rule() }

            HStack(spacing: 10) {
                quote("usd", "DOLAR/TL")
                quote("gram", "GRAM ALTIN")
            }.padding(.horizontal, 15).padding(.vertical, 12).overlay(alignment: .bottom) { Rule() }

            if let m = store.headlineMatch {
                let live = m.inPlay
                Button { showMain(); store.openFootball(match: m) } label: { HStack(spacing: 10) {
                    PulseDot(color: live ? T.down : m.kind == .upcoming ? .clear : T.ink3, pulsing: m.kind == .live)
                    Text(m.home).font(.ui(12.5, store.isFavorite(m.home) ? .semibold : .regular)).lineLimit(1)
                    Text(m.kind == .upcoming ? "–" : "\(m.homeGoals ?? 0) – \(m.awayGoals ?? 0)").font(.mono(14))
                    Text(m.away).font(.ui(12.5, store.isFavorite(m.away) ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(m.statusText).font(.mono(10)).foregroundStyle(live ? T.down : T.ink3)
                }
                .padding(.horizontal, 15).padding(.vertical, 11).background(T.paper2).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rule() }
            }

            if store.radio.current == nil || store.radio.state == .idle, !favoriteStations.isEmpty {
                // nothing playing: one-click start for the favourite stations
                HStack(spacing: 8) {
                    Eyebrow(text: "RADYO", size: 9)
                    ForEach(favoriteStations.prefix(3)) { st in
                        Button { store.radio.play(st) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(T.accent)
                                Text(st.name).font(.ui(11.5)).foregroundStyle(T.ink).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(T.paper2, in: Capsule()).overlay(Capsule().stroke(T.rule, lineWidth: 1))
                            .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15).padding(.vertical, 10).overlay(alignment: .bottom) { Rule() }
            } else if let st = store.radio.current, store.radio.state != .idle {
                HStack(spacing: 10) {
                    StationLogo(station: st, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.name).font(.ui(12.5, .semibold)).lineLimit(1)
                        Text(store.radio.state == .playing ? (store.radio.nowPlaying ?? "Canlı yayın") : store.radio.state == .stopped ? "Durduruldu" : "Bağlanıyor…")
                            .font(.mono(10, .regular)).foregroundStyle(T.ink3).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    SleepTimerMenu()
                    Button { store.radio.toggle() } label: {
                        Image(systemName: store.radio.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(T.accentInk)
                            .frame(width: 26, height: 26).background(T.accent, in: Circle())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 15).padding(.vertical, 10).background(T.paper2).overlay(alignment: .bottom) { Rule() }
            }

            VStack(alignment: .leading, spacing: 9) {
                let unread = store.unreadNewsCount
                HStack {
                    Eyebrow(text: "İLK 3 BAŞLIK", size: 9)
                    Spacer()
                    if unread > 0 {
                        Button { showMain(); store.newsMode = .list; store.screen = .haberler } label: {
                            Text("\(unread) yeni haber →").font(.mono(9.5)).foregroundStyle(T.accent)
                        }.buttonStyle(.plain)
                    }
                }
                if store.topHeadlines.isEmpty { Text("Haber yok").font(.ui(12)).foregroundStyle(T.ink3) }
                ForEach(store.topHeadlines.prefix(3)) { h in
                    Button {
                        store.openNews(h)
                        showMain()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(store.isUnread(h) ? T.accent : .clear).frame(width: 5, height: 5)
                            Text(shortSource(h.sourceID)).font(.mono(9)).foregroundStyle(T.accent)
                                .frame(width: 30, alignment: .leading).lineLimit(1)
                            Text(h.title).font(.serif(13.5, .regular)).lineSpacing(2).multilineTextAlignment(.leading).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15).padding(.vertical, 11).overlay(alignment: .bottom) { Rule() }

            let todos = store.todos(on: Day.key())
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: "BUGÜN · \(todos.filter(\.done).count) / \(todos.count)", size: 9)
                if todos.isEmpty { Text("Bugün için görev yok").font(.ui(12)).foregroundStyle(T.ink3) }
                ForEach(todos.prefix(5)) { t in
                    Button { store.toggle(t.id) } label: {
                        HStack(spacing: 9) {
                            Checkbox(checked: t.done, size: 14)
                            Text(t.title).font(.ui(12.5)).strikethrough(t.done).foregroundStyle(t.done ? T.ink3 : T.ink).lineLimit(1)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15).padding(.vertical, 11).overlay(alignment: .bottom) { Rule() }

            HStack(spacing: 9) {
                TextField("Hızlı not ekle…", text: $note).textFieldStyle(.plain).font(.ui(12.5))
                    .padding(.horizontal, 9).padding(.vertical, 7).background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1)).onSubmit(add)
                Button(action: add) {
                    Text("Ekle").font(.ui(12, .semibold)).foregroundStyle(T.accentInk)
                        .padding(.horizontal, 11).padding(.vertical, 8).background(T.accent, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }.padding(.horizontal, 15).padding(.vertical, 10)

            HStack {
                footer("Pencereyi aç") { showMain() }
                Spacer()
                footer("Ayarlar") { showMain(); store.screen = .ayarlar }
                Spacer()
                footer("Çıkış") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 15).padding(.vertical, 9).background(T.paper3).overlay(alignment: .top) { Rule() }
        }
        .frame(width: 360)
        .preferredColorScheme(store.colorScheme)
        .background(AppBackdrop(material: .popover))
        .id(store.lookID)
    }

    private func quote(_ id: String, _ label: String) -> some View {
        let inst = allInstruments.first { $0.id == id }!
        let q = store.quotes[id]
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(9)).tracking(0.7).foregroundStyle(T.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(q.map { inst.priceText($0) } ?? "—").font(.mono(16)).lineLimit(1).minimumScaleFactor(0.7)
                if let q { Text(q.changeText).font(.mono(10)).foregroundStyle(q.color).lineLimit(1) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.ui(11.5)).foregroundStyle(T.ink2) }.buttonStyle(.plain)
    }

    private func shortSource(_ id: String) -> String {
        ["aa": "AA", "bbc": "BBC", "bloomberght": "BHT", "dunya": "DNY", "cumhuriyet": "CUM", "hurriyet": "HUR",
         "ntv": "NTV", "webtekno": "WBT", "trt": "TRT", "trtspor": "TRS", "ekonomim": "EKO"][id] ?? id.prefix(3).uppercased()
    }

    private func add() { store.appendNote(note); note = "" }

    private var favoriteStations: [Station] {
        store.radio.favorites.compactMap { id in store.radio.stations.first { $0.id == id } }
    }

    private func showMain() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
