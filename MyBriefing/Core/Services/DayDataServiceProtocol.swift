import Foundation

protocol DayDataServiceProtocol {
    /// Load the DayData for a single calendar day.
    func load(for date: Date) -> DayData

    /// Persist the DayData for a single calendar day.
    func save(_ data: DayData, for date: Date)

    /// Load multiple days at once. Keys are "yyyy-MM-dd" strings.
    func batchLoad(dates: [Date]) -> [String: DayData]

    /// Persist multiple days in a single write.
    func batchSave(_ updates: [(Date, DayData)])

    /// Load every stored day (used for CloudKit migration in S8).
    func loadAll() -> [String: DayData]
}
