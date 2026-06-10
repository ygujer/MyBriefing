import Foundation

final class LocalWorkoutService: WorkoutServiceProtocol {
    private let modeKey  = "workout_selected_mode"
    private let plansKey = "workout_plans"

    func save(mode: WorkoutMode, plans: [String: WeekPlan]) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        if let data = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(data, forKey: plansKey)
        }
    }

    func load() -> (mode: WorkoutMode, plans: [String: WeekPlan])? {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = WorkoutMode(rawValue: raw) else { return nil }
        let plans: [String: WeekPlan]
        if let data = UserDefaults.standard.data(forKey: plansKey),
           let decoded = try? JSONDecoder().decode([String: WeekPlan].self, from: data) {
            plans = decoded
        } else {
            plans = [:]
        }
        return (mode: mode, plans: plans)
    }
}
