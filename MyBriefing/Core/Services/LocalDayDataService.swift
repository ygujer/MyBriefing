import Foundation

final class LocalDayDataService: DayDataServiceProtocol {
    private let udKey = "app_day_data"

    // MARK: - DayDataServiceProtocol

    func load(for date: Date) -> DayData {
        guard let dict = UserDefaults.standard.dictionary(forKey: udKey),
              let raw  = dict[Self.dateKey(for: date)] as? Data,
              let decoded = try? JSONDecoder().decode(DayData.self, from: raw) else { return DayData() }
        return decoded
    }

    func save(_ data: DayData, for date: Date) {
        var dict = UserDefaults.standard.dictionary(forKey: udKey) ?? [:]
        if let encoded = try? JSONEncoder().encode(data) {
            dict[Self.dateKey(for: date)] = encoded
            UserDefaults.standard.set(dict, forKey: udKey)
        }
    }

    func batchLoad(dates: [Date]) -> [String: DayData] {
        let dict = UserDefaults.standard.dictionary(forKey: udKey) ?? [:]
        var result: [String: DayData] = [:]
        for date in dates {
            let k = Self.dateKey(for: date)
            if let raw = dict[k] as? Data,
               let decoded = try? JSONDecoder().decode(DayData.self, from: raw) {
                result[k] = decoded
            }
        }
        return result
    }

    func batchSave(_ updates: [(Date, DayData)]) {
        var dict = UserDefaults.standard.dictionary(forKey: udKey) ?? [:]
        for (date, data) in updates {
            if let encoded = try? JSONEncoder().encode(data) {
                dict[Self.dateKey(for: date)] = encoded
            }
        }
        UserDefaults.standard.set(dict, forKey: udKey)
    }

    func loadAll() -> [String: DayData] {
        guard let dict = UserDefaults.standard.dictionary(forKey: udKey) else { return [:] }
        return dict.compactMapValues { raw in
            guard let data = raw as? Data else { return nil }
            return try? JSONDecoder().decode(DayData.self, from: data)
        }
    }

    // MARK: - Helpers

    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
