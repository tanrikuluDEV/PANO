import SwiftUI
import AVKit

/// Canlı TV: the player on the left, the channel list on the right (category menu, search, favourites).
/// Leaving the tab keeps the stream going in MiniTVPlayer; starting a channel stops the radio, and vice versa.
struct CanliTVView: View {
    @Environment(AppStore.self) private var store
    @State private var category = "Tümü"
    @State private var query = ""

    private var tv: TVStore { store.tv }

    private var channels: [TVChannel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return tv.channels.filter { c in
            if !q.isEmpty { return c.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) != nil }
            switch category {
            case "Tümü": return true
            case "Favoriler": return tv.isFavorite(c)
            case "Ulusal": return c.rank != nil
            default: return c.category == category
            }
        }
    }

    var body: some View {
        let list = channels
        VStack(spacing: 0) {
            HStack {
                Text("Canlı TV").font(.serif(25)).tracking(-0.4)
                Spacer()
                Text("\(tv.channels.count) kanal").font(.mono(11, .regular)).foregroundStyle(T.ink3)
            }
            .padding(.init(top: 34, leading: 24, bottom: 14, trailing: 24))
            .overlay(alignment: .bottom) { Rule() }

            HStack(spacing: 0) {
                TVPlayerPane().frame(maxWidth: .infinity, maxHeight: .infinity)
                channelColumn(list).frame(width: 320).overlay(alignment: .leading) { VRule() }
            }
        }
        .task { await tv.loadIfNeeded() }
        .onAppear { DispatchQueue.main.async { tv.ensurePlaying() } }
    }

    // MARK: Channel list

    private func channelColumn(_ list: [TVChannel]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(tvCategories, id: \.self) { c in Button(c) { query = ""; category = c } }
                } label: {
                    Text("\(category) ▾").font(.ui(12, .medium)).foregroundStyle(T.ink2).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }.menuStyle(.button).buttonStyle(.plain).fixedSize()
                ChannelSearchField(query: $query)
            }
            .padding(12)
            .overlay(alignment: .bottom) { Rule() }

            if case .failed(let m) = tv.loadState, tv.channels.isEmpty {
                ErrorCard(eyebrow: "HATA · CANLI TV", message: m) { Task { await tv.loadIfNeeded() } }.padding(16)
                Spacer()
            } else if tv.channels.isEmpty {
                SkeletonCard(title: "YÜKLENİYOR · KANALLAR").padding(16)
                Spacer()
            } else if list.isEmpty {
                EmptyBox(title: category == "Favoriler" ? "Henüz favori kanal yok" : "Kanal bulunamadı",
                         subtitle: category == "Favoriler" ? "İzlerken ♡'ye basarak ekle" : "Başka bir kategori ya da arama dene").padding(16)
                Spacer()
            } else {
                ChannelList(channels: list)
            }
        }
    }
}

/// The player shared by Canlı TV and IPTV: video on top, then the channel's name, live badge and controls.
/// Both tabs drive the same TVStore, so the mini player, the sleep timer and the radio hand-off work the same.
struct TVPlayerPane: View {
    @Environment(AppStore.self) private var store
    private var tv: TVStore { store.tv }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                if tv.current != nil {
                    TVPlayerView(player: tv.player)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                overlay
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)

            if let c = tv.current {
                HStack(spacing: 12) {
                    ChannelLogo(channel: c, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(c.name).font(.serif(20)).tracking(-0.2)
                            if tv.state == .playing { LiveBadge() }
                        }
                        Text(caption(c)).font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                    }
                    Spacer()
                    SleepTimerMenu()
                    Button { tv.toggleFavorite(c) } label: {
                        Text(tv.isFavorite(c) ? "♥" : "♡").font(.ui(18)).foregroundStyle(tv.isFavorite(c) ? T.down : T.ink3)
                    }.buttonStyle(.plain).help(tv.isFavorite(c) ? "Favorilerden çıkar" : "Favorilere ekle")
                    Button { if tv.state == .idle || isFailed { tv.play(c) } else { tv.stop() } } label: {
                        Image(systemName: tv.state == .idle || isFailed ? "play.fill" : "stop.fill")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(T.accentInk)
                            .frame(width: 34, height: 34).background(T.accent, in: Circle())
                    }.buttonStyle(.plain).help(tv.state == .idle ? "Canlı yayını başlat" : "Durdur")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var isFailed: Bool { if case .failed = tv.state { return true } else { return false } }

    @ViewBuilder private var overlay: some View {
        switch tv.state {
        case .loading:
            ProgressView().controlSize(.large).tint(.white)
        case .failed(let m):
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                Text(m).font(.ui(13)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                if let c = tv.current { Button("Tekrar dene") { tv.play(c) }.buttonStyle(.plain).font(.ui(12, .medium)).foregroundStyle(.white).underline() }
            }.padding(24)
        case .idle where tv.current == nil:
            VStack(spacing: 8) {
                Image(systemName: "tv").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
                Text("Sağdaki listeden bir kanal seç").font(.ui(13)).foregroundStyle(.white.opacity(0.75))
            }
        case .idle:
            Image(systemName: "play.circle.fill").font(.system(size: 52)).foregroundStyle(.white.opacity(0.85))
                .onTapGesture { if let c = tv.current { tv.play(c) } }
        case .playing:
            EmptyView()
        }
    }

    private func caption(_ c: TVChannel) -> String {
        var parts = [c.category]
        if c.geoBlocked { parts.append("bölge kısıtlı") }
        if c.partTime { parts.append("7/24 değil") }
        return parts.joined(separator: " · ")
    }
}

/// "⌕ Kanal ara" box used by both TV tabs.
struct ChannelSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 6) {
            Text("⌕").font(.ui(13)).foregroundStyle(T.ink3)
            TextField("Kanal ara", text: $query).textFieldStyle(.plain).font(.ui(12.5))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(T.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
    }
}

/// Scrolling channel list used by both TV tabs.
struct ChannelList: View {
    let channels: [TVChannel]
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(channels) { c in ChannelRow(channel: c) }
            }
        }
    }
}

private struct ChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: TVChannel
    @State private var hover = false
    var body: some View {
        let tv = store.tv
        let isCurrent = tv.current?.id == channel.id
        let dead = tv.failed.contains(channel.id)
        Button { tv.play(channel) } label: {
            HStack(spacing: 10) {
                ChannelLogo(channel: channel, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name).font(.ui(13, isCurrent ? .semibold : .regular)).foregroundStyle(isCurrent ? T.accent : T.ink).lineLimit(1)
                    Text(dead ? "yayın açılamadı" : channel.category).font(.mono(9.5, .regular)).foregroundStyle(dead ? T.down : T.ink3).lineLimit(1)
                }
                Spacer(minLength: 4)
                if tv.isFavorite(channel) { Text("♥").font(.ui(11)).foregroundStyle(T.down) }
                if isCurrent && tv.state == .playing { Equalizer(animating: true).frame(width: 14, height: 12) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isCurrent ? T.accentSoft : hover ? T.paper3 : .clear)
            .opacity(dead && !isCurrent ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button(tv.isFavorite(channel) ? "Favorilerden çıkar" : "Favorilere ekle") { tv.toggleFavorite(channel) }
        }
    }
}

struct ChannelLogo: View {
    let channel: TVChannel
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Color.white.opacity(0.92))
            if let s = channel.logo, let u = URL(string: s) {
                CachedImage(url: u) { initials }.padding(size * 0.12)
            } else { initials }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(T.rule, lineWidth: 1))
    }
    private var initials: some View {
        Text(String(channel.name.prefix(2)).uppercased()).font(.mono(size * 0.32, .bold)).foregroundStyle(Color.black.opacity(0.6))
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            PulseDot(color: .white, pulsing: true)
            Text("CANLI").font(.mono(9, .bold)).tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(T.down, in: Capsule())
    }
}

/// AppKit's player view: native controls, full screen and picture-in-picture.
struct TVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        v.allowsPictureInPicturePlayback = true
        v.videoGravity = .resizeAspect
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.masksToBounds = true
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { if v.player !== player { v.player = player } }
}
