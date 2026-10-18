import SwiftUI
import WebKit

/// In-app browser for "Kaynakta aç": a centred glass panel over the main window while everything behind it
/// blurs. Back / forward / reload, the page title and host, a load bar, and a way out to the real browser.
/// Esc, the ✕ button or a click on the blurred background closes it.
struct WebOverlay: View {
    @Environment(AppStore.self) private var store
    let url: URL
    @State private var page = WebPage()

    var body: some View {
        GeometryReader { g in
            ZStack {
                // haze over the whole app: a material blurs everything behind it, AppKit-backed views included
                // (a SwiftUI .blur would skip the backdrop and the notebook's text view); click it to close
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.12)
                }
                .contentShape(Rectangle())
                .onTapGesture { store.closeWeb() }
                .transition(.opacity)

                panel
                    .frame(width: isPhone ? g.size.width : min(g.size.width - 80, 1180), height: isPhone ? g.size.height : g.size.height - 72)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .onAppear { page.load(url) }
        .onChange(of: url) { page.load(url) }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .top) {
                WebView(page: page)
                if page.progress < 1 {
                    GeometryReader { g in
                        Rectangle().fill(T.accent).frame(width: g.size.width * max(page.progress, 0.05), height: 2)
                            .animation(.easeOut(duration: 0.2), value: page.progress)
                    }.frame(height: 2)
                }
            }
        }
        .background { shape.fill(.regularMaterial) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(T.glass ? AnyShapeStyle(T.glassEdge) : AnyShapeStyle(T.rule), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolButton("chevron.left", "Geri", enabled: page.canGoBack) { page.view.goBack() }
            toolButton("chevron.right", "İleri", enabled: page.canGoForward) { page.view.goForward() }
            toolButton(page.progress < 1 ? "xmark" : "arrow.clockwise", page.progress < 1 ? "Durdur" : "Yenile") {
                if page.progress < 1 { page.view.stopLoading() } else { page.view.reload() }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? "Yükleniyor…" : page.title).font(.ui(12.5, .semibold)).foregroundStyle(T.ink).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: page.isSecure ? "lock.fill" : "globe").font(.system(size: 8.5))
                    Text(page.host).font(.mono(10, .regular)).lineLimit(1)
                }.foregroundStyle(T.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            Button { NSWorkspace.shared.open(page.currentURL ?? url) } label: {
                Text("Tarayıcıda aç ↗").font(.ui(12, .medium)).foregroundStyle(T.ink)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(T.paper2, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.rule, lineWidth: 1))
            }.buttonStyle(.plain).help("Varsayılan tarayıcıda aç")
            Button { store.closeWeb() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(T.ink2)
                    .frame(width: 28, height: 28).background(T.paper3, in: Circle())
            }
            .buttonStyle(.plain).help("Kapat (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func toolButton(_ symbol: String, _ help: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? T.ink2 : T.ink3.opacity(0.5))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).help(help)
    }
}

/// Owns the WKWebView and mirrors its state (title, URL, progress, history) for SwiftUI.
@MainActor @Observable
final class WebPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    @ObservationIgnored let view: WKWebView
    var title = ""
    var currentURL: URL?
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    var host: String { currentURL?.host() ?? "" }
    var isSecure: Bool { currentURL?.scheme == "https" }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // cookies persist, so a site's consent banner shows only once
        // identify as the Safari engine it is; some sites treat a bare WebKit user agent as a less capable browser
        cfg.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        view = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        #if os(macOS)
        view.allowsMagnification = true
        #endif
        observations = [
            view.observe(\.title) { [weak self] v, _ in Task { @MainActor in self?.title = v.title ?? "" } },
            view.observe(\.url) { [weak self] v, _ in Task { @MainActor in self?.currentURL = v.url } },
            view.observe(\.estimatedProgress) { [weak self] v, _ in Task { @MainActor in self?.progress = v.estimatedProgress } },
            view.observe(\.canGoBack) { [weak self] v, _ in Task { @MainActor in self?.canGoBack = v.canGoBack } },
            view.observe(\.canGoForward) { [weak self] v, _ in Task { @MainActor in self?.canGoForward = v.canGoForward } },
        ]
    }

    func load(_ url: URL) {
        currentURL = url; title = ""; progress = 0
        view.load(URLRequest(url: url))
    }

    /// Links that want a new window (target="_blank") open in this same panel instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    /// Non-web links (mailto:, app store, tel:) go to the system.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let u = navigationAction.request.url, let scheme = u.scheme?.lowercased() else { return .allow }
        if ["http", "https", "about", "data", "blob"].contains(scheme) { return .allow }
        NSWorkspace.shared.open(u)
        return .cancel
    }
}

#if os(macOS)
struct WebView: NSViewRepresentable {
    let page: WebPage
    /// SwiftUI's clipShape doesn't reach an AppKit view, so the panel's bottom corners are rounded on the layer.
    func makeNSView(context: Context) -> WKWebView {
        page.view.wantsLayer = true
        page.view.layer?.cornerRadius = 15
        page.view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return page.view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
