import Foundation
import EventKit
import Combine

@MainActor
class CalendarManager: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var writableCalendars: [EKCalendar] = []
    private(set) var lastLoadedDate: Date? = nil
    private let store = EKEventStore()

    func start() async {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        await requestAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if let date = self.lastLoadedDate { self.loadEvents(for: date) }
            }
        }
    }

    func requestAccess() async {
        do {
            if #available(iOS 17.0, *) {
                _ = try await store.requestFullAccessToEvents()
            } else {
                _ = try await store.requestAccess(to: .event)
            }
            loadWritableCalendars()
        } catch {
            // İzin verilmedi
        }
    }

    func loadWritableCalendars() {
        writableCalendars = store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }
    
    // Ayarlarda seçili olan takvimleri filtreler
    private func getSelectedCalendars() -> [EKCalendar]? {
        let allCals = store.calendars(for: .event)
        let disabledString = UserDefaults.standard.string(forKey: "disabledCalendarIDs") ?? ""
        let disabledIDs = disabledString.components(separatedBy: ",")
        
        let filtered = allCals.filter { !disabledIDs.contains($0.calendarIdentifier) }
        return filtered.isEmpty ? nil : filtered // Eğer hepsi kapalıysa nil döner (hiçbir şey göstermez)
    }

    func loadEvents(for date: Date) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        let calendar = Calendar.current
        guard let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return }
        
        let targetCalendars = getSelectedCalendars()
        if targetCalendars?.isEmpty == true { self.events = []; return }
        
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: targetCalendars)
        lastLoadedDate = date
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func loadEventsInRange(from startDate: Date, to endDate: Date) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        let targetCalendars = getSelectedCalendars()
        if targetCalendars?.isEmpty == true { self.events = []; return }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        lastLoadedDate = nil
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(startingAt hour: Int) -> [EKEvent] {
        let calendar = Calendar.current
        return events.filter { calendar.component(.hour, from: $0.startDate) == hour }
    }

    private func mealTargetCalendar() -> EKCalendar? {
        let id = UserDefaults.standard.string(forKey: "mealCalendarIdentifier") ?? ""
        if !id.isEmpty, let cal = store.calendar(withIdentifier: id), cal.allowsContentModifications {
            return cal
        }
        return store.defaultCalendarForNewEvents
    }

    private func workoutTargetCalendar() -> EKCalendar? {
        let id = UserDefaults.standard.string(forKey: "workoutCalendarIdentifier") ?? ""
        if !id.isEmpty, let cal = store.calendar(withIdentifier: id), cal.allowsContentModifications {
            return cal
        }
        return store.defaultCalendarForNewEvents
    }

    /// True upsert: if a "Spor :" event already exists on that day, mutate it in place.
    /// Never deletes and re-creates, so there is zero window for duplicates.
    func upsertWorkoutEvent(for date: Date, label: String, startTime: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let target = workoutTargetCalendar() else { return }
        let cal = Calendar.current
        guard let dayStart = cal.date(bySettingHour: 0,  minute: 0, second: 0, of: date),
              let dayEnd   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return }

        let hm = cal.dateComponents([.hour, .minute], from: startTime)
        guard let start = cal.date(bySettingHour: hm.hour ?? 10, minute: hm.minute ?? 0,
                                   second: 0, of: date),
              let end   = cal.date(byAdding: .minute, value: 90, to: start) else { return }

        let title     = "Spor : \(label)"
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [target])
        let allEvents = store.events(matching: predicate)

        if let existing = allEvents.first(where: { isAppWorkoutEvent($0) }) {
            // Mutate the existing event — no duplicate ever created
            existing.title     = title
            existing.startDate = start
            existing.endDate   = end
            try? store.save(existing, span: .thisEvent, commit: true)

            // Delete any extra duplicates that may have crept in
            for extra in allEvents.dropFirst() where isAppWorkoutEvent(extra) {
                try? store.remove(extra, span: .thisEvent, commit: true)
            }
        } else {
            let ev       = EKEvent(eventStore: store)
            ev.title     = title
            ev.startDate = start
            ev.endDate   = end
            ev.calendar  = target
            try? store.save(ev, span: .thisEvent, commit: true)
        }

        if let loaded = lastLoadedDate, cal.isDate(loaded, inSameDayAs: date) {
            loadEvents(for: date)
        }
    }

    func deleteWorkoutEvent(for date: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let target = workoutTargetCalendar() else { return }
        let cal = Calendar.current
        guard let dayStart = cal.date(bySettingHour: 0,  minute: 0, second: 0, of: date),
              let dayEnd   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return }

        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [target])
        var deleted = false
        for ev in store.events(matching: predicate) where isAppWorkoutEvent(ev) {
            try? store.remove(ev, span: .thisEvent, commit: false)
            deleted = true
        }
        if deleted { try? store.commit() }

        if let loaded = lastLoadedDate, cal.isDate(loaded, inSameDayAs: date) {
            loadEvents(for: date)
        }
    }

    /// Single-pass range delete: removes every "Spor :" event from `startDate`
    /// through +1 year. Called by the absolute Remove action so no orphan events survive.
    func deleteAllFutureWorkoutEvents(from startDate: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let target = workoutTargetCalendar() else { return }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: startDate)
        guard let end = cal.date(byAdding: .year, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [target])
        var deleted = false
        for ev in store.events(matching: predicate) where isAppWorkoutEvent(ev) {
            try? store.remove(ev, span: .thisEvent, commit: false)
            deleted = true
        }
        if deleted { try? store.commit() }

        if let loaded = lastLoadedDate, loaded >= start { loadEvents(for: loaded) }
    }

    /// One-way sync: Calendar → App. Reads "Spor :" events for the next 60 days
    /// and calls `workoutManager.setLabelOverride` when the user has edited the title
    /// externally. Never writes to the calendar — loop-safe by design.
    func syncWorkoutsFromCalendar(into workoutManager: WorkoutManager) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 60, to: start) else { return }

        let targetCalendars = getSelectedCalendars()
        guard targetCalendars?.isEmpty != true else { return }

        let predicate     = store.predicateForEvents(withStart: start, end: end, calendars: targetCalendars)
        let workoutEvents = store.events(matching: predicate).filter { isAppWorkoutEvent($0) }

        for event in workoutEvents {
            guard let eventStart: Date = event.startDate else { continue }
            let date = cal.startOfDay(for: eventStart)

            guard let calLabel = workoutLabelFromEvent(event), !calLabel.isEmpty else { continue }

            let appLabel       = workoutManager.exerciseLabel(for: date)
            let currentOverride = workoutManager.entry(for: date)?.labelOverride

            // Guard: skip if the app already reflects this label — prevents no-op churn
            guard calLabel != appLabel, calLabel != currentOverride else { continue }

            // Calendar has a newer label → update app state only; never call upsertWorkoutEvent
            workoutManager.setLabelOverride(calLabel, for: date)
        }
    }

    // Legacy — kept so existing callers compile
    func syncWorkoutEvent(for date: Date, at time: Date, label: String = "") {
        upsertWorkoutEvent(for: date, label: label.isEmpty ? "Spor" : label, startTime: time)
    }

    func removeWorkoutEvent(for date: Date) {
        deleteWorkoutEvent(for: date)
    }

    func isAppWorkoutEvent(_ event: EKEvent) -> Bool {
        guard let t = event.title else { return false }
        return t == "Spor" || t.hasPrefix("Spor : ")
    }

    func workoutLabelFromEvent(_ event: EKEvent) -> String? {
        guard let t = event.title, t.hasPrefix("Spor : ") else { return nil }
        let full = String(t.dropFirst(7))
        return full.components(separatedBy: " + ").first.flatMap { $0.isEmpty ? nil : $0 }
    }

    // Write app-entered meals back to the chosen meal calendar (fallback: default calendar).
    // Existing app-written events for that date are replaced so edits stay in sync.
    func syncMealEvents(_ meals: [Meal], for date: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              let target = mealTargetCalendar() else { return }

        let cal = Calendar.current
        guard let dayStart = cal.date(bySettingHour: 0,  minute: 0, second: 0, of: date),
              let dayEnd   = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return }

        // Remove previously written meal events (identified by known prefixes)
        let predicate  = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [target])
        let appPrefixes = ["Kahvaltı - ", "Yemek - "]
        for ev in store.events(matching: predicate)
            where appPrefixes.contains(where: { ev.title?.hasPrefix($0) == true }) {
            try? store.remove(ev, span: .thisEvent, commit: false)
        }

        // Time windows per meal type
        let slots: [String: (start: Int, end: Int)] = [
            "Breakfast": (12, 13),
            "Dinner":    (18, 19)
        ]
        let prefixes: [String: String] = [
            "Breakfast": "Kahvaltı - ",
            "Dinner":    "Yemek - "
        ]

        for meal in meals where !meal.name.isEmpty {
            let prefix = prefixes[meal.type] ?? "Yemek - "
            let startDate: Date
            let endDate: Date
            if let mealTime = meal.mealTime {
                let comps = cal.dateComponents([.hour, .minute], from: mealTime)
                let h = comps.hour ?? 12
                let m = comps.minute ?? 0
                guard let s = cal.date(bySettingHour: h, minute: m, second: 0, of: date),
                      let e = cal.date(byAdding: .minute, value: 60, to: s) else { continue }
                startDate = s; endDate = e
            } else {
                let slot = slots[meal.type] ?? (12, 13)
                guard let s = cal.date(bySettingHour: slot.start, minute: 0, second: 0, of: date),
                      let e = cal.date(bySettingHour: slot.end,   minute: 0, second: 0, of: date) else { continue }
                startDate = s; endDate = e
            }
            let ev       = EKEvent(eventStore: store)
            ev.title     = prefix + meal.name
            ev.startDate = startDate
            ev.endDate   = endDate
            ev.calendar  = target
            try? store.save(ev, span: .thisEvent, commit: false)
        }

        try? store.commit()

        // Keep the published events list up to date if we're viewing this date
        if let loaded = lastLoadedDate, cal.isDate(loaded, inSameDayAs: date) {
            loadEvents(for: date)
        }
    }

    func updateEventTimes(_ event: EKEvent, start: Date, end: Date) {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        event.startDate = start
        event.endDate = end
        try? store.save(event, span: .thisEvent, commit: true)
        if let loaded = lastLoadedDate, Calendar.current.isDate(loaded, inSameDayAs: start) {
            loadEvents(for: loaded)
        }
    }

    // Convenience wrapper: update a single meal type without rebuilding the full meals array.
    // Delegates to syncMealEvents so duplicate-prevention is handled automatically.
    func saveMealEvent(type: String, mealName: String, for date: Date) {
        let meal = Meal(type: type, name: mealName)
        syncMealEvents([meal], for: date)
    }
}
