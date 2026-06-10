import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: Replace with your actual App Group identifier.
//   • Xcode → Main App Target → Signing & Capabilities → + App Groups
//   • Repeat for the Widget Extension target
//   • Use the same string in both places
// ─────────────────────────────────────────────────────────────────────────────
let widgetAppGroupID = "group.com.Ygujer.MyBriefing.mybriefing"

// ── Shared keys ──────────────────────────────────────────────────────────────
private let widgetDataKey     = "widget_day_data"
private let widgetZonePageKey = "widget_zone_page"

// ── Data Models ──────────────────────────────────────────────────────────────

struct WidgetDayData: Codable {
    var sleepDuration: String       = "-"   // e.g. "7h 23m"
    var sleepScore:    Double       = 0     // 0–100
    var mood:          Int          = 0     // 0 = not set, 1–10
    var breakfastName: String       = ""
    var dinnerName:    String       = ""
    var workoutLabel:  String       = ""    // "" = Rest Day
    var workoutStatus: Int          = 0     // WidgetWorkoutStatus.rawValue
    var zones:         [WidgetZone] = []
}


struct WidgetZone: Codable, Identifiable, Hashable {
    var id: String { name }
    var name:      String
    var startHour: Int
    var endHour:   Int
    let tasks: [Int: String]?
    var timeRange: String {
        String(format: "%d:00 – %d:00", startHour, endHour)
    }
}

// Mirrors WorkoutStatus — defined here so the widget target needs no reference
// to WorkoutManager.swift.
enum WidgetWorkoutStatus: Int {
    case neutral  = 0
    case done     = 1
    case notDone  = 2
    case postpone = 3
}

// ── Shared Read / Write Helpers ───────────────────────────────────────────────

extension WidgetDayData {

    /// Read the latest snapshot from the App Group shared container.
    static func readFromSharedDefaults() -> WidgetDayData {
        guard let ud  = UserDefaults(suiteName: widgetAppGroupID),
              let raw = ud.data(forKey: widgetDataKey),
              let val = try? JSONDecoder().decode(WidgetDayData.self, from: raw) else {
            return WidgetDayData()
        }
        return val
    }

    /// Current zone page index (0-based).
    static func readZonePage() -> Int {
        UserDefaults(suiteName: widgetAppGroupID)?.integer(forKey: widgetZonePageKey) ?? 0
    }

    /// Persist the zone page index (called from AppIntent.perform).
    static func writeZonePage(_ page: Int) {
        UserDefaults(suiteName: widgetAppGroupID)?.set(page, forKey: widgetZonePageKey)
    }
}
