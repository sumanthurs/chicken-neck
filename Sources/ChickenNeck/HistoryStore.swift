import Foundation

/// Aggregated posture stats for a single calendar day.
struct DayStat: Codable, Identifiable {
    let day: String          // "yyyy-MM-dd" (local)
    var goodSeconds: Double
    var badSeconds: Double
    var slouches: Int
    var sessions: Int

    var id: String { day }
    var totalSeconds: Double { goodSeconds + badSeconds }
    var goodMinutes: Double { goodSeconds / 60 }
    var badMinutes: Double { badSeconds / 60 }
    var goodPercent: Double { totalSeconds > 0 ? goodSeconds / totalSeconds * 100 : 0 }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var shortWeekday: String {
        guard let date = DayStat.parser.date(from: day) else { return day }
        return DayStat.weekday.string(from: date)
    }
}

/// A grouped slice of history (a day, week, or month) for charts/export.
struct HistoryBucket: Identifiable {
    let id = UUID()
    let label: String
    let goodSeconds: Double
    let badSeconds: Double
    var goodMinutes: Double { goodSeconds / 60 }
    var badMinutes: Double { badSeconds / 60 }
    var totalSeconds: Double { goodSeconds + badSeconds }
    var goodPercent: Double { totalSeconds > 0 ? goodSeconds / totalSeconds * 100 : 0 }
}

/// Persists per-day posture aggregates across app launches (UserDefaults JSON).
final class HistoryStore: ObservableObject {

    @Published private(set) var days: [String: DayStat] = [:]

    private let key = "historyDays"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Add a finished session's totals into the given day's aggregate.
    func record(good: Double, bad: Double, slouches: Int, on date: Date) {
        let key = HistoryStore.dayKey(date)
        var stat = days[key] ?? DayStat(day: key, goodSeconds: 0, badSeconds: 0, slouches: 0, sessions: 0)
        stat.goodSeconds += good
        stat.badSeconds += bad
        stat.slouches += slouches
        stat.sessions += 1
        days[key] = stat
        save()
    }

    /// The last `count` calendar days (oldest → newest), filling empty days.
    func lastDays(_ count: Int, now: Date = Date()) -> [DayStat] {
        let calendar = Calendar.current
        var result: [DayStat] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = HistoryStore.dayKey(date)
            result.append(days[key] ?? DayStat(day: key, goodSeconds: 0, badSeconds: 0, slouches: 0, sessions: 0))
        }
        return result
    }

    func clear() {
        days = [:]
        save()
    }

    // MARK: Aggregations for Daily / Weekly / Monthly views + export

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func sum(in interval: DateInterval) -> (Double, Double) {
        var good = 0.0, bad = 0.0
        for (key, stat) in days {
            guard let date = HistoryStore.dayParser.date(from: key) else { continue }
            if interval.contains(date) { good += stat.goodSeconds; bad += stat.badSeconds }
        }
        return (good, bad)
    }

    /// Last `count` days, oldest → newest.
    func dailyBuckets(_ count: Int = 7, now: Date = Date()) -> [HistoryBucket] {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return lastDays(count, now: now).map {
            let label = HistoryStore.dayParser.date(from: $0.day).map { f.string(from: $0) } ?? $0.day
            return HistoryBucket(label: label, goodSeconds: $0.goodSeconds, badSeconds: $0.badSeconds)
        }
    }

    /// Last `count` weeks, oldest → newest.
    func weeklyBuckets(_ count: Int = 8, now: Date = Date()) -> [HistoryBucket] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "MMM d"
        var result: [HistoryBucket] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .weekOfYear, value: -offset, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: d) else { continue }
            let (g, b) = sum(in: interval)
            result.append(HistoryBucket(label: f.string(from: interval.start), goodSeconds: g, badSeconds: b))
        }
        return result
    }

    /// Last `count` months, oldest → newest.
    func monthlyBuckets(_ count: Int = 6, now: Date = Date()) -> [HistoryBucket] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "MMM"
        var result: [HistoryBucket] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .month, value: -offset, to: now),
                  let interval = cal.dateInterval(of: .month, for: d) else { continue }
            let (g, b) = sum(in: interval)
            result.append(HistoryBucket(label: f.string(from: interval.start), goodSeconds: g, badSeconds: b))
        }
        return result
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: DayStat].self, from: data) else {
            return
        }
        days = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: key)
        }
    }
}
