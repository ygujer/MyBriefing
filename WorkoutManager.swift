import Foundation
import Combine

// MARK: - State Machine Types

enum WorkoutStatus: Int, Codable, Equatable {
    case neutral  = 0
    case done     = 1
    case notDone  = 2
    case postpone = 3
}

struct WorkoutScheduleEntry: Codable, Equatable {
    var splitKey: String
    var splitDayIndex: Int                // 0 = Mon … 6 = Sun
    var status: WorkoutStatus  = .neutral
    var completedAt: Date?     = nil      // floor-to-hour timestamp set when .done
    var plannedTimeOverride: Date? = nil  // DatePicker override set in HomeView
    var labelOverride: String? = nil      // user manually typed a different name
}

// MARK: - Split configuration

enum WorkoutMode: String, CaseIterable, Codable, Identifiable {
    case ppl        = "PPL"
    case upperLower = "Upper / Lower"
    case run        = "Run"
    case custom     = "Custom"
    var id: String { rawValue }
}

struct WeekPlan: Codable {
    var days: [String]    = Array(repeating: "", count: 7)
    var offDays: Set<Int> = []
    var times: [Date?]    = Array(repeating: nil, count: 7)

    init() {}
    init(days: [String], offDays: Set<Int> = [], times: [Date?] = Array(repeating: nil, count: 7)) {
        self.days = days; self.offDays = offDays; self.times = times
    }

    enum CodingKeys: String, CodingKey { case days, offDays, times }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days    = (try? c.decode([String].self,   forKey: .days))    ?? Array(repeating: "", count: 7)
        offDays = (try? c.decode(Set<Int>.self,   forKey: .offDays)) ?? []
        var t   = (try? c.decode([Date?].self,    forKey: .times))   ?? []
        while t.count < 7 { t.append(nil) }
        times = t
        while days.count < 7 { days.append("") }
    }
}

// MARK: - WorkoutManager

final class WorkoutManager: ObservableObject {

    // MARK: Published

    @Published var selectedSplitKey: String = "" {
        didSet {
            guard !isLoading else { return }
            if selectedSplitKey.isEmpty {
                UserDefaults.standard.set("", forKey: Self.splitKeyUD)
                return
            }
            if plans[selectedSplitKey] == nil {
                plans[selectedSplitKey] = WorkoutMode(rawValue: selectedSplitKey)
                    .map { Self.defaultPlan(for: $0) } ?? WeekPlan()
            }
            UserDefaults.standard.set(selectedSplitKey, forKey: Self.splitKeyUD)
            savePlans()
        }
    }

    @Published var plans: [String: WeekPlan] = [:] {
        didSet { guard !isLoading else { return }; savePlans() }
    }

    @Published var customSplitNames: [String] = [] {
        didSet {
            guard !isLoading else { return }
            if let data = try? JSONEncoder().encode(customSplitNames) {
                UserDefaults.standard.set(data, forKey: Self.customNamesUD)
            }
        }
    }

    /// Single source of truth for all per-day workout state.
    /// Not auto-saved via didSet — each mutating method calls saveEntries() explicitly.
    @Published var entries: [String: WorkoutScheduleEntry] = [:]

    /// When set, the weekday-cycle fallback in exerciseLabel is suppressed for all dates >= this value.
    /// Set by nukeUpcoming, cleared by scheduleRange.
    @Published var clearedFrom: Date? = nil

    // MARK: Computed

    var selectedMode: WorkoutMode  { WorkoutMode(rawValue: selectedSplitKey) ?? .custom }
    var currentDisplayName: String { selectedSplitKey.isEmpty ? "Select a Split" : selectedSplitKey }
    var isCustomSplit: Bool        { customSplitNames.contains(selectedSplitKey) }

    // MARK: Private

    private let service: WorkoutServiceProtocol
    private var isLoading = false

    private static let customNamesUD  = "workout_custom_split_names"
    private static let splitKeyUD     = "workout_selected_split_key"
    private static let entriesUD      = "workout_entries_v2"
    private static let clearedFromUD  = "workout_cleared_from"

    init(service: WorkoutServiceProtocol = LocalWorkoutService()) {
        self.service = service
        load()
    }

    // MARK: - Date utilities

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parseDate(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    // MARK: - Entry read API

    func entry(for date: Date) -> WorkoutScheduleEntry? {
        entries[Self.dateKey(for: date)]
    }

    func status(for date: Date) -> WorkoutStatus {
        entries[Self.dateKey(for: date)]?.status ?? .neutral
    }

    /// Exercise label: labelOverride → split plan lookup → weekday cycle fallback → "".
    func exerciseLabel(for date: Date) -> String {
        let key = Self.dateKey(for: date)
        if let e = entries[key] {
            if let ov = e.labelOverride, !ov.isEmpty { return ov }
            let plan = plans[e.splitKey]
                ?? WorkoutMode(rawValue: e.splitKey).map { Self.defaultPlan(for: $0) }
                ?? WeekPlan()
            if plan.offDays.contains(e.splitDayIndex) { return "" }
            let name = plan.days.indices.contains(e.splitDayIndex) ? plan.days[e.splitDayIndex] : ""
            return (name.isEmpty || name.lowercased() == "rest") ? "" : name
        }
        // Suppress weekday-cycle fallback for dates after a nuclear remove
        if let cleared = clearedFrom, Calendar.current.startOfDay(for: date) >= cleared { return "" }
        guard !selectedSplitKey.isEmpty else { return "" }
        let plan = currentPlan()
        let idx  = weekdayIndex(of: date)
        if plan.offDays.contains(idx) { return "" }
        let name = plan.days.indices.contains(idx) ? plan.days[idx] : ""
        return (name.isEmpty || name.lowercased() == "rest") ? "" : name
    }

    /// Planned workout start time: entry override → split time → 10:00 default.
    func plannedTime(for date: Date) -> Date {
        let key = Self.dateKey(for: date)
        if let e = entries[key], let t = e.plannedTimeOverride { return t }
        let dayIdx = entries[key]?.splitDayIndex ?? weekdayIndex(of: date)
        let plan   = currentPlan()
        if dayIdx < plan.times.count, let splitTime = plan.times[dayIdx] {
            let cal   = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: splitTime)
            return cal.date(bySettingHour: comps.hour ?? 10, minute: comps.minute ?? 0,
                            second: 0, of: date) ?? date
        }
        return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
    }

    // MARK: - State machine transitions

    /// Marks done. Floors current time to the start of that hour. Returns the stamped time.
    @discardableResult
    func markDone(for date: Date) -> Date {
        resolvePostponeConflicts()
        let floored = floorToHour(Date())
        let key     = Self.dateKey(for: date)
        var e       = entries[key] ?? makeEntry(for: date)
        e.status      = .done
        e.completedAt = floored
        entries[key]  = e
        saveEntries()
        return floored
    }

    func markNotDone(for date: Date) {
        resolvePostponeConflicts()
        let key = Self.dateKey(for: date)
        var e   = entries[key] ?? makeEntry(for: date)
        e.status      = .notDone
        e.completedAt = nil
        entries[key]  = e
        saveEntries()
    }

    /// Marks today as postponed, then cascades all entries from D+1…D+30 forward by one day.
    func postpone(from date: Date) {
        resolvePostponeConflicts()
        let cal       = Calendar.current
        let key       = Self.dateKey(for: date)
        let baseEntry = entries[key] ?? makeEntry(for: date)

        var mutated = entries

        var todayEntry         = baseEntry
        todayEntry.status      = .postpone
        todayEntry.completedAt = nil
        mutated[key]           = todayEntry

        // Backwards loop: copy D+i-1 → D+i so no source is read after it's been written.
        for i in stride(from: 30, through: 1, by: -1) {
            guard let target = cal.date(byAdding: .day, value: i,     to: date),
                  let source = cal.date(byAdding: .day, value: i - 1, to: date) else { continue }
            let targetKey = Self.dateKey(for: target)
            let sourceKey = Self.dateKey(for: source)

            if sourceKey == key {
                var carried         = baseEntry
                carried.status      = .neutral
                carried.completedAt = nil
                mutated[targetKey]  = carried
            } else if let src = mutated[sourceKey] {
                mutated[targetKey] = src
            } else {
                mutated.removeValue(forKey: targetKey)
            }
        }

        entries = mutated
        saveEntries()
    }

    /// Reverses a postpone: restores today to neutral and shifts D+1…D+29 back by one day.
    func undoPostpone(from date: Date) {
        let cal = Calendar.current
        let key = Self.dateKey(for: date)
        var mutated = entries

        if var e = mutated[key] {
            e.status = .neutral; e.completedAt = nil; mutated[key] = e
        }

        // Forward loop: copy D+i+1 → D+i (reads ahead so each source is still unmodified).
        for i in 1...29 {
            guard let target = cal.date(byAdding: .day, value: i,     to: date),
                  let source = cal.date(byAdding: .day, value: i + 1, to: date) else { continue }
            let targetKey = Self.dateKey(for: target)
            let sourceKey = Self.dateKey(for: source)
            if let src = mutated[sourceKey] { mutated[targetKey] = src }
            else { mutated.removeValue(forKey: targetKey) }
        }

        if let last = cal.date(byAdding: .day, value: 30, to: date) {
            mutated.removeValue(forKey: Self.dateKey(for: last))
        }

        entries = mutated
        saveEntries()
    }

    func resetToNeutral(for date: Date) {
        let key = Self.dateKey(for: date)
        guard var e = entries[key] else { return }
        e.status = .neutral; e.completedAt = nil
        entries[key] = e
        saveEntries()
    }

    // MARK: - Overrides

    func setLabelOverride(_ label: String?, for date: Date) {
        let key = Self.dateKey(for: date)
        var e   = entries[key] ?? makeEntry(for: date)
        e.labelOverride = label
        entries[key]    = e
        saveEntries()
    }

    func setPlannedTimeOverride(_ time: Date?, for date: Date) {
        let key = Self.dateKey(for: date)
        var e   = entries[key] ?? makeEntry(for: date)
        e.plannedTimeOverride = time
        entries[key]          = e
        saveEntries()
    }

    func setCompletedTime(_ time: Date, for date: Date) {
        let key = Self.dateKey(for: date)
        guard var e = entries[key], e.status == .done else { return }
        e.completedAt = time
        entries[key]  = e
        saveEntries()
    }

    // MARK: - Schedule management (WorkoutTabView)

    func scheduleRange(_ dates: [Date]) {
        let plan     = currentPlan()
        let splitKey = selectedSplitKey
        guard !splitKey.isEmpty else { return }
        resolvePostponeConflicts()
        var mutated = entries
        for date in dates {
            let idx     = weekdayIndex(of: date)
            let dateKey = Self.dateKey(for: date)
            let isOff   = plan.offDays.contains(idx)
                || (plan.days.indices.contains(idx)
                    && (plan.days[idx].isEmpty || plan.days[idx].lowercased() == "rest"))
            if isOff {
                mutated.removeValue(forKey: dateKey)
            } else {
                var e = WorkoutScheduleEntry(splitKey: splitKey, splitDayIndex: idx)
                e.plannedTimeOverride = mutated[dateKey]?.plannedTimeOverride
                mutated[dateKey] = e
            }
        }
        entries = mutated
        saveEntries()
    }

    func clearEntries(for dates: [Date]) {
        var mutated = entries
        for date in dates { mutated.removeValue(forKey: Self.dateKey(for: date)) }
        entries = mutated
        saveEntries()
    }

    /// Nuclear remove: wipes all entries from `date` onwards and sets the clearedFrom sentinel
    /// so the weekday-cycle fallback is also suppressed for those dates.
    func nukeUpcoming(from date: Date) {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        var mutated = entries
        for key in entries.keys {
            if let d = Self.parseDate(key), cal.startOfDay(for: d) >= start {
                mutated.removeValue(forKey: key)
            }
        }
        entries     = mutated
        clearedFrom = start
        saveEntries()
        saveClearedFrom()
    }

    // MARK: - Plan management (WorkoutTabView)

    func currentPlan() -> WeekPlan {
        guard !selectedSplitKey.isEmpty else { return WeekPlan() }
        return plans[selectedSplitKey]
            ?? WorkoutMode(rawValue: selectedSplitKey).map { Self.defaultPlan(for: $0) }
            ?? WeekPlan()
    }

    func addCustomSplit(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customSplitNames.contains(trimmed),
              WorkoutMode(rawValue: trimmed) == nil else { return }
        customSplitNames.append(trimmed)
        plans[trimmed]   = WeekPlan()
        selectedSplitKey = trimmed
    }

    func deleteCurrentCustomSplit() {
        guard isCustomSplit else { return }
        let name = selectedSplitKey
        selectedSplitKey = ""
        customSplitNames.removeAll { $0 == name }
        plans.removeValue(forKey: name)
    }

    func updateExercise(at idx: Int, to value: String) {
        var p = currentPlan(); p.days[idx] = value; plans[selectedSplitKey] = p
    }

    func updateTime(at idx: Int, to value: Date?) {
        guard !selectedSplitKey.isEmpty else { return }
        var p = currentPlan()
        while p.times.count < 7 { p.times.append(nil) }
        p.times[idx] = value
        plans[selectedSplitKey] = p
    }

    func toggleOffDay(at idx: Int) {
        var p = currentPlan()
        if p.offDays.contains(idx) { p.offDays.remove(idx) } else { p.offDays.insert(idx) }
        if let fixed = WorkoutMode(rawValue: selectedSplitKey), fixed != .custom {
            p.days = Self.generateSequence(for: fixed, offDays: p.offDays)
        }
        DispatchQueue.main.async { self.plans[self.selectedSplitKey] = p }
    }

    // MARK: - Conflict resolution

    private func resolvePostponeConflicts() {
        let today = Calendar.current.startOfDay(for: Date())
        var mutated = entries
        var changed = false
        for (key, e) in entries where e.status == .postpone {
            guard let entryDate = Self.parseDate(key) else { continue }
            if Calendar.current.startOfDay(for: entryDate) < today {
                var cleared = e; cleared.status = .neutral
                mutated[key] = cleared; changed = true
            }
        }
        if changed { entries = mutated }
    }

    // MARK: - Helpers

    private func weekdayIndex(of date: Date) -> Int {
        var cal = Calendar.current; cal.firstWeekday = 2
        return (cal.component(.weekday, from: date) - 2 + 7) % 7
    }

    private func floorToHour(_ date: Date) -> Date {
        let cal = Calendar.current
        var c   = cal.dateComponents([.year, .month, .day, .hour], from: date)
        c.minute = 0; c.second = 0
        return cal.date(from: c) ?? date
    }

    private func makeEntry(for date: Date) -> WorkoutScheduleEntry {
        WorkoutScheduleEntry(splitKey: selectedSplitKey, splitDayIndex: weekdayIndex(of: date))
    }

    // MARK: - Static split helpers

    static func generateSequence(for mode: WorkoutMode, offDays: Set<Int>) -> [String] {
        guard mode != .custom else { return Array(repeating: "", count: 7) }
        let sequence: [String]
        switch mode {
        case .ppl:        sequence = ["Push", "Pull", "Leg"]
        case .upperLower: sequence = ["Upper", "Lower"]
        case .run:        sequence = ["Run"]
        case .custom:     sequence = []
        }
        var days = Array(repeating: "Rest", count: 7); var seqIdx = 0
        for i in 0..<7 where !offDays.contains(i) {
            days[i] = sequence[seqIdx % sequence.count]; seqIdx += 1
        }
        return days
    }

    static func defaultPlan(for mode: WorkoutMode) -> WeekPlan {
        var offDays: Set<Int> = []
        if mode == .ppl        { offDays = [6] }
        if mode == .upperLower { offDays = [2, 5, 6] }
        return WeekPlan(days: generateSequence(for: mode, offDays: offDays), offDays: offDays)
    }

    // MARK: - Persistence

    private func savePlans() { service.save(mode: selectedMode, plans: plans) }

    private func saveClearedFrom() {
        if let d = clearedFrom {
            UserDefaults.standard.set(d.timeIntervalSinceReferenceDate, forKey: Self.clearedFromUD)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.clearedFromUD)
        }
    }

    func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.entriesUD)
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data  = UserDefaults.standard.data(forKey: Self.customNamesUD),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            customSplitNames = names
        }

        let saved = service.load()
        plans = saved?.plans ?? [:]
        selectedSplitKey = UserDefaults.standard.string(forKey: Self.splitKeyUD)
            ?? saved?.mode.rawValue ?? ""

        if !selectedSplitKey.isEmpty, plans[selectedSplitKey] == nil {
            plans[selectedSplitKey] = WorkoutMode(rawValue: selectedSplitKey)
                .map { Self.defaultPlan(for: $0) } ?? WeekPlan()
        }

        let cfInterval = UserDefaults.standard.double(forKey: Self.clearedFromUD)
        if cfInterval != 0 { clearedFrom = Date(timeIntervalSinceReferenceDate: cfInterval) }

        if let data    = UserDefaults.standard.data(forKey: Self.entriesUD),
           let decoded = try? JSONDecoder().decode([String: WorkoutScheduleEntry].self, from: data) {
            entries = decoded
        } else {
            // One-time migration from old schedule: [String: Int]
            if let data = UserDefaults.standard.data(forKey: "workout_schedule"),
               let old  = try? JSONDecoder().decode([String: Int].self, from: data), !old.isEmpty {
                entries = old.reduce(into: [:]) { dict, pair in
                    dict[pair.key] = WorkoutScheduleEntry(
                        splitKey: selectedSplitKey, splitDayIndex: pair.value)
                }
                saveEntries()
            }
        }
    }
}
