import Foundation

/// Folding the same story from several outlets into one row. Two headlines are the same story when they were
/// published within 36 hours of each other and share most of their significant words — compared on the first
/// five letters so Turkish suffixes don't hide a match ("İzmir'de depremi" / "İzmir depreminde"). Words are
/// weighted by rarity, so a shared name counts for more than a stock phrase ("burç yorumu", "asliye hukuk"), and
/// each story is compared with a group's first (newest) story only, so different stories can't chain together.
/// Two stories from the same outlet only fold when their headlines are identical.
enum StoryClusters {
    /// Story id → id of the newest story in its group, for every story that has at least one duplicate.
    static func build(_ news: [NewsItem]) -> [String: String] {
        let items = news.sorted { $0.date > $1.date }
        let sigs = items.map(signature)
        var df: [String: Int] = [:]
        for sig in sigs { for w in sig { df[w, default: 0] += 1 } }
        let total = Double(max(items.count, 1))
        func weight(_ w: String) -> Double { log(total / Double(df[w] ?? 1)) }
        let mass = sigs.map { $0.reduce(0) { $0 + weight($1) } }

        var clusterOf: [Int] = Array(0..<items.count)   // index → index of the group's newest story
        var index: [String: [Int]] = [:]                 // word → groups' first stories using it
        for (i, sig) in sigs.enumerated() where sig.count >= 3 {
            var shared: [Int: Set<String>] = [:]
            for w in sig { for j in index[w] ?? [] { shared[j, default: []].insert(w) } }
            var best: (j: Int, score: Double)?
            for (j, ws) in shared where ws.count >= 3 {
                guard items[j].date.timeIntervalSince(items[i].date) <= 36 * 3600 else { continue }
                // one outlet doesn't rewrite its own story; same-source matches are series (burç yorumları, ilanlar)
                if items[j].sourceID == items[i].sourceID, items[j].title != items[i].title { continue }
                let common = ws.reduce(0) { $0 + weight($1) }
                let overlap = common / min(mass[i], mass[j])
                let jaccard = common / (mass[i] + mass[j] - common)
                guard overlap >= 0.6, jaccard >= 0.34 else { continue }
                if overlap > best?.score ?? 0 { best = (j, overlap) }
            }
            if let b = best { clusterOf[i] = b.j } else { for w in sig { index[w, default: []].append(i) } }
        }
        var size: [Int: Int] = [:]
        for c in clusterOf { size[c, default: 0] += 1 }
        var out: [String: String] = [:]
        for (i, c) in clusterOf.enumerated() where size[c, default: 0] > 1 { out[items[i].id] = items[c].id }
        return out
    }

    private static let tr = Locale(identifier: "tr_TR")

    /// Significant words of a headline, cut to five letters.
    static func signature(_ n: NewsItem) -> Set<String> {
        let words = n.title.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .compactMap { $0.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map { String($0).lowercased(with: tr) } }
        return Set(words.filter { $0.count >= 3 && !WeeklyDigest.stopwords.contains($0) }.map { String($0.prefix(5)) })
    }
}
