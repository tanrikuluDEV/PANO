import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    static let sidebarWide: CGFloat = 232, sidebarNarrow: CGFloat = 72
    /// Live width while the sidebar edge is being dragged; nil otherwise.
    @State private var dragWidth: CGFloat?
    @State private var dragStart: CGFloat?

    private var sidebarWidth: CGFloat {
        dragWidth ?? (store.prefs.sidebarCollapsed ? Self.sidebarNarrow : Self.sidebarWide)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(compact: sidebarWidth < 150)
                .frame(width: sidebarWidth)
                .overlay(alignment: .trailing) { resizeHandle }
                .zIndex(1)
            VStack(spacing: 0) {
                if store.isOffline {
                    OfflineBanner(lastSync: store.lastSync).padding(.horizontal, 20).padding(.top, 34)
                }
                Group {
                    switch store.screen {
                    case .bugun: BugunView()
                    case .haberler: HaberlerView()
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
                    case .ayarlar: AyarlarView()
                    }
                }
                // Canlı TV / IPTV keep playing in a corner while another tab is open
                .overlay {
                    let tv = store.tv
                    if !store.screen.isTV, tv.current != nil, tv.state != .idle {
                        MiniTVPlayer().transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: store.screen.isTV)
                .animation(.easeOut(duration: 0.2), value: store.tv.state == .idle)
                NowPlayingBar()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackdrop())
        .overlay(alignment: .topTrailing) { AppearanceSwitch().padding(.top, 7).padding(.trailing, 16) }
        // while the in-app browser is open the app behind it stops taking clicks; WebOverlay frosts it over
        .allowsHitTesting(store.webURL == nil)
        .overlay {
            if let url = store.webURL { WebOverlay(url: url) }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .preferredColorScheme(store.colorScheme)
        .ignoresSafeArea()
        .onAppear {
            store.openSettingsAction = { store.screen = .ayarlar }
            store.openMainAction = { openWindow(id: "main") }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.prefs.sidebarCollapsed)
        // Most screens never read store.prefs, so a colour-theme change wouldn't otherwise
        // reach their already-rendered accent colours — force the whole window to redraw.
        .id(store.lookID)
    }
}

extension RootView {
    /// Invisible strip over the sidebar's right edge: drag to resize, and it snaps to icons-only or full width
    /// on release (a quick flick counts too). Double-click toggles.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .offset(x: 4)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { v in
                        let start = dragStart ?? sidebarWidth
                        dragStart = start
                        dragWidth = min(max(start + v.translation.width, Self.sidebarNarrow), Self.sidebarWide)
                    }
                    .onEnded { v in
                        let start = dragStart ?? sidebarWidth
                        let projected = start + v.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            store.prefs.sidebarCollapsed = projected < (Self.sidebarWide + Self.sidebarNarrow) / 2
                            dragWidth = nil
                        }
                        dragStart = nil
                    }
            )
            .onTapGesture(count: 2) { store.prefs.sidebarCollapsed.toggle() }
            .help("Sürükleyerek daralt / genişlet")
    }
}

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    /// Icons only: logo mark without the wordmark, row labels become tooltips, badges become dots.
    var compact = false

    private func badge(_ s: Screen) -> String {
        switch s {
        case .haberler: let n = store.unreadNewsCount; return n > 0 ? "\(n) yeni" : ""
        case .arsiv: return store.bookmarks.isEmpty ? "" : "\(store.bookmarks.count)"
        case .futbol: return store.liveMatches.isEmpty ? "" : "\(store.liveMatches.count)"
        case .radyo: return store.radio.state == .playing ? "♪" : ""
        default: return ""
        }
    }

    @State private var dragging: Screen?
    @State private var hovered: Screen?
    @Namespace private var hoverNS

    private func navRow(_ s: Screen) -> some View {
        let sel = store.screen == s
        let hot = hovered == s
        let b = badge(s)
        return HStack(spacing: 10) {
            Image(systemName: s.symbol).font(.system(size: compact ? 15 : 13, weight: sel ? .semibold : .regular)).frame(width: 18)
                .scaleEffect(hot ? 1.12 : 1).offset(x: hot && !compact ? 1.5 : 0)
                .overlay(alignment: .topTrailing) {
                    if compact && !b.isEmpty { Circle().fill(T.accent).frame(width: 6, height: 6).offset(x: 5, y: -3) }
                }
            if !compact {
                Text(s.rawValue).font(.ui(13.5, sel ? .semibold : .regular)).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                Text(b).font(.mono(10)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .foregroundStyle(sel ? T.accent : hot ? T.ink : T.ink2)
        .padding(.horizontal, compact ? 0 : 10).padding(.vertical, compact ? 9 : 7)
        .help(compact ? (b.isEmpty ? s.rawValue : "\(s.rawValue) · \(b)") : "")
        .background(sel ? T.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        .background {
            // One frame shared by every row: it fades in on the first hovered row, then glides
            // from row to row as the pointer moves (matchedGeometryEffect), and fades out on exit.
            if hot {
                RoundedRectangle(cornerRadius: 7)
                    .fill(T.paper2.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.accent.opacity(0.55), lineWidth: 1))
                    .shadow(color: T.accent.opacity(0.18), radius: 4, y: 1)
                    .matchedGeometryEffect(id: "hoverFrame", in: hoverNS)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                if inside { hovered = s } else if hovered == s { hovered = nil }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if compact {
                    PanoMark(size: 36).frame(maxWidth: .infinity).padding(.bottom, 5.5)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 10) {
                            PanoMark(size: 36)
                            PanoWordmark(size: 28).fixedSize()
                        }
                        Text("DEFTER VE GAZETE").font(.mono(8.5)).tracking(1.4).foregroundStyle(T.ink3).fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.init(top: 44, leading: compact ? 0 : 18, bottom: 14, trailing: compact ? 0 : 18))

            Rule().padding(.horizontal, 12)

            VStack(spacing: 2) {
                ForEach(store.orderedScreens) { s in
                    navRow(s)
                        .opacity(dragging == s ? 0.35 : 1)
                        .onTapGesture { store.screen = s }
                        .onDrag {
                            dragging = s; hovered = nil
                            return NSItemProvider(object: s.rawValue as NSString)
                        }
                        .onDrop(of: [.text], delegate: ScreenDropDelegate(item: s, dragging: $dragging, store: store))
                }
            }.padding(.horizontal, compact ? 8 : 10).padding(.top, 12).padding(.bottom, 6)

            Rule(color: T.rule2).padding(.horizontal, 12)

            navRow(.ayarlar)
                .onTapGesture { store.screen = .ayarlar }
                .padding(.horizontal, compact ? 8 : 10).padding(.top, 6)

            Spacer()

            if compact {
                VStack(spacing: 10) {
                    Circle().fill(store.isOffline ? T.ink3 : T.up).frame(width: 6, height: 6)
                        .help("Son güncelleme: \(store.lastSync.map(Day.hm) ?? "—")")
                    Button { Task { await store.refresh() } } label: {
                        Text("↻").font(.ui(14))
                            .frame(width: 34, height: 30)
                            .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                    }.buttonStyle(.plain).help("Yenile")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rule() }
            } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(store.isOffline ? T.ink3 : T.up).frame(width: 5, height: 5)
                    Text("Son güncelleme: \(store.lastSync.map(Day.hm) ?? "—")").font(.mono(11, .regular)).foregroundStyle(T.ink2).lineLimit(1)
                    Spacer()
                }
                Button { Task { await store.refresh() } } label: {
                    HStack(spacing: 7) {
                        Text("↻").font(.ui(13)); Text("Yenile").font(.ui(12, .medium))
                    }
                    .frame(maxWidth: .infinity).padding(7)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(14)
            .overlay(alignment: .top) { Rule() }
            }
        }
        .clipped()
        .panelBackground()
        .overlay(alignment: .trailing) { VRule() }
    }
}

/// Reorders `orderedScreens` live as a sidebar row is dragged over another — the standard
/// SwiftUI drag-to-reorder recipe, since the sidebar is a plain VStack rather than a List.
struct ScreenDropDelegate: DropDelegate {
    let item: Screen
    @Binding var dragging: Screen?
    let store: AppStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item else { return }
        var order = store.orderedScreens
        guard let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: item), from != to else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        store.setNavOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
