// codepet/Models/UsageLedger.swift
import Foundation

/// One local day of department meetings: how many ran and what they would have cost at API
/// prices. A meeting runs on the founder's own Claude plan, so `costUsd` is an estimate of plan
/// usage, never an amount billed.
struct UsageDay: Codable, Equatable {
    var runs: Int
    var costUsd: Double
}

/// Where a room's cost goes once it leaves the chat (CP-028). The chat used to print "This run
/// cost $0.457" under every room — internal accounting a founder on their own plan cannot act
/// on. The figure is kept, added up per local day, and shown in Settings → Usage instead.
protocol UsageLedgering: AnyObject {
    func record(costUsd: Double, at date: Date)
    func day(_ date: Date) -> UsageDay
}

/// The real ledger: a `[yyyy-MM-dd: UsageDay]` dictionary in the defaults it is given, keyed by
/// the founder's LOCAL day, keeping the last `retentionDays`.
final class DefaultsUsageLedger: UsageLedgering {
    static let key = "cp_usageLedger"
    static let retentionDays = 30

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func record(costUsd: Double, at date: Date) {
        var days = load()
        var today = days[dayKey(date)] ?? UsageDay(runs: 0, costUsd: 0)
        today.runs += 1
        today.costUsd += max(0, costUsd)
        days[dayKey(date)] = today
        let cutoff = dayKey(calendar.date(byAdding: .day, value: -Self.retentionDays, to: date) ?? date)
        days = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: Self.key) }
    }

    func day(_ date: Date) -> UsageDay {
        load()[dayKey(date)] ?? UsageDay(runs: 0, costUsd: 0)
    }

    private func load() -> [String: UsageDay] {
        guard let data = defaults.data(forKey: Self.key),
              let days = try? JSONDecoder().decode([String: UsageDay].self, from: data) else { return [:] }
        return days
    }

    /// `yyyy-MM-dd` in `calendar`'s time zone, so keys sort as dates and a day is the founder's.
    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// What the test host gets by default, so no suite writes a meeting into the founder's real
/// preferences — the same rule as `NullChatThreadArchive`.
final class InMemoryUsageLedger: UsageLedgering {
    private var days: [DateComponents: UsageDay] = [:]
    private let calendar = Calendar.current

    func record(costUsd: Double, at date: Date) {
        let k = calendar.dateComponents([.year, .month, .day], from: date)
        var d = days[k] ?? UsageDay(runs: 0, costUsd: 0)
        d.runs += 1
        d.costUsd += max(0, costUsd)
        days[k] = d
    }

    func day(_ date: Date) -> UsageDay {
        days[calendar.dateComponents([.year, .month, .day], from: date)] ?? UsageDay(runs: 0, costUsd: 0)
    }
}

/// Settings → Usage copy for the day's meetings.
enum UsageCopy {
    static func todayLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cuộc họp phòng ban hôm nay" : "Department meetings today"
    }

    static func todayValue(_ day: UsageDay, lang: AppLanguage) -> String {
        guard day.runs > 0 else { return lang == .vi ? "Chưa có" : "None yet" }
        let cost = String(format: "~$%.2f", day.costUsd)
        if lang == .vi { return "\(day.runs) cuộc họp · \(cost)" }
        return "\(day.runs) \(day.runs == 1 ? "meeting" : "meetings") · \(cost)"
    }

    static func todayDetail(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Ước tính theo giá API. Chạy trên gói Claude của bạn nên bạn không bị tính phí số này."
            : "Estimated at API prices. It runs on your Claude plan, so you are not billed this amount."
    }
}
