import SwiftUI
import EventKit

/// Takvim: public holidays (Nager.Date — free, no key, includes the Ramazan and Kurban bayrams), the half days
/// before them, well-known days worked out locally (Anneler Günü, 10 Kasım …), long-weekend hints, and — if
/// switched on in Ayarlar — today's events from the Mac's Calendar app.
struct SpecialDay: Identifiable, Hashable {
    enum Kind { case tatil, yarimGun, onemli }
    let name: String
    let start: Date
    let end: Date
    let kind: Kind
    var tentative = false
    var id: String { "\(Day.key(start))|\(name)" }

    var dateText: String {
        Day.cal.isDate(start, inSameDayAs: end) ? Day.format(start, "d MMMM EEEE")
            : Day.format(start, "d") + "–" + Day.format(end, "d MMMM")
    }
}

/// A run of days off around a holiday, and the workdays to take off to get it.
struct LongWeekend: Identifiable, Hashable {
    let start: Date
    let end: Date
    let leave: [Date]
    let holiday: String
    var id: String { Day.key(start) }
    var days: Int { (Day.cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
    var text: String {
        let range = Day.format(start, "d MMMM EEEE") + " – " + Day.format(end, "d MMMM EEEE")
        if leave.isEmpty { return "\(days) gün tatil · \(range)" }
        let names = leave.map { Day.format($0, "EEEE") }.joined(separator: " ve ")
        return "\(names) izin alırsan \(days) gün · \(range)"
    }
}

struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let calendar: String
}

@MainActor @Observable
final class TakvimStore {
    private struct Raw: Codable { let date: String; let localName: String }
    /// Year → holidays as fetched.
    private var raw: [String: [Raw]] = Storage.load([String: [Raw]].self, "holidays.json") ?? [:]
    var events: [CalendarEvent] = []
    var nextEvent: CalendarEvent?
    var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var fetchedYears: Set<String> = []

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loadEvents(enabled: true) }
        }
    }

    // MARK: Holidays

    /// This year and next, each fetched once per launch (the list for next year firms up during the year).
    func refresh() async {
        let y = Day.cal.component(.year, from: Date())
        for year in [y, y + 1].map(String.init) where !fetchedYears.contains(year) {
            guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/TR"),
                  let data = try? await fetch(url), let list = try? JSONDecoder().decode([Raw].self, from: data), !list.isEmpty else { continue }
            fetchedYears.insert(year)
            raw[year] = list
        }
        Storage.save(raw, "holidays.json")
    }

    /// Holidays, half days and well-known days from today through the next twelve months, in date order.
    /// Multi-day bayrams come back as one item.
    var upcoming: [SpecialDay] {
        let today = Day.cal.startOfDay(for: Date())
        guard let limit = Day.cal.date(byAdding: .month, value: 12, to: today) else { return [] }
        let y = Day.cal.component(.year, from: today)
        let all = (holidays + [y, y + 1].flatMap(Self.wellKnown)).filter { $0.end >= today && $0.start <= limit }
        return all.sorted { ($0.start, $0.kind == .tatil ? 0 : 1) < ($1.start, $1.kind == .tatil ? 0 : 1) }
    }

    var nextHoliday: SpecialDay? { upcoming.first { $0.kind == .tatil } }

    private var holidays: [SpecialDay] {
        var out: [SpecialDay] = []
        let days = raw.values.flatMap { $0 }.compactMap { r -> (Date, String, Bool)? in
            guard let d = Day.date(r.date) else { return nil }
            let tentative = r.localName.contains("Tentative")
            let name = r.localName.replacingOccurrences(of: #"\s*\d+\. Gün|\s*\(Tentative Date\)"#, with: "", options: .regularExpression)
            return (d, name, tentative)
        }.sorted { $0.0 < $1.0 }
        for (d, name, tentative) in days {
            // another holiday can fall inside a bayram (19 Mayıs), so look for the same name, not just the last item
            if let i = out.lastIndex(where: { $0.name == name }), let next = Day.cal.date(byAdding: .day, value: 1, to: out[i].end),
               Day.cal.isDate(next, inSameDayAs: d) {
                let last = out[i]
                out[i] = SpecialDay(name: name, start: last.start, end: d, kind: .tatil, tentative: last.tentative || tentative)
            } else {
                out.append(SpecialDay(name: name, start: d, end: d, kind: .tatil, tentative: tentative))
            }
        }
        // the afternoon before a bayram (and before 29 Ekim) is off too
        let halves = out.filter { $0.name.contains("Bayramı") && ($0.name.hasPrefix("Ramazan") || $0.name.hasPrefix("Kurban") || $0.name.hasPrefix("Cumhuriyet")) }
            .compactMap { h -> SpecialDay? in
                guard let eve = Day.cal.date(byAdding: .day, value: -1, to: h.start), !isWeekend(eve) else { return nil }
                return SpecialDay(name: "\(h.name) arifesi (öğleden sonra)", start: eve, end: eve, kind: .yarimGun, tentative: h.tentative)
            }
        return out + halves
    }

    private static func wellKnown(_ year: Int) -> [SpecialDay] {
        func d(_ m: Int, _ day: Int) -> Date? { Day.cal.date(from: DateComponents(year: year, month: m, day: day)) }
        /// n-th Sunday of a month.
        func sunday(_ m: Int, _ n: Int) -> Date? {
            guard let first = d(m, 1) else { return nil }
            let offset = (8 - Day.cal.component(.weekday, from: first)) % 7   // weekday 1 = Sunday
            return Day.cal.date(byAdding: .day, value: offset + 7 * (n - 1), to: first)
        }
        let list: [(String, Date?)] = [
            ("Sevgililer Günü", d(2, 14)), ("Dünya Kadınlar Günü", d(3, 8)), ("Çanakkale Zaferi", d(3, 18)),
            ("Anneler Günü", sunday(5, 2)), ("Babalar Günü", sunday(6, 3)),
            ("Atatürk'ü Anma Günü", d(11, 10)), ("Öğretmenler Günü", d(11, 24)),
        ]
        return list.compactMap { n, date in date.map { SpecialDay(name: n, start: $0, end: $0, kind: .onemli) } }
    }

    private func isWeekend(_ d: Date) -> Bool { Day.cal.isDateInWeekend(d) }

    // MARK: Long weekends

    /// For each upcoming holiday: the days off it joins up with, and whether one or two days of leave would
    /// link it to a weekend or another holiday. Only runs of three days or more are listed.
    var longWeekends: [LongWeekend] {
        let full = Set(holidays.filter { $0.kind == .tatil }.flatMap { h in dates(h.start, h.end).map { Day.key($0) } })
        func off(_ d: Date) -> Bool { isWeekend(d) || full.contains(Day.key(d)) }
        func step(_ d: Date, _ n: Int) -> Date { Day.cal.date(byAdding: .day, value: n, to: d) ?? d }
        func run(_ d: Date) -> (Date, Date) {
            var a = d, b = d
            while off(step(a, -1)) { a = step(a, -1) }
            while off(step(b, 1)) { b = step(b, 1) }
            return (a, b)
        }
        var out: [LongWeekend] = []
        for h in upcoming where h.kind == .tatil {
            let (a, b) = run(h.start)
            let base = LongWeekend(start: a, end: b, leave: [], holiday: h.name)
            var best = base
            // bridge up to two workdays on either side; worth it when each day of leave adds at least a weekend's worth
            for dir in [-1, 1] {
                var gap: [Date] = [], edge = dir < 0 ? a : b
                for _ in 0..<2 {
                    edge = step(edge, dir)
                    guard !off(edge) else { break }
                    gap.append(edge)
                    if off(step(edge, dir)) {
                        let (na, nb) = run(step(edge, dir))
                        let cand = LongWeekend(start: dir < 0 ? na : a, end: dir < 0 ? b : nb, leave: gap.sorted(), holiday: h.name)
                        if cand.days - base.days >= cand.leave.count * 2, cand.days > best.days { best = cand }
                        break
                    }
                }
            }
            if best.days >= 3, !out.contains(where: { $0.start == best.start }) { out.append(best) }
        }
        return out
    }

    private func dates(_ a: Date, _ b: Date) -> [Date] {
        var out: [Date] = [], d = a
        while d <= b { out.append(d); d = Day.cal.date(byAdding: .day, value: 1, to: d) ?? b.addingTimeInterval(1) }
        return out
    }

    // MARK: Mac Calendar

    /// Asks for access the first time, then loads today's events and the next one after today.
    func loadEvents(enabled: Bool) {
        guard enabled else { events = []; nextEvent = nil; return }
        access = EKEventStore.authorizationStatus(for: .event)
        if access == .notDetermined {
            Task {
                _ = try? await eventStore.requestFullAccessToEvents()
                access = EKEventStore.authorizationStatus(for: .event)
                if access == .fullAccess { loadEvents(enabled: true) }
            }
            return
        }
        guard access == .fullAccess else { events = []; nextEvent = nil; return }
        let start = Day.cal.startOfDay(for: Date())
        let end = Day.cal.date(byAdding: .day, value: 1, to: start)!
        let later = Day.cal.date(byAdding: .day, value: 14, to: start)!
        func map(_ e: EKEvent) -> CalendarEvent {
            CalendarEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Etkinlik", start: e.startDate, end: e.endDate,
                          allDay: e.isAllDay, color: Color(cgColor: e.calendar.cgColor), calendar: e.calendar.title)
        }
        let today = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
        events = today.map(map).sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
        nextEvent = eventStore.events(matching: eventStore.predicateForEvents(withStart: end, end: later, calendars: nil))
            .filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }.first.map(map)
    }
}

// MARK: - Views

/// "32 gün", "Yarın", "Bugün".
func countdown(_ d: Date) -> String {
    let n = Day.cal.dateComponents([.day], from: Day.cal.startOfDay(for: Date()), to: Day.cal.startOfDay(for: d)).day ?? 0
    return n <= 0 ? "Bugün" : n == 1 ? "Yarın" : "\(n) gün"
}

/// Bugün: the next holiday with a countdown, the coming special days, and today's Calendar events.
struct TakvimCard: View {
    @Environment(AppStore.self) private var store
    @State private var showAll = false

    var body: some View {
        let t = store.takvim
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "TAKVİM", link: "Tüm yıl →") { showAll = true }
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    if let h = t.nextHoliday {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(h.name).font(.serif(17)).tracking(-0.2).lineLimit(1)
                                Spacer()
                                Text(countdown(h.start)).font(.mono(17)).foregroundStyle(T.accent)
                            }
                            Text(h.dateText + (h.tentative ? " · tahmini" : "")).font(.ui(11.5)).foregroundStyle(T.ink3)
                            if let lw = t.longWeekends.first(where: { $0.holiday == h.name }), lw.days >= 3 {
                                Label(lw.text, systemImage: "sun.max").font(.ui(11.5, .medium)).foregroundStyle(T.ink2).lineLimit(2)
                                    .padding(.top, 3)
                            }
                        }
                        .padding(14)
                    }
                    let rest = t.upcoming.filter { $0.id != t.nextHoliday?.id }.prefix(3)
                    ForEach(Array(rest)) { d in
                        Rule(color: T.rule2)
                        HStack(spacing: 8) {
                            Circle().fill(d.kind == .tatil ? T.accent : d.kind == .yarimGun ? T.accent.opacity(0.5) : T.ink3.opacity(0.5)).frame(width: 6, height: 6)
                            Text(d.name).font(.ui(12.5)).lineLimit(1)
                            Spacer()
                            Text(Day.format(d.start, "d MMM")).font(.mono(10.5, .regular)).foregroundStyle(T.ink3)
                            Text(countdown(d.start)).font(.mono(11)).frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    if store.prefs.showCalendarEvents { events(t) }
                }
            }
        }
        .task { await t.refresh() }
        .task(id: store.prefs.showCalendarEvents) {
            while !Task.isCancelled {
                t.loadEvents(enabled: store.prefs.showCalendarEvents)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .sheet(isPresented: $showAll) { YearSheet().environment(store) }
        // `-showYear YES` (command line only): screenshot of the year sheet
        .onAppear { if UserDefaults.standard.bool(forKey: "showYear") { showAll = true } }
    }

    @ViewBuilder private func events(_ t: TakvimStore) -> some View {
        Rule()
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "BUGÜN TAKVİMİNDE")
            if t.access == .denied || t.access == .restricted {
                Text("PANO'nun takvime erişimi kapalı. Sistem Ayarları › Gizlilik ve Güvenlik › Takvimler'den aç.")
                    .font(.ui(11.5)).foregroundStyle(T.ink3)
            } else if t.events.isEmpty {
                Text("Bugün etkinlik yok" + (t.nextEvent.map { " · Sıradaki: \(Day.format($0.start, "d MMM EEE HH:mm")) \($0.title)" } ?? ""))
                    .font(.ui(12)).foregroundStyle(T.ink3).lineLimit(2)
            }
            ForEach(t.events) { e in
                let past = !e.allDay && e.end < Date()
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5).fill(e.color).frame(width: 3, height: 16)
                    Text(e.allDay ? "Tüm gün" : Day.hm(e.start)).font(.mono(10.5)).foregroundStyle(T.ink3).frame(width: 52, alignment: .leading)
                    Text(e.title).font(.ui(12.5)).lineLimit(1)
                    Spacer()
                }
                .opacity(past ? 0.45 : 1)
            }
        }
        .padding(14)
    }
}

/// The next twelve months: every holiday, half day and special day, month by month, plus the long weekends.
private struct YearSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let t = store.takvim
        let months = Dictionary(grouping: t.upcoming) { Day.format($0.start, "yyyy-MM") }.sorted { $0.key < $1.key }
        VStack(spacing: 0) {
            HStack {
                Text("Önümüzdeki 12 ay").font(.serif(21))
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(18)
            .overlay(alignment: .bottom) { Rule() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !t.longWeekends.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "UZUN TATİLLER")
                            ForEach(t.longWeekends) { lw in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(lw.days) gün").font(.mono(12, .semibold)).foregroundStyle(T.accent).frame(width: 52, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lw.holiday).font(.ui(12.5, .medium))
                                        Text(lw.text).font(.ui(11.5)).foregroundStyle(T.ink3)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(months, id: \.key) { _, days in
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: Day.format(days[0].start, "MMMM yyyy").uppercased(with: Locale(identifier: "tr_TR")))
                            ForEach(days) { d in
                                HStack(alignment: isPhone ? .top : .center, spacing: 8) {
                                    Text(d.kind == .tatil ? "TATİL" : d.kind == .yarimGun ? "YARIM" : "")
                                        .font(.mono(8.5, .semibold)).foregroundStyle(T.accent).frame(width: 40, alignment: .leading)
                                        .padding(.top, isPhone ? 3 : 0)
                                    if isPhone {
                                        // phone: the date goes under the name so neither is cut off
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(d.name + (d.tentative ? " (tahmini)" : "")).font(.ui(14)).fixedSize(horizontal: false, vertical: true)
                                            Text(d.dateText).font(.ui(12)).foregroundStyle(T.ink3)
                                        }
                                    } else {
                                        Text(d.name + (d.tentative ? " (tahmini)" : "")).font(.ui(12.5)).lineLimit(1)
                                    }
                                    Spacer()
                                    if !isPhone { Text(d.dateText).font(.ui(11.5)).foregroundStyle(T.ink3) }
                                    Text(countdown(d.start)).font(.mono(isPhone ? 11.5 : 10.5)).frame(width: 56, alignment: .trailing)
                                }
                                .padding(.vertical, isPhone ? 4 : 0)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: isPhone ? nil : 560, height: isPhone ? nil : 560)
        .background(T.paper)
        .presentationDetents([.large])
    }
}
