import SwiftUI
import AppKit

/// Keyboard shortcuts. ⌘-combinations live in the menus (PANOApp); single keys are caught here, and only while no
/// text box is being typed into, the quick search and in-app browser are closed, and no other window is in front.
///
///   J / ↓   next story            K / ↑   previous story
///   B       add to / remove from Arşiv
///   O / ↩   open the story's page  P      radio play / pause
///   /       quick search           ?      this list
enum Shortcuts {
    /// Shown by "?" and Yardım › Klavye Kısayolları.
    static let list: [(keys: String, what: String)] = [
        ("⌘K  veya  /", "Hızlı arama"),
        ("⌘1 … ⌘9", "Kenar çubuğundaki ilk dokuz sekme"),
        ("⌘R", "Her şeyi yenile"),
        ("⌃⌘S", "Kenar çubuğunu daralt / genişlet"),
        ("J  veya  ↓", "Sonraki haber"),
        ("K  veya  ↑", "Önceki haber"),
        ("B", "Arşive ekle / çıkar"),
        ("O  veya  ↩", "Haberi kaynağında aç"),
        ("P", "Radyoyu çal / durdur"),
        ("?", "Bu liste"),
    ]

    /// Installed once by RootView; returns the monitor so it can be removed.
    @MainActor static func install(_ store: AppStore) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .control, .option])
            guard mods.isEmpty, !store.quickSearchOpen, store.webURL == nil, !store.shortcutsOpen || e.keyCode == 53,
                  let w = e.window, w.identifier?.rawValue.hasPrefix("main") == true || w.title == "PANO",
                  !(w.firstResponder is NSText) else { return e }
            return handle(e, store) ? nil : e
        }
    }

    @MainActor private static func handle(_ e: NSEvent, _ store: AppStore) -> Bool {
        if store.shortcutsOpen { store.shortcutsOpen = false; return true }   // Esc (or anything) closes the list
        switch (e.keyCode, e.charactersIgnoringModifiers?.lowercased() ?? "") {
        case (_, "j"), (125, _): return store.moveStory(1)
        case (_, "k"), (126, _): return store.moveStory(-1)
        case (_, "b"):
            guard let n = store.currentStory else { return false }
            store.toggleBookmark(n); return true
        case (_, "o"), (36, _), (76, _):
            guard let l = store.currentStory?.link else { return false }
            store.openWeb(GoogleNews.cached(l) ?? l); return true
        case (_, "p"):
            guard store.radio.current != nil else { return false }
            store.radio.toggle(); return true
        case (_, "/"):
            withAnimation(.easeOut(duration: 0.15)) { store.quickSearchOpen = true }; return true
        case (_, "?"):
            withAnimation(.easeOut(duration: 0.15)) { store.shortcutsOpen = true }; return true
        default: return false
        }
    }
}

extension AppStore {
    /// The story list on screen, one entry per row: stories folded under another outlet's row are skipped, as
    /// NewsDayList shows them.
    private var storyRows: (items: [NewsItem], selected: NewsItem?)? {
        func rows(_ items: [NewsItem], fold: Bool) -> [NewsItem] {
            guard fold, prefs.foldDuplicates else { return items }
            var seen = Set<String>()
            return items.filter { n in storyCluster[n.id].map { seen.insert($0).inserted } ?? true }
        }
        switch screen {
        case .haberler where newsMode == .list: return (rows(filteredNews, fold: true), selectedNews)
        case .spor: return (rows(filteredSpor, fold: true), selectedSpor)
        case .teknoloji: return (rows(filteredTeknoloji, fold: true), selectedTeknoloji)
        case .arsiv: return (filteredArsiv, selectedArsiv)
        case .yerel: return (yerel.filtered, yerel.selected)
        default: return nil
        }
    }

    /// The story open in the reading pane of the current screen.
    var currentStory: NewsItem? { storyRows?.selected }

    /// Selects the next (`by: 1`) or previous story of the current list; false when this screen has no story list.
    func moveStory(_ by: Int) -> Bool {
        guard let (items, sel) = storyRows, !items.isEmpty else { return false }
        // a story folded under another row counts as that row
        let at = sel.flatMap { s in items.firstIndex { $0.id == s.id || (storyCluster[$0.id] != nil && storyCluster[$0.id] == storyCluster[s.id]) } } ?? -1
        let n = items[min(max(at + by, 0), items.count - 1)]
        switch screen {
        case .haberler: selectedNewsID = n.id
        case .spor: selectedSporID = n.id
        case .teknoloji: selectedTeknolojiID = n.id
        case .arsiv: selectedArsivID = n.id
        case .yerel: yerel.selectedID = n.id
        default: break
        }
        return true
    }
}

/// "?" — the list of shortcuts over the window.
struct ShortcutsOverlay: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Klavye kısayolları").font(.serif(20)).tracking(-0.3)
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink3) }
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 14)
                ForEach(Shortcuts.list, id: \.keys) { s in
                    HStack {
                        Text(s.what).font(.ui(13)).foregroundStyle(T.ink)
                        Spacer(minLength: 24)
                        Text(s.keys).font(.mono(11.5)).foregroundStyle(T.ink2)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) { Rule(color: T.rule2) }
                }
                Text("Tek tuşlu kısayollar bir yazı kutusuna yazarken çalışmaz.")
                    .font(.ui(11.5)).foregroundStyle(T.ink3).padding(.top, 12)
            }
            .padding(22)
            .frame(width: 420)
            .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial) }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
        }
    }
    private func close() { withAnimation(.easeOut(duration: 0.15)) { store.shortcutsOpen = false } }
}
