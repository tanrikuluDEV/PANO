import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Search

extension AppStore {
    struct JournalHit: Identifiable {
        let day: String
        /// The first matching line: from the page, a to-do ("☐ …") or a tag ("#…").
        let line: String
        let count: Int
        var id: String { day }
    }

    /// Days whose page, tags or to-dos contain `query`, newest first.
    func journalSearch(_ query: String) -> [JournalHit] {
        let q = Search.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return [] }
        let days = Set(journal.keys).union(todos.map(\.day))
        return days.sorted(by: >).compactMap { day in
            var lines: [String] = []
            if let e = journal[day] {
                lines += e.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                lines += e.tags.map { "#" + $0 }
            }
            for t in todos(on: day) {
                lines.append((t.done ? "☑ " : "☐ ") + t.title)
                if let n = t.note { lines.append(n) }
            }
            let hits = lines.filter { Search.fold($0).contains(q) }
            return hits.first.map { JournalHit(day: day, line: $0, count: hits.count) }
        }
    }
}

// MARK: - Export

/// Defter pages as Markdown (to keep or paste anywhere) or PDF (to print or send).
enum DefterExport {
    /// Every day with something on it, oldest first.
    @MainActor static func allDays(_ store: AppStore) -> [String] {
        let written = store.journal.values.filter { !$0.text.isEmpty || !$0.tags.isEmpty }.map(\.day)
        return Set(written + store.todos.map(\.day)).sorted()
    }

    private enum Line { case title(String), day(String), meta(String), section(String), item(String, done: Bool), text(String) }

    @MainActor private static func lines(_ store: AppStore, days: [String]) -> [Line] {
        var out: [Line] = [.title("Defter"), .meta("PANO · \(Day.long(Date())) tarihinde dışa aktarıldı")]
        for day in days {
            let date = Day.date(day) ?? Date()
            out.append(.day(Day.format(date, "d MMMM yyyy EEEE")))
            let e = store.entry(day)
            if let tags = e?.tags, !tags.isEmpty { out.append(.meta(tags.map { "#" + $0 }.joined(separator: " "))) }
            let todos = store.todos(on: day)
            if !todos.isEmpty {
                out.append(.section("Yapılacaklar"))
                for t in todos {
                    var s = t.title
                    if let time = t.time { s = "\(time) · " + s }
                    if let n = t.note { s += " — " + n }
                    out.append(.item(s, done: t.done))
                }
            }
            if let text = e?.text, !text.isEmpty {
                if !todos.isEmpty { out.append(.section("Günlük")) }
                out.append(.text(text))
            }
        }
        return out
    }

    @MainActor static func markdown(_ store: AppStore, days: [String]) -> String {
        lines(store, days: days).map { l -> String in
            switch l {
            case .title(let s): return "# \(s)\n"
            case .day(let s): return "\n## \(s)\n"
            case .meta(let s): return "_\(s)_\n"
            case .section(let s): return "\n### \(s)\n"
            case .item(let s, let done): return "- [\(done ? "x" : " ")] \(s)"
            case .text(let s): return "\n" + s + "\n"
            }
        }.joined(separator: "\n") + "\n"
    }

    @MainActor static func html(_ store: AppStore, days: [String]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let body = lines(store, days: days).map { l -> String in
            switch l {
            case .title(let s): return "<h1>\(esc(s))</h1>"
            case .day(let s): return "<h2>\(esc(s))</h2>"
            case .meta(let s): return "<p class=meta>\(esc(s))</p>"
            case .section(let s): return "<h3>\(esc(s))</h3>"
            case .item(let s, let done): return "<p class=item>\(done ? "☑" : "☐")&nbsp; \(esc(s))</p>"
            case .text(let s): return s.components(separatedBy: "\n\n").map { "<p>\(esc($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }.joined()
            }
        }.joined(separator: "\n")
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: Georgia, serif; font-size: 12pt; line-height: 1.5; color: #222; }
        h1 { font-size: 24pt; margin: 0 0 2pt; }
        h2 { font-size: 15pt; margin: 22pt 0 2pt; border-bottom: 0.5pt solid #bbb; padding-bottom: 3pt; }
        h3 { font-family: Helvetica, sans-serif; font-size: 8.5pt; letter-spacing: 1pt; text-transform: uppercase; color: #777; margin: 10pt 0 3pt; }
        p { margin: 0 0 7pt; }
        p.meta { font-family: Helvetica, sans-serif; font-size: 9pt; color: #777; }
        p.item { margin: 0 0 3pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    static func fileName(_ days: [String], ext: String) -> String {
        days.count == 1 ? "Defter \(days[0]).\(ext)" : "Defter.\(ext)"
    }

    /// A4 pages with 2 cm margins.
    private static let page = CGSize(width: 595, height: 842), margin: CGFloat = 57

    #if os(macOS)
    /// Asks where to save, then writes the file.
    @MainActor static func save(_ store: AppStore, days: [String], pdf: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(days, ext: pdf ? "pdf" : "md")
        panel.allowedContentTypes = [pdf ? .pdf : UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if pdf { writePDF(html(store, days: days), to: url) }
        else { try? markdown(store, days: days).write(to: url, atomically: true, encoding: .utf8) }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor private static func writePDF(_ html: String, to url: URL) {
        guard let attr = NSAttributedString(html: Data(html.utf8), documentAttributes: nil) else { return }
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = page
        info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: page.width - 2 * margin, height: page.height - 2 * margin))
        view.textStorage?.setAttributedString(attr)
        view.isVerticallyResizable = true
        view.sizeToFit()
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false; op.showsProgressPanel = false
        op.run()
    }
    #else
    /// Writes the file to a temporary folder and opens the share sheet (Dosyalar'a kaydet, Notlar, Mail …).
    @MainActor static func share(_ store: AppStore, days: [String], pdf: Bool) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(days, ext: pdf ? "pdf" : "md"))
        if pdf { try? pdfData(html(store, days: days)).write(to: url) }
        else { try? markdown(store, days: days).write(to: url, atomically: true, encoding: .utf8) }
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    @MainActor private static func pdfData(_ html: String) -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: page)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: margin, dy: margin), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
    #endif
}
