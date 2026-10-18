import SwiftUI

struct RadyoView: View {
    @Environment(AppStore.self) private var store
    @State private var category = "Tümü"
    @State private var query = ""
    /// Kanallar (the station grid) or Çalanlar (song history).
    @State private var showSongs = false

    private var radio: RadioStore { store.radio }

    /// Province shown under Yerel: the user's pick, else the weather city if it has stations, else İstanbul.
    private var city: String {
        let counts = radio.localCounts
        if let c = radio.localCity, counts[c] != nil { return c }
        if let w = Provinces.match(store.prefs.cityName), counts[w] != nil { return w }
        return counts["İstanbul"] != nil ? "İstanbul" : Provinces.sorted(Array(counts.keys)).first ?? "İstanbul"
    }

    private func stations(in city: String) -> [Station] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if category == "Yerel" {
            let local = radio.allLocal.filter { $0.province == city }
            return q.isEmpty ? local : local.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        var list: [Station]
        if q.count >= 2 {
            let local = radio.stations.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            let ids = Set(local.map(\.id))
            list = local + radio.searchResults.filter { !ids.contains($0.id) }
        } else {
            list = radio.stations
        }
        switch category {
        case "Tümü": return list
        case "Favoriler": return list.filter { radio.isFavorite($0) }
        default: return list.filter { $0.category == category }
        }
    }

    var body: some View {
        // computed once per redraw and passed down — the list filters hundreds of stations
        let city = city
        let list = stations(in: city)
        VStack(spacing: 0) {
            if isPhone {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Radyo").font(.serif(25)).tracking(-0.4)
                    Spacer()
                    Text(showSongs ? "\(radio.songHistory.count) şarkı" : category == "Yerel" ? "\(list.count) kanal · \(city)" : "\(radio.stations.count) kanal")
                        .font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                HStack {
                    ModeSwitch(selection: $showSongs, options: [(false, "Kanallar"), (true, "Çalanlar")])
                    Spacer()
                    if !showSongs && category == "Yerel" && !radio.allLocal.isEmpty { cityMenu(city) }
                }
                if !showSongs {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(radioCategories, id: \.self) { c in
                                Button { category = c } label: { Pill(text: c, selected: category == c) }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(T.ink3)
                        TextField("Kanal ara", text: $query).textFieldStyle(.plain).font(.ui(15))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.rule, lineWidth: 1))
                }
            }
            .padding(.init(top: 8, leading: 16, bottom: 12, trailing: 16))
            .overlay(alignment: .bottom) { Rule() }
            } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Radyo").font(.serif(25)).tracking(-0.4)
                    ModeSwitch(selection: $showSongs, options: [(false, "Kanallar"), (true, "Çalanlar")])
                    // the city picker sits by the title: the filter row is already full at narrow widths
                    if !showSongs && category == "Yerel" && !radio.allLocal.isEmpty { cityMenu(city).padding(.leading, 6) }
                    Spacer()
                    Text(showSongs ? "\(radio.songHistory.count) şarkı" : category == "Yerel" ? "\(list.count) kanal · \(city)" : "\(radio.stations.count) kanal · Türkiye")
                        .font(.mono(11, .regular)).foregroundStyle(T.ink3)
                }
                if !showSongs {
                HStack(spacing: 8) {
                    ForEach(radioCategories, id: \.self) { c in
                        Button { category = c } label: { Pill(text: c, selected: category == c) }.buttonStyle(.plain)
                    }

                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
                        TextField("Kanal ara", text: $query).textFieldStyle(.plain).font(.ui(12.5)).frame(width: 130)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }
                }
            }
            .padding(.screenHeader)
            .overlay(alignment: .bottom) { Rule() }
            }

            if showSongs { SongHistoryView() } else { content(list, city: city) }
        }
        .task { if radio.stations.isEmpty || radio.loadState == .idle { await radio.loadStations() } }
        .task(id: category) { if category == "Yerel", radio.localState == .idle { await radio.loadLocal() } }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await radio.search(query)
        }
    }

    /// Only provinces that have stations are offered, each with its count; the weather city is marked.
    private func cityMenu(_ city: String) -> some View {
        let counts = radio.localCounts
        let weatherCity = Provinces.match(store.prefs.cityName)
        return Menu {
            ForEach(Provinces.sorted(Array(counts.keys)), id: \.self) { p in
                Button { radio.localCity = p } label: {
                    Text("\(p) (\(counts[p] ?? 0))" + (p == weatherCity ? " · hava durumu şehrin" : ""))
                }
            }
            Divider()
            Text("\(counts.count) ilde kayıtlı yerel kanal var")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 10.5))
                Text("\(city) ▾").font(.ui(12, .medium))
            }
            .foregroundStyle(T.accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.accent.opacity(0.4), lineWidth: 1))
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .help("Şehir seç")
    }

    @ViewBuilder private func content(_ list: [Station], city: String) -> some View {
        if category == "Yerel", radio.allLocal.isEmpty {
            if case .failed(let m) = radio.localState {
                ErrorCard(eyebrow: "HATA · YEREL RADYO", message: m) { Task { await radio.loadLocal() } }
                    .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                SkeletonCard(title: "YÜKLENİYOR · YEREL RADYOLAR").frame(maxWidth: 340).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if case .failed(let m) = radio.loadState, radio.stations.isEmpty {
            ErrorCard(eyebrow: "HATA · RADYO", message: m) { Task { await radio.loadStations() } }
                .frame(maxWidth: 340).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if radio.stations.isEmpty {
            SkeletonCard(title: "YÜKLENİYOR · RADYO").frame(maxWidth: 340).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if list.isEmpty {
            EmptyBox(title: category == "Favoriler" ? "Henüz favori kanal yok" : "Kanal bulunamadı",
                     subtitle: category == "Favoriler" ? "Bir kanalın ♡ simgesine dokunarak favorilere ekle"
                             : category == "Yerel" ? "\(city) için aramana uyan kanal yok" : "Başka bir kategori ya da arama dene")
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(list) { StationCard(station: $0) }
                }.padding(isPhone ? .init(top: 12, leading: 16, bottom: 20, trailing: 16) : .init(top: 18, leading: 24, bottom: 24, trailing: 24))
            }
        }
    }
}

struct StationCard: View {
    @Environment(AppStore.self) private var store
    let station: Station

    var body: some View {
        let radio = store.radio
        let isCurrent = radio.current?.id == station.id
        let active = isCurrent && radio.isPlaying
        Button { isCurrent ? radio.toggle() : radio.play(station) } label: {
            HStack(spacing: 12) {
                StationLogo(station: station, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name).font(.ui(13.5, .semibold)).lineLimit(1)
                    Text(station.detail).font(.mono(10, .regular)).foregroundStyle(T.ink3).lineLimit(1)
                }
                Spacer(minLength: 4)
                if active { Equalizer(animating: radio.state == .playing).frame(width: 16, height: 14) }
                Button { radio.toggleFavorite(station) } label: {
                    Text(radio.isFavorite(station) ? "♥" : "♡").font(.ui(15)).foregroundStyle(radio.isFavorite(station) ? T.down : T.ink3)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(isCurrent ? T.accentSoft : T.paper2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isCurrent ? T.accent : T.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct StationLogo: View {
    let station: Station
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            T.paper3
            Text(station.initials).font(.mono(size * 0.3, .bold)).foregroundStyle(T.ink2)
            if let l = station.logo, let url = URL(string: l) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFit().padding(4).background(.white) }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .overlay(RoundedRectangle(cornerRadius: size * 0.2).stroke(T.rule2, lineWidth: 1))
    }
}

struct Equalizer: View {
    var animating: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let h = animating ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i))) : 0.3
                    RoundedRectangle(cornerRadius: 1).fill(T.accent).frame(width: 3).scaleEffect(y: h, anchor: .bottom)
                }
            }.frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Pinned under every screen while a station is selected.
struct NowPlayingBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let radio = store.radio
        if let s = radio.current, radio.state != .idle {
            @Bindable var radio = radio
            let song = radio.state == .playing ? radio.currentSong : nil
            HStack(spacing: 14) {
                if let song {
                    SongArtwork(url: song.artwork, size: 40)
                        .overlay(alignment: .bottomTrailing) { StationLogo(station: s, size: 18).offset(x: 5, y: 5) }
                } else {
                    StationLogo(station: s, size: 40)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.ui(13, .semibold)).lineLimit(1)
                    Text(song.map { [$0.artist, $0.track].compactMap { $0 }.joined(separator: " – ") }.flatMap { $0.isEmpty ? nil : $0 } ?? statusLine(radio, s))
                        .font(.mono(11, .regular))
                        .foregroundStyle({ if case .failed = radio.state { return T.down } else { return T.ink3 } }()).lineLimit(1)
                }
                if let song { AppleMusicButton(song: song, compact: true) }
                Spacer(minLength: 12)
                if radio.state == .playing { Equalizer(animating: true).frame(width: 16, height: 14) }
                HStack(spacing: 6) {
                    Button { radio.toggleFavorite(s) } label: {
                        Text(radio.isFavorite(s) ? "♥" : "♡").font(.ui(16)).foregroundStyle(radio.isFavorite(s) ? T.down : T.ink3).frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                    Button { radio.step(-1, in: store.radio.stations) } label: { Image(systemName: "backward.fill").font(.system(size: 11)).foregroundStyle(T.ink2).frame(width: 28, height: 28) }.buttonStyle(.plain)
                    Button { radio.toggle() } label: {
                        Image(systemName: radio.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(T.accentInk)
                            .frame(width: 34, height: 34).background(T.accent, in: Circle())
                    }.buttonStyle(.plain).help(radio.isPlaying ? "Durdur" : "Canlı yayını başlat")
                    Button { radio.step(1, in: store.radio.stations) } label: { Image(systemName: "forward.fill").font(.system(size: 11)).foregroundStyle(T.ink2).frame(width: 28, height: 28) }.buttonStyle(.plain)
                    Button { radio.stop() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.ink3).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help("Radyoyu kapat")
                }
                SleepTimerMenu()
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(T.ink3)
                    Slider(value: $radio.volume, in: 0...1).tint(T.accent).frame(width: 96).controlSize(.small)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(T.paper2)
            .overlay(alignment: .top) { Rule() }
        }
    }

    private func statusLine(_ r: RadioStore, _ s: Station) -> String {
        switch r.state {
        case .loading: return "Bağlanıyor…"
        case .stopped: return "Durduruldu · ▶ ile canlı yayına dön"
        case .failed(let m): return m
        default: return r.nowPlaying ?? "Canlı yayın · \(s.category)"
        }
    }
}
