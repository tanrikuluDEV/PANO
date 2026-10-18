import SwiftUI
import UserNotifications

/// The ⌘, settings window.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        SettingsPane()
            .frame(width: 680, height: 520)
            .preferredColorScheme(store.colorScheme)
            .background(AppBackdrop())
            .id(store.lookID)
    }
}

/// The in-app Ayarlar screen.
struct AyarlarView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ayarlar").font(.serif(25)).tracking(-0.4)
                Spacer()
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            SettingsPane(embedded: true)
        }
    }
}

struct SettingsPane: View {
    @Environment(AppStore.self) private var store
    var embedded = false
    @State private var tab = "Genel"
    @State private var cityQuery = ""
    @State private var cityResults: [City] = []
    private let tabs = ["Genel", "Yenileme", "Haber kaynakları", "Maçlar", "Ekonomi"]

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { s in
                    Button { tab = s } label: {
                        Text(s).font(.ui(12.5, tab == s ? .semibold : .regular)).foregroundStyle(tab == s ? T.ink : T.ink2)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(tab == s ? T.paper2 : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, embedded ? 24 : 12).padding(.vertical, 10)
            .background(embedded ? Color.clear : T.sidebar)
            .overlay(alignment: .top) { if embedded { Rule() } }
            .overlay(alignment: .bottom) { Rule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case "Genel": general
                    case "Yenileme": refresh
                    case "Haber kaynakları": sources
                    case "Maçlar": football
                    default: economy
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, embedded ? 24 : 26).padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Groups

    private func bind<V>(_ kp: WritableKeyPath<Prefs, V>) -> Binding<V> {
        Binding(get: { store.prefs[keyPath: kp] }, set: { store.prefs[keyPath: kp] = $0 })
    }
    /// `eveningMinute` (minutes after midnight) as a time of today, for the time picker.
    private var eveningTime: Binding<Date> {
        Binding(get: {
            let m = store.prefs.eveningMinute
            return Day.cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            let c = Day.cal.dateComponents([.hour, .minute], from: $0)
            store.prefs.eveningMinute = (c.hour ?? 19) * 60 + (c.minute ?? 30)
        })
    }
    private func setBind<E: Hashable>(_ kp: WritableKeyPath<Prefs, Set<E>>, _ e: E) -> Binding<Bool> {
        Binding(get: { store.prefs[keyPath: kp].contains(e) }, set: { on in
            if on { store.prefs[keyPath: kp].insert(e) } else { store.prefs[keyPath: kp].remove(e) }
        })
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("KİŞİSEL") {
                HStack {
                    Text("Karşılama adı").font(.ui(13)); Spacer()
                    TextField("Adın", text: bind(\.userName)).textFieldStyle(.plain).font(.ui(13)).multilineTextAlignment(.trailing).frame(width: 160)
                }.padding(.horizontal, 14).padding(.vertical, 11)
            }
            weatherGroup
            group("GÖRÜNÜM") {
                pickerRowS("Görünüm modu", "Sağ üstteki Açık/Koyu düğmesiyle de değiştirilebilir",
                           [("system", "Sistem"), ("light", "Açık"), ("dark", "Koyu")],
                           Binding(get: { store.appearance ?? "system" }, set: { store.appearance = $0 == "system" ? nil : $0 }))
                pickerRowS("Arayüz stili", "Cam: buzlu cam paneller ve renkli arka plan · Klasik: düz kâğıt yüzeyler",
                           UIStyle.allCases.map { ($0.rawValue, $0.name) }, bind(\.uiStyle))
                    .overlay(alignment: .top) { Rule(color: T.rule2) }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Renk teması").font(.ui(13))
                        Text("Arka plan, kenar çubuğu, kartlar ve vurgu rengi").font(.ui(11.5)).foregroundStyle(T.ink3)
                    }
                    Spacer()
                    ColorThemeSwatches(selection: bind(\.colorTheme))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .overlay(alignment: .top) { Rule(color: T.rule2) }
            }
            group("SABAH ÖZETİ") {
                row("Sabah özeti bildirimi", "Hava, piyasalar, manşetler, görevler ve takımın — her sabah tek bildirim", bind(\.morningBrief), first: true)
                pickerRow("Saat", "Mac uykudaysa uyanınca, 4 saat içinde gönderilir",
                          [(6, "06:00"), (7, "07:00"), (8, "08:00"), (9, "09:00"), (10, "10:00")], bind(\.morningHour))
                TryNowRow { try await store.sendMorningBrief() }
            }
            group("GÜNÜN ÖZETİ") {
                row("Günün özeti bildirimi", "Günün öne çıkan haberleri — her akşam tek bildirim, tıklayınca Haberler › Günün Özeti açılır", bind(\.eveningBrief), first: true)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saat").font(.ui(13))
                        Text("Mac uykudaysa uyanınca, aynı gün içinde gönderilir").font(.ui(11.5)).foregroundStyle(T.ink3)
                    }
                    Spacer()
                    DatePicker("", selection: eveningTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.stepperField).fixedSize()
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .overlay(alignment: .top) { Rule(color: T.rule2) }
                TryNowRow { try await store.sendEveningBrief() }
            }
            group("TAKVİM") {
                row("Mac Takvimi etkinliklerini göster", "Bugün ekranındaki Takvim kartında günün toplantı ve etkinlikleri; açınca izin istenir", bind(\.showCalendarEvents), first: true)
            }
            group("AKARYAKIT") {
                row("Zam / indirim bildirimi", "Ekonomi › Akaryakıt'ta seçili ilde benzin, motorin ya da LPG fiyatı değişince", bind(\.fuelNotify), first: true)
            }
            group("MENÜ ÇUBUĞU") {
                row("Menü çubuğu simgesini göster", "Tek renkli simge, tıklayınca popover açılır", bind(\.showMenuIcon), first: true)
                row("Simgede Dolar/TL değerini göster", "Kapalıysa yalnızca simge görünür", bind(\.showFXInMenu))
                row("Canlı maç skorunu simgede göster", "Yalnızca takip edilen takımlar", bind(\.showScoreInMenu))
            }
            group("UYGULAMA") {
                row("Açılışta başlat", "Oturum açıldığında sessizce çalışır", bind(\.launchAtLogin), first: true)
                row("Pencereyi kapatınca menü çubuğunda kal", "Dock simgesi gizlenir", bind(\.stayInMenuBar))
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("HABER LİSTESİ") {
                row("Aynı haberleri birleştir", "Birden çok kaynağın verdiği haber tek satırda, \"+N kaynak\" etiketiyle görünür", bind(\.foldDuplicates), first: true)
            }
            group("ANAHTAR KELİME BİLDİRİMLERİ") {
                row("Anahtar kelime bildirimi", "Yeni bir başlık bu kelimelerden birini içerince bildirim gönder", bind(\.keywordNotify), first: true)
                ForEach(Array(store.prefs.alertKeywords.enumerated()), id: \.element) { i, k in
                    HStack {
                        Image(systemName: "bell").font(.system(size: 11)).foregroundStyle(T.accent).frame(width: 15)
                        Text(k).font(.ui(13))
                        Spacer()
                        Button { store.prefs.alertKeywords.remove(at: i) } label: { Text("Kaldır").font(.ui(11.5)).foregroundStyle(T.ink3) }.buttonStyle(.plain)
                    }.padding(.horizontal, 14).padding(.vertical, 11).overlay(alignment: .top) { Rule(color: T.rule2) }
                }
                AddKeywordRow()
            }
            group("ETKİN KAYNAKLAR") {
                ForEach(Array(allNewsSources.enumerated()), id: \.element.id) { i, s in
                    row(s.name, s.blurb, setBind(\.enabledSources, s.id), first: i == 0)
                }
            }
        }
    }

    private var football: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("TAKİP EDİLEN LİGLER") {
                ForEach(Array(allLeagues.enumerated()), id: \.element.id) { i, l in
                    row(l.name, l.teamsOnly ? "Yalnızca takımlarım" : "Tüm maçlar", setBind(\.enabledLeagues, l.id), first: i == 0)
                }
                row("Milli takım maçları", "Türkiye maçları", bind(\.nationalTeam))
            }
            group("TAKIMLARIM") {
                ForEach(Array(store.prefs.favoriteTeams.enumerated()), id: \.element) { i, t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) { Text(t).font(.ui(13)); Text("Gol bildirimi \(store.prefs.goalNotify ? "açık" : "kapalı")").font(.ui(11.5)).foregroundStyle(T.ink3) }
                        Spacer()
                        Button { store.prefs.favoriteTeams.remove(at: i) } label: { Text("Kaldır").font(.ui(11.5)).foregroundStyle(T.ink3) }.buttonStyle(.plain)
                    }.padding(.horizontal, 14).padding(.vertical, 11).overlay(alignment: .top) { if i > 0 { Rule(color: T.rule2) } }
                }
                AddTeamRow()
                row("Gol bildirimi", "Takımlarımın golleri için bildirim gönder", bind(\.goalNotify))
            }
        }
    }

    private var economy: some View {
        group("GÖSTERİLECEK GÖSTERGELER") {
            ForEach(Array(allInstruments.enumerated()), id: \.element.id) { i, ins in
                row(ins.name, ins.blurb, setBind(\.enabledIndicators, ins.id), first: i == 0)
            }
        }
    }

    private var refresh: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("VERİ YENİLEME") {
                pickerRow("Haber, ekonomi ve hava durumu", "Haberler, piyasalar, hava durumu bu aralıkla yenilenir",
                          [(30, "30 sn"), (60, "1 dk"), (300, "5 dk"), (900, "15 dk"), (0, "Elle")], bind(\.refreshSeconds), first: true)
                pickerRow("Canlı skorlar", "Bugün ve Maçlar ekranı açıkken ya da canlı maç varken uygulanır",
                          [(5, "5 sn"), (10, "10 sn"), (15, "15 sn"), (30, "30 sn"), (60, "1 dk")], bind(\.liveSeconds))
            }
            Text("Skorlar ESPN'in herkese açık verisinden gelir; anahtar gerekmez. Sol menüdeki Yenile düğmesi her şeyi hemen günceller.")
                .font(.ui(11.5)).foregroundStyle(T.ink3)
        }
    }

    private var weatherGroup: some View {
        group("HAVA DURUMU") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şehir").font(.ui(13))
                    Text("Bugün ekranındaki sıcaklık bu şehir için gösterilir").font(.ui(11.5)).foregroundStyle(T.ink3)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(store.prefs.cityName).font(.ui(13, .semibold))
                    if let w = store.weather { WeatherBadge(weather: w, size: 12) }
                }
            }.padding(.horizontal, 14).padding(.vertical, 11)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                    TextField("Şehir ara (ör. Eskişehir, Berlin)", text: $cityQuery).textFieldStyle(.plain).font(.ui(13))
                }
                .padding(.horizontal, 10).padding(.vertical, 7).background(T.paper, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                if cityQuery.trimmingCharacters(in: .whitespaces).count >= 2 {
                    if cityResults.isEmpty {
                        Text("Sonuç yok").font(.ui(12)).foregroundStyle(T.ink3)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(cityResults) { c in
                                Button { store.setCity(c); cityQuery = ""; cityResults = [] } label: {
                                    HStack {
                                        Text(c.name).font(.ui(13))
                                        Text(c.subtitle).font(.ui(11.5)).foregroundStyle(T.ink3)
                                        Spacer()
                                    }.padding(.vertical, 6).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    FlowChips(items: quickCities) { c in
                        Button { store.setCity(c) } label: { Pill(text: c.name, selected: store.prefs.cityName == c.name) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .overlay(alignment: .top) { Rule(color: T.rule2) }
        }
        .task(id: cityQuery) {
            let q = cityQuery.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { cityResults = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let r = await CityService.search(q)
            if !Task.isCancelled { cityResults = r }
        }
    }

    private func pickerRowS(_ title: String, _ sub: String, _ items: [(String, String)], _ sel: Binding<String>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.ui(13)); Text(sub).font(.ui(11.5)).foregroundStyle(T.ink3) }
            Spacer()
            Segmented(items: items, selection: sel, mono: false, radius: 7, hPad: 10)
        }.padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func pickerRow(_ title: String, _ sub: String, _ items: [(Int, String)], _ sel: Binding<Int>, first: Bool = false) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.ui(13)); Text(sub).font(.ui(11.5)).foregroundStyle(T.ink3) }
            Spacer()
            Segmented(items: items, selection: sel, mono: true, radius: 7, hPad: 10)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .top) { if !first { Rule(color: T.rule2) } }
    }

    // MARK: Building blocks

    private func group<C: View>(_ title: String, card: Bool = true, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Eyebrow(text: title)
            if card { Card { VStack(spacing: 0) { content() } } } else { content() }
        }
    }

    private func row(_ title: String, _ sub: String, _ on: Binding<Bool>, first: Bool = false) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13)); Text(sub).font(.ui(11.5)).foregroundStyle(T.ink3)
            }
            Spacer()
            ToggleSwitch(isOn: on)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .top) { if !first { Rule(color: T.rule2) } }
    }
}

struct AddKeywordRow: View {
    @Environment(AppStore.self) private var store
    @State private var word = ""
    var body: some View {
        HStack(spacing: 10) {
            Text("+").font(.ui(11)).foregroundStyle(T.ink3).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
            TextField("Kelime ekle (ör. deprem, faiz, Galatasaray)", text: $word).textFieldStyle(.plain).font(.ui(13))
                .onSubmit {
                    let w = word.trimmingCharacters(in: .whitespaces)
                    let tr = Locale(identifier: "tr_TR")
                    if !w.isEmpty, !store.prefs.alertKeywords.contains(where: { $0.lowercased(with: tr) == w.lowercased(with: tr) }) {
                        store.prefs.alertKeywords.append(w)
                    }
                    word = ""
                }
        }.padding(.horizontal, 14).padding(.vertical, 11).overlay(alignment: .top) { Rule(color: T.rule2) }
    }
}

struct AddTeamRow: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    var body: some View {
        HStack(spacing: 10) {
            Text("+").font(.ui(11)).foregroundStyle(T.ink3).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
            TextField("Takım ekle (ör. Fenerbahçe)", text: $name).textFieldStyle(.plain).font(.ui(13))
                .onSubmit {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, !store.prefs.favoriteTeams.contains(n) { store.prefs.favoriteTeams.append(n) }
                    name = ""
                }
        }.padding(.horizontal, 14).padding(.vertical, 11).overlay(alignment: .top) { Rule(color: T.rule2) }
    }
}

/// "Şimdi dene" for a summary notification. Says what happened — preparing, sent, or why it couldn't be
/// sent — instead of failing silently when macOS hasn't allowed PANO's notifications.
private struct TryNowRow: View {
    let send: () async throws -> Void
    @State private var state: Phase = .idle
    private enum Phase: Equatable { case idle, working, sent, denied, failed(String) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nasıl görüneceğini şimdi gör").font(.ui(13))
                if let note { Text(note).font(.ui(11.5)).foregroundStyle(state == .sent ? T.ink3 : T.accent) }
            }
            Spacer()
            if state == .denied || { if case .failed = state { true } else { false } }() {
                Button("Bildirim ayarlarını aç") {
                    let id = Bundle.main.bundleIdentifier ?? ""
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                }.font(.ui(12))
            }
            Button { Task { await run() } } label: {
                HStack(spacing: 6) {
                    if state == .working { ProgressView().controlSize(.small).tint(T.accentInk) }
                    Text(state == .working ? "Hazırlanıyor…" : state == .sent ? "Gönderildi ✓" : "Şimdi dene")
                }
                .font(.ui(12, .medium)).foregroundStyle(T.accentInk)
                .padding(.horizontal, 12).padding(.vertical, 6).background(T.accent, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).disabled(state == .working)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .top) { Rule(color: T.rule2) }
    }

    private var note: String? {
        switch state {
        case .idle, .working: nil
        case .sent: "Bildirim gönderildi. Görünmediyse Rahatsız Etme / Odak modunu kontrol et."
        case .denied: "macOS, PANO'nun bildirimlerine izin vermiyor. Sistem Ayarları › Bildirimler › PANO'dan aç."
        case .failed(let m): "Gönderilemedi: \(m)"
        }
    }

    private func run() async {
        state = .working
        let center = UNUserNotificationCenter.current()
        do {
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            guard await center.notificationSettings().authorizationStatus != .denied else { state = .denied; return }
            try await send()
            state = .sent
        } catch {
            state = (error as NSError).domain == UNErrorDomain ? .denied : .failed(error.localizedDescription)
        }
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        if state == .sent { state = .idle }
    }
}
