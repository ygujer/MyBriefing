import Foundation
import WidgetKit

// Main-app-only writer. Add this file to the MAIN APP TARGET only.
final class WidgetDataWriter {
    static let shared = WidgetDataWriter()
    private init() {}

    static let sleepDurationKey = "widget_last_sleep_dur"
    static let sleepScoreKey    = "widget_last_sleep_scr"

    private let dataKey    = "widget_day_data"
    private let appGroupID = "group.com.Ygujer.MyBriefing.mybriefing"

    static func persistSleep(duration: String, score: Double) {
        UserDefaults.standard.set(duration, forKey: sleepDurationKey)
        UserDefaults.standard.set(score,    forKey: sleepScoreKey)
    }

    /// Builds a fresh snapshot and writes it to the shared App Group container.
    ///
    /// `dailyEvents` is a [startHour: eventTitle] map for today's calendar events.
    /// The caller (MyBriefingApp) is responsible for loading events from CalendarManager
    /// before calling this — that guarantees we use the live, permissioned EKEventStore.
    func sync(
        workoutManager: WorkoutManager,
        zoneSettings:   ZoneSettingsManager,
        dailyEvents:    [Int: String] = [:],
        date:           Date = Date()
    ) {
        let today   = Calendar.current.startOfDay(for: date)
        let service = LocalDayDataService()
        let dayData = service.load(for: today)

        let sleepDuration = UserDefaults.standard.string(forKey: Self.sleepDurationKey) ?? "-"
        let sleepScore    = UserDefaults.standard.double(forKey: Self.sleepScoreKey)

        var zones: [WidgetZone] = []

        // Returns only the hours within [start, end] that have a matching event.
        func buildTasks(from start: Int, to end: Int) -> [Int: String] {
            guard start <= end else { return [:] }
            var dict: [Int: String] = [:]
            for h in start...end {
                if let title = dailyEvents[h], !title.isEmpty { dict[h] = title }
            }
            return dict
        }

        if zoneSettings.z1Enabled {
            zones.append(WidgetZone(name: zoneSettings.z1Name,
                                    startHour: zoneSettings.z1Start,
                                    endHour:   zoneSettings.z1End,
                                    tasks:     buildTasks(from: zoneSettings.z1Start,
                                                          to:   zoneSettings.z1End)))
        }
        if zoneSettings.z2Enabled {
            zones.append(WidgetZone(name: zoneSettings.z2Name,
                                    startHour: zoneSettings.z2Start,
                                    endHour:   zoneSettings.z2End,
                                    tasks:     buildTasks(from: zoneSettings.z2Start,
                                                          to:   zoneSettings.z2End)))
        }
        if zoneSettings.z3Enabled {
            zones.append(WidgetZone(name: zoneSettings.z3Name,
                                    startHour: zoneSettings.z3Start,
                                    endHour:   zoneSettings.z3End,
                                    tasks:     buildTasks(from: zoneSettings.z3Start,
                                                          to:   zoneSettings.z3End)))
        }

        let bf = dayData.meals.first(where: { $0.type == "Breakfast" })?.name ?? ""
        let dn = dayData.meals.first(where: { $0.type == "Dinner"    })?.name ?? ""

        let payload = WidgetDayData(
            sleepDuration: sleepDuration,
            sleepScore:    sleepScore,
            mood:          dayData.mood,
            breakfastName: bf,
            dinnerName:    dn,
            workoutLabel:  workoutManager.exerciseLabel(for: today),
            workoutStatus: workoutManager.status(for: today).rawValue,
            zones:         zones
        )

        guard let encoded  = try? JSONEncoder().encode(payload),
              let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(encoded, forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
