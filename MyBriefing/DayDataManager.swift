import Foundation
import Combine

struct Meal: Codable, Identifiable {
    var id: UUID = UUID()
    var type: String
    var name: String = ""
    var mealTime: Date? = nil

    private enum CodingKeys: String, CodingKey { case id, type, name, mealTime }

    init(id: UUID = UUID(), type: String, name: String = "", mealTime: Date? = nil) {
        self.id = id; self.type = type; self.name = name; self.mealTime = mealTime
    }

    // Resilient decode: handles missing id, ignores legacy calories key
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = (try? c.decode(UUID.self,   forKey: .id))       ?? UUID()
        type     = (try? c.decode(String.self, forKey: .type))     ?? ""
        name     = (try? c.decode(String.self, forKey: .name))     ?? ""
        mealTime = try? c.decode(Date.self,    forKey: .mealTime)
    }
}

struct DayData: Codable {
    var meals: [Meal]      = [Meal(type: "Breakfast"), Meal(type: "Dinner")]
    var sportExtra: String = ""
    var mood: Int          = 0   // 0 = not set, 1–10 scale
    var note: String       = ""

    enum CodingKeys: String, CodingKey {
        case meals, sportExtra, mood, note
    }

    private enum LegacyKeys: String, CodingKey {
        case breakfast, dinner, moodEmoji
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedMeals = try? c.decode([Meal].self, forKey: .meals) {
            meals = decodedMeals
        } else {
            let leg     = try? decoder.container(keyedBy: LegacyKeys.self)
            let bfName  = (try? leg?.decode(String.self, forKey: .breakfast)) ?? ""
            let dinName = (try? leg?.decode(String.self, forKey: .dinner))    ?? ""
            meals = [Meal(type: "Breakfast", name: bfName), Meal(type: "Dinner", name: dinName)]
        }
        sportExtra = (try? c.decode(String.self, forKey: .sportExtra)) ?? ""
        note       = (try? c.decode(String.self, forKey: .note))       ?? ""
        // Prefer new Int mood; fall back to migrating the legacy emoji string
        if let moodInt = try? c.decode(Int.self, forKey: .mood) {
            mood = moodInt
        } else {
            let legacyC  = try? decoder.container(keyedBy: LegacyKeys.self)
            let oldEmoji = (try? legacyC?.decode(String.self, forKey: .moodEmoji)) ?? "-"
            mood = Self.migrateMoodEmoji(oldEmoji)
        }
    }

    private static func migrateMoodEmoji(_ emoji: String) -> Int {
        switch emoji {
        case "🤩": return 9
        case "🙂": return 7
        case "😐": return 5
        case "🙁": return 3
        case "😫": return 2
        default:   return 0
        }
    }
}

/// Maps a 1–10 mood integer to a representative emoji.
func moodEmoji(for value: Int) -> String {
    switch value {
    case 1...2:  return "😭"
    case 3...4:  return "☹️"
    case 5...6:  return "😐"
    case 7...8:  return "🙂"
    case 9...10: return "🤩"
    default:     return "—"
    }
}

// MARK: - Quick Pick Meals

enum QuickPickCategory: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case dinner    = "Dinner"
}

struct QuickPickMeal: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var category: QuickPickCategory
}

class QuickPickStore: ObservableObject {
    private static let udKey = "quickPickMeals_v1"

    @Published var meals: [QuickPickMeal] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let decoded = try? JSONDecoder().decode([QuickPickMeal].self, from: data) {
            meals = decoded
        } else {
            meals = [
                QuickPickMeal(name: "Klasik",      category: .breakfast),
                QuickPickMeal(name: "Omlet",        category: .breakfast),
                QuickPickMeal(name: "Burger",       category: .dinner),
                QuickPickMeal(name: "Tavuk Pilav",  category: .dinner),
            ]
        }
    }

    func add(_ meal: QuickPickMeal) { meals.append(meal) }

    private func save() {
        if let data = try? JSONEncoder().encode(meals) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }
}

// MARK: - Day Data Manager

class DayDataManager: ObservableObject {
    @Published var currentDayData: DayData = DayData()
    private let service: DayDataServiceProtocol

    init(service: DayDataServiceProtocol = LocalDayDataService()) {
        self.service = service
    }

    func loadData(for date: Date) { currentDayData = service.load(for: date) }
    func saveData(for date: Date) { service.save(currentDayData, for: date) }
    func peekData(for date: Date) -> DayData { service.load(for: date) }

    static func formatDate(_ date: Date) -> String { LocalDayDataService.dateKey(for: date) }
    func formatDate(_ date: Date) -> String { DayDataManager.formatDate(date) }
}
