import Foundation

struct ArticleBlock: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let isHeading: Bool
}

/// Pulls the readable body out of a news page: JSON-LD `articleBody` when present,
/// otherwise the densest run of `<p>` elements. Whichever yields more text wins.
enum ArticleService {
    static func load(_ url: URL) async throws -> [ArticleBlock] { try await loadPage(url).blocks }

    /// The body and the page's own picture (og:image / twitter:image), if it names one.
    static func loadPage(_ url: URL) async throws -> (blocks: [ArticleBlock], image: URL?) {
        var req = URLRequest(url: url)
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.setValue("tr-TR,tr;q=0.9,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw ServiceError.http(h.statusCode) }
        let html = decode(data, response: resp)
        let blocks = extract(html)
        if blocks.isEmpty { throw ServiceError.empty }
        return (blocks, image(html, base: resp.url ?? url))
    }

    private static func image(_ html: String, base: URL) -> URL? {
        let head = String(html.prefix(200_000))
        for p in [#"<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)["'][^>]*content=["']([^"']+)"#,
                  #"<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["'](?:og:image|twitter:image)["']"#] {
            if let m = regex(p).firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
               let r = Range(m.range(at: 1), in: head),
               let u = URL(string: String(head[r]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
               u.scheme?.hasPrefix("http") == true { return u }
        }
        return nil
    }

    private static func decode(_ data: Data, response: URLResponse) -> String {
        if let name = response.textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId,
               let s = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return s }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1254) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Extraction

    static func extract(_ html: String) -> [ArticleBlock] {
        let ld = jsonLD(html)
        let cluster = paragraphCluster(html)
        let ldChars = ld.reduce(0) { $0 + $1.text.count }, clChars = cluster.reduce(0) { $0 + $1.text.count }
        if clChars >= Int(Double(ldChars) * 0.7), clChars > 0 { return cluster }
        return ld.isEmpty ? cluster : ld
    }

    private static func regex(_ p: String, _ opts: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }
    private static let ldScript = regex("<script[^>]*application/ld\\+json[^>]*>(.*?)</script>")
    private static let noise = regex("<(script|style|noscript|svg|nav|footer|aside|form|iframe|button)\\b.*?</\\1>|<!--.*?-->")
    private static let tags = regex("<(p|h2|h3|h4)\\b[^>]*>(.*?)</\\1>")
    private static let br = regex("<br\\s*/?>")
    private static let sentenceSplit = regex("(?<=[.!?…])\\s+(?=[A-ZÇĞİÖŞÜ0-9\"“‘'])", [])

    /// Dropped at any length (cookie banners, agency footers).
    private static let strongBoilerplate = ["çerez", "cookie", "kvkk", "gdpr", "tüm hakları", "bu haberde bir hata", "haber akış sistemi",
                                            "bültene", "abone ol", "kitap dünyasına açılan kapınızı"]
    private static let boilerplate = ["tüm hakları", "çerez", "abone ol", "bültene", "yorum yap", "haberi paylaş", "google news", "whatsapp",
                                      "takip edin", "reklam", "kaynak:", "facebook", "twitter", "instagram", "telegram", "©", "giriş yap", "üye ol"]

    private static func jsonLD(_ html: String) -> [ArticleBlock] {
        let ns = html as NSString
        var best = ""
        for m in ldScript.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let data = ns.substring(with: m.range(at: 1)).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let body = findBody(obj), body.count > best.count else { continue }
            best = body
        }
        guard !best.isEmpty else { return [] }
        var parts = best.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            .map { stripHTML($0) }.filter { t in !t.isEmpty && !strongBoilerplate.contains(where: { t.lowercased().contains($0) }) }
        if parts.count == 1, parts[0].count > 700 { parts = chunkSentences(parts[0]) }
        return parts.map { ArticleBlock(text: $0, isHeading: false) }
    }

    private static func findBody(_ o: Any) -> String? {
        if let d = o as? [String: Any] {
            if let b = d["articleBody"] as? String, !b.isEmpty { return b }
            for v in d.values { if let b = findBody(v) { return b } }
        } else if let a = o as? [Any] {
            for v in a { if let b = findBody(v) { return b } }
        }
        return nil
    }

    private static func chunkSentences(_ text: String) -> [String] {
        let ns = text as NSString
        var sentences: [String] = [], last = 0
        for m in sentenceSplit.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            sentences.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        sentences.append(ns.substring(from: last))
        return stride(from: 0, to: sentences.count, by: 3).map { sentences[$0..<min($0 + 3, sentences.count)].joined(separator: " ") }
    }

    private struct Piece { let loc: Int; let text: String; let heading: Bool }

    private static func paragraphCluster(_ html: String) -> [ArticleBlock] {
        var s = html as NSString
        s = noise.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: s.length), withTemplate: " ") as NSString
        let src = s as String
        var pieces: [Piece] = []
        for m in tags.matches(in: src, range: NSRange(location: 0, length: s.length)) {
            let tag = s.substring(with: m.range(at: 1)).lowercased()
            var inner = s.substring(with: m.range(at: 2))
            inner = br.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length), withTemplate: " ")
            let text = stripHTML(inner)
            let heading = tag != "p"
            if heading { if text.count >= 8, text.count <= 120 { pieces.append(Piece(loc: m.range.location, text: text, heading: true)) }; continue }
            guard text.count >= 35 else { continue }
            let low = text.lowercased()
            if strongBoilerplate.contains(where: { low.contains($0) }) { continue }
            if text.count < 200, boilerplate.contains(where: { low.contains($0) }) { continue }
            pieces.append(Piece(loc: m.range.location, text: text, heading: false))
        }
        // group paragraphs that sit close together; the biggest group is the article
        var groups: [[Piece]] = [], cur: [Piece] = []
        for p in pieces where !p.heading {
            if let l = cur.last, p.loc - l.loc > 4000 { groups.append(cur); cur = [] }
            cur.append(p)
        }
        if !cur.isEmpty { groups.append(cur) }
        guard let best = groups.max(by: { $0.reduce(0) { $0 + $1.text.count } < $1.reduce(0) { $0 + $1.text.count } }),
              let first = best.first?.loc, let last = best.last?.loc else { return [] }
        var seen = Set<String>()
        return pieces.filter { $0.loc >= first && $0.loc <= last && seen.insert($0.text).inserted }
            .map { ArticleBlock(text: $0.text, isHeading: $0.heading) }
    }
}
