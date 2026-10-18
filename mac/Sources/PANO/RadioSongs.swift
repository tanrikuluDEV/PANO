import SwiftUI
import AppKit

/// A song heard on the radio: the station's ICY "StreamTitle", plus cover art and an Apple Music link
/// looked up on the iTunes Search API (free, no key). Kept in Radyo › Çalanlar.
struct PlayedSong: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    let text: String
    let station: String
    let date: Date
    var artist: String?
    var track: String?
    var artwork: URL?
    var link: URL?

    /// "Sanatçı – Şarkı" as matched on Apple Music, else what the station sent.
    var title: String { track ?? text }
    var subtitle: String? { artist }

    /// Apple Music's page for the song, or a search when no match was found; `music://` opens the Music app.
    var musicURL: URL? {
        if let link { return link }
        let q = text.replacingOccurrences(of: " - ", with: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/tr/search?term=\(q)")
    }
}

enum SongLookup {
    private struct Response: Decodable { let results: [Hit] }
    private struct Hit: Decodable { let artistName: String; let trackName: String; let artworkUrl100: String?; let trackViewUrl: String? }
    @MainActor private static var cache: [String: PlayedSong] = [:]

    /// Stations also send slogans, ads and their own name instead of a song; those aren't songs.
    static func isSong(_ text: String, station: String) -> Bool {
        let t = Provinces.fold(text)
        guard text.contains(" - ") || text.contains(" – "), t.count >= 5 else { return false }
        if ["radyo", "radio", " fm", "reklam", "jingle", "www.", "http", ".com", "canli yayin"].contains(where: t.contains) { return false }
        let name = Provinces.fold(station).filter(\.isLetter)
        return name.count < 4 || !t.filter(\.isLetter).contains(name)
    }

    /// Fills in artist, track, cover and link. Order in the stream title varies ("Sanatçı - Şarkı" or the
    /// reverse); the search takes both words together, and a hit only counts if its words appear in the text.
    @MainActor static func enrich(_ song: PlayedSong) async -> PlayedSong {
        if let c = cache[song.text] { return merged(song, c) }
        let term = song.text.replacingOccurrences(of: " - ", with: " ").replacingOccurrences(of: " – ", with: " ")
        var q = URLComponents(string: "https://itunes.apple.com/search")!
        q.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "song"), .init(name: "limit", value: "5"), .init(name: "country", value: "TR")]
        guard let url = q.url, let data = try? await fetch(url), let r = try? JSONDecoder().decode(Response.self, from: data) else { return song }
        let folded = Provinces.fold(song.text)
        func words(_ s: String) -> [String] { Provinces.fold(s).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 } }
        func fits(_ s: String) -> Bool { let w = words(s); return !w.isEmpty && w.filter { folded.contains($0) }.count * 2 >= w.count }
        guard let hit = r.results.first(where: { fits($0.trackName) && fits($0.artistName) }) else { return song }
        var out = song
        out.artist = hit.artistName; out.track = hit.trackName
        out.artwork = hit.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "300x300bb")) }
        out.link = hit.trackViewUrl.flatMap { URL(string: $0.components(separatedBy: "&uo=").first ?? $0) }
        cache[song.text] = out
        return out
    }

    private static func merged(_ s: PlayedSong, _ c: PlayedSong) -> PlayedSong {
        var o = s; o.artist = c.artist; o.track = c.track; o.artwork = c.artwork; o.link = c.link; return o
    }

    /// Opens the song in the Music app; falls back to the browser.
    static func open(_ song: PlayedSong) {
        guard let u = song.musicURL else { return }
        if u.host == "music.apple.com", let app = URL(string: "music://" + u.absoluteString.dropFirst("https://".count)),
           NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            NSWorkspace.shared.open(app)
        } else {
            NSWorkspace.shared.open(u)
        }
    }
}

// MARK: - Views

/// Square cover art, falling back to a note glyph.
struct SongArtwork: View {
    let url: URL?
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            T.paper3
            if let url {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.38)).foregroundStyle(T.ink3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
        .overlay(RoundedRectangle(cornerRadius: size * 0.16).stroke(T.rule2, lineWidth: 1))
    }
}

struct AppleMusicButton: View {
    let song: PlayedSong
    var compact = false
    var body: some View {
        Button { SongLookup.open(song) } label: {
            HStack(spacing: 4) {
                Image(systemName: "applelogo").font(.system(size: 10))
                if !compact { Text("Music").font(.ui(11.5, .medium)) }
            }
            .foregroundStyle(T.ink2)
            .padding(.horizontal, compact ? 7 : 9).padding(.vertical, 5)
            .background(T.paper3, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(song.link != nil ? "Apple Music'te aç" : "Apple Music'te ara")
    }
}

/// Radyo › Çalanlar: every song heard, newest first, split into days.
struct SongHistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        let songs = store.radio.songHistory
        if songs.isEmpty {
            EmptyBox(title: "Henüz şarkı yok", subtitle: "Radyo dinlerken istasyonun gönderdiği şarkılar burada birikir")
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(days(songs), id: \.key) { g in
                        Section {
                            ForEach(g.items) { SongRow(song: $0) }
                        } header: {
                            NewsDayHeader(date: g.date, count: g.items.count)
                        }
                    }
                    HStack {
                        Spacer()
                        Button(confirmClear ? "Emin misin? Tüm geçmiş silinir" : "Geçmişi temizle") {
                            if confirmClear { store.radio.clearSongHistory() }
                            confirmClear.toggle()
                        }
                        .font(.ui(11.5)).foregroundStyle(confirmClear ? T.down : T.ink3).buttonStyle(.plain)
                        Spacer()
                    }.padding(18)
                }
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
    }

    private func days(_ songs: [PlayedSong]) -> [(key: String, date: Date, items: [PlayedSong])] {
        var out: [(key: String, date: Date, items: [PlayedSong])] = []
        for s in songs {
            let k = Day.key(s.date)
            if out.last?.key == k { out[out.count - 1].items.append(s) } else { out.append((k, s.date, [s])) }
        }
        return out
    }
}

private struct SongRow: View {
    let song: PlayedSong
    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(url: song.artwork, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.ui(13.5, .semibold)).lineLimit(1)
                Text([song.subtitle, song.station].compactMap { $0 }.joined(separator: " · ")).font(.ui(12)).foregroundStyle(T.ink3).lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(Day.hm(song.date)).font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
            AppleMusicButton(song: song)
        }
        .padding(.horizontal, 24).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rule(color: T.rule2) }
        .contextMenu {
            Button("Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([song.artist, song.track].compactMap { $0 }.joined(separator: " – ").nonEmpty ?? song.text, forType: .string)
            }
            Button(song.link != nil ? "Apple Music'te aç" : "Apple Music'te ara") { SongLookup.open(song) }
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
