import SwiftUI

/// iPhone shell: every screen of the Mac sidebar in a side menu. ☰ slides the current screen aside as a rounded card
/// (scaled, turned slightly, with a faded card behind it) and shows the menu on a dark, theme-tinted ground.
/// Tapping or swiping the card closes it. The screen shown is `store.screen`, so the shared cards' links still work.
struct MobileRoot: View {
    @Environment(AppStore.self) private var store
    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var editingOrder = false

    private let menuWidth: CGFloat = 265

    var body: some View {
        GeometryReader { g in
            // 0 closed … 1 open, following the finger while the card is dragged
            let p = max(0, min(1, (open ? 1 : 0) + drag / menuWidth))
            let full = CGSize(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                MenuBackground().ignoresSafeArea()
                SideMenu(editingOrder: $editingOrder)
                    .frame(width: menuWidth, height: g.size.height)
                    .opacity(p)
                    .offset(x: -40 * (1 - p))

                // the faded card behind the screen
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .frame(width: full.width, height: full.height)
                    .scaleEffect(1 - 0.26 * p)
                    .offset(x: (menuWidth - 42) * p)
                    .rotation3DEffect(.degrees(-10 * p), axis: (0, 1, 0), perspective: 0.6)
                    .opacity(p)
                    .ignoresSafeArea()

                content
                    .frame(width: full.width, height: full.height)
                    .clipShape(RoundedRectangle(cornerRadius: 34 * p, style: .continuous))
                    .overlay {
                        // while open the card is one big "close" target
                        if open { Color.black.opacity(0.001).onTapGesture { close() } }
                    }
                    .shadow(color: .black.opacity(0.35 * p), radius: 30, x: -8)
                    .scaleEffect(1 - 0.18 * p)
                    .offset(x: menuWidth * p)
                    .rotation3DEffect(.degrees(-10 * p), axis: (0, 1, 0), perspective: 0.6)
                    .ignoresSafeArea()
                    .gesture(open ? closeDrag : nil)
            }
        }
        .statusBarHidden(open)
        .overlay {
            if let url = store.webURL { WebOverlay(url: url).transition(.move(edge: .bottom)) }
        }
        .sheet(isPresented: $editingOrder) { OrderEditor().environment(store) }
        .sheet(isPresented: Binding(get: { store.briefToShow != nil }, set: { if !$0 { store.briefToShow = nil } })) {
            BriefView(kind: store.briefToShow ?? "evening").environment(store)
        }
        .preferredColorScheme(store.colorScheme)
        .id(store.lookID)
        // switching screens leaves any open story behind
        .onChange(of: store.navRequest) { close(); store.phoneStory = nil }
        .onAppear {
            // `-menuOpen YES` (command line only): screenshot of the open menu
            if UserDefaults.standard.bool(forKey: "menuOpen") { open = true }
        }
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in drag = min(0, v.translation.width) }
            .onEnded { v in
                if v.predictedEndTranslation.width < -menuWidth / 3 { close() }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 } }
            }
    }

    private func close() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { open = false; drag = 0 }
    }

    /// The current screen in its own navigation stack (stories and details open as pages), the ☰ bar on top,
    /// the radio mini player at the bottom and the TV mini player in a corner.
    private var content: some View {
        NavigationStack {
            MobileScreen(screen: store.screen)
                .id(store.screen)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 4) {
                        MenuBar { withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { open = true } }
                        if store.isOffline { OfflineBanner(lastSync: store.lastSync).padding(.horizontal, 16) }
                    }
                }
                .background(AppBackdrop().ignoresSafeArea())
                .navigationDestination(item: Binding(get: { store.briefToShow == nil ? store.phoneStory : nil },
                                                     set: { store.phoneStory = $0 })) { NewsDetail(item: $0) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MiniRadioBar() }
        .overlay {
            let tv = store.tv
            if !store.screen.isTV, tv.current != nil, tv.state != .idle {
                MiniTVPlayer().transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .background(AppBackdrop())
    }
}

/// ☰ and, off Anasayfa, a home button on the left; live matches (if any) on the right.
private struct MenuBar: View {
    @Environment(AppStore.self) private var store
    var openMenu: () -> Void

    var body: some View {
        HStack {
            Button(action: openMenu) { circle("line.3.horizontal") }.buttonStyle(.plain)
                .accessibilityLabel("Menü")
            // everywhere but Anasayfa: straight back to it
            if store.screen != .bugun {
                Button { store.screen = .bugun } label: { circle("house.fill") }.buttonStyle(.plain)
                    .accessibilityLabel("Anasayfa")
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if !store.liveMatches.isEmpty, store.screen != .futbol {
                Button { store.openFootball(liveOnly: true) } label: {
                    HStack(spacing: 7) {
                        PulseDot(color: T.down, pulsing: true)
                        Text("\(store.liveMatches.count) CANLI").font(.mono(11))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 2)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(T.ink)
            .frame(width: 42, height: 42)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().stroke(T.rule, lineWidth: 1))
    }
}

/// Dark ground behind the menu, tinted with the colour theme's hue.
private struct MenuBackground: View {
    var body: some View {
        let h = ColorTheme.current.hue
        ZStack {
            LinearGradient(colors: [Color(uiColor: oklch(0.30, 0.07, h)), Color(uiColor: oklch(0.15, 0.04, h + 30))],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(uiColor: oklch(0.55, 0.14, h, 0.35)), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
        }
    }
}

/// Logo, every screen in the sidebar order with the Mac's badges, then Ayarlar and "Sırayı düzenle".
private struct SideMenu: View {
    @Environment(AppStore.self) private var store
    @Binding var editingOrder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("P.").font(.system(size: 22, weight: .bold)).foregroundStyle(Color(uiColor: oklch(0.42, 0.11, 262)))
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: oklch(0.97, 0.015, 85)), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PANO").font(.system(size: 19, weight: .bold)).tracking(1.2)
                    Text(Day.long(Date())).font(.ui(12)).opacity(0.65)
                }
            }
            .padding(.leading, 24).padding(.top, 14).padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.orderedScreens) { s in item(s) }
                }
                .padding(.horizontal, 12)
            }

            Rectangle().fill(.white.opacity(0.14)).frame(height: 1).padding(.horizontal, 24).padding(.vertical, 8)
            item(.ayarlar).padding(.horizontal, 12)
            Button { editingOrder = true } label: {
                Label("Sırayı düzenle", systemImage: "arrow.up.arrow.down").font(.ui(13)).opacity(0.7)
                    .padding(.horizontal, 24).padding(.vertical, 10)
            }.buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .foregroundStyle(.white)
    }

    private func item(_ s: Screen) -> some View {
        let sel = store.screen == s
        let b = badge(s)
        return Button { store.screen = s } label: {
            HStack(spacing: 14) {
                Image(systemName: s.symbol).font(.system(size: 16, weight: .medium)).frame(width: 24)
                Text(s.title).font(.ui(15.5, sel ? .semibold : .regular))
                Spacer(minLength: 4)
                if !b.isEmpty {
                    Text(b).font(.mono(10.5, .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(s == .futbol ? AnyShapeStyle(T.down) : AnyShapeStyle(.white.opacity(0.18)), in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(sel ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(sel ? 1 : 0.82)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    /// Same counts as the Mac sidebar.
    private func badge(_ s: Screen) -> String {
        switch s {
        case .haberler: let n = store.unreadNewsCount; return n > 0 ? "\(n)" : ""
        case .arsiv: return store.bookmarks.isEmpty ? "" : "\(store.bookmarks.count)"
        case .futbol: return store.liveMatches.isEmpty ? "" : "\(store.liveMatches.count) canlı"
        default: return ""
        }
    }
}

/// Drag to reorder the menu (the same setting as the Mac sidebar's order).
private struct OrderEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.orderedScreens) { s in Label(s.title, systemImage: s.symbol) }
                        .onMove { from, to in
                            var order = store.orderedScreens
                            order.move(fromOffsets: from, toOffset: to)
                            store.setNavOrder(order)
                        }
                } footer: {
                    Text("Tutamaçtan sürükleyerek menünün sırasını değiştir.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Menü sırası")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Bitti") { dismiss() } }
        }
    }
}

/// The phone version of each screen.
struct MobileScreen: View {
    let screen: Screen
    var body: some View {
        switch screen {
        case .bugun: MobileBugun()
        case .haberler: MobileHaberler()
        case .yerel: YerelView()
        case .ekonomi: EkonomiView()
        case .futbol: FutbolView()
        case .spor: SporView()
        case .teknoloji: TeknolojiView()
        case .radyo: RadyoView()
        case .canliTV: CanliTVView()
        case .iptv: IPTVView()
        case .hava: HavaDurumuView()
        case .yol: YolDurumuView()
        case .deprem: DepremView()
        case .defter: DefterView()
        case .arsiv: ArsivView()
        case .ayarlar: MobileAyarlar()
        }
    }
}

/// Radio controls at the bottom while a station is selected: cover or logo, song, stop/play, next, close.
struct MiniRadioBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let radio = store.radio
        if let s = radio.current, radio.state != .idle {
            let song = radio.state == .playing ? radio.currentSong : nil
            HStack(spacing: 12) {
                if let song { SongArtwork(url: song.artwork, size: 40) } else { StationLogo(station: s, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.ui(13.5, .semibold)).lineLimit(1)
                    Text(subtitle(radio, s, song)).font(.ui(12)).foregroundStyle(T.ink3).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let song { AppleMusicButton(song: song, compact: true) }
                Button { radio.toggle() } label: {
                    Image(systemName: radio.isPlaying ? "stop.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(T.accentInk).frame(width: 38, height: 38).background(T.accent, in: Circle())
                }.buttonStyle(.plain)
                Button { radio.step(1, in: radio.stations) } label: {
                    Image(systemName: "forward.fill").font(.system(size: 14)).foregroundStyle(T.ink2).frame(width: 30, height: 38)
                }.buttonStyle(.plain)
                Button { radio.stop() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink3).frame(width: 26, height: 38)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T.rule, lineWidth: 1))
            .padding(.horizontal, 10).padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func subtitle(_ r: RadioStore, _ s: Station, _ song: PlayedSong?) -> String {
        if let song, let t = song.track { return [song.artist, t].compactMap { $0 }.joined(separator: " – ") }
        switch r.state {
        case .loading: return "Bağlanıyor…"
        case .stopped: return "Durduruldu"
        case .failed(let m): return m
        default: return r.nowPlaying ?? "Canlı yayın"
        }
    }
}
