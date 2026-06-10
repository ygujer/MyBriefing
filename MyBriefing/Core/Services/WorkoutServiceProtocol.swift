import Foundation

protocol WorkoutServiceProtocol {
    func save(mode: WorkoutMode, plans: [String: WeekPlan])
    func load() -> (mode: WorkoutMode, plans: [String: WeekPlan])?
}
