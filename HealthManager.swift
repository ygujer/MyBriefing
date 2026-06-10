import Foundation
import HealthKit
import Combine

class HealthManager: ObservableObject {
    @Published var sleepDuration: String = "-"
    @Published var sleepScore:    Double = 0.0   // 0–100

    // Per-stage durations (minutes)
    @Published var deepMinutes: Int = 0
    @Published var remMinutes:  Int = 0
    @Published var coreMinutes: Int = 0

    // Per-stage share of total sleep (0–100 %)
    @Published var deepPercent:  Double = 0.0
    @Published var remPercent:   Double = 0.0
    @Published var corePercent:  Double = 0.0

    let healthStore = HKHealthStore()

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
        } catch {
            print("HealthKit auth error: \(error.localizedDescription)")
        }
    }

    func fetchSleepData(for date: Date) {
        let cal = Calendar.current
        // Window: previous day 6 PM → selected day 6 PM captures a full night
        let endDate   = cal.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let startDate = cal.date(byAdding: .day, value: -1, to: endDate) ?? date

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: endDate, options: .strictStartDate)
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, _ in
            guard let self, let samples = samples as? [HKCategorySample] else { return }

            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]

            let asleepSamples = samples.filter { asleepValues.contains($0.value) }
            let deepSamples   = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
            let remSamples    = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
            let coreSamples   = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }
            let hasStageData  = !deepSamples.isEmpty || !remSamples.isEmpty || !coreSamples.isEmpty

            // Merge overlapping intervals per stage to eliminate double-counting
            let totalSeconds = self.mergedDuration(of: asleepSamples)
            let deepSeconds  = self.mergedDuration(of: deepSamples)
            let remSeconds   = self.mergedDuration(of: remSamples)
            let coreSeconds  = self.mergedDuration(of: coreSamples)

            let h = Int(totalSeconds) / 3600
            let m = (Int(totalSeconds) % 3600) / 60
            let durationString = totalSeconds > 0 ? "\(h)h \(m)m" : "-"

            let deepPct  = totalSeconds > 0 ? deepSeconds  / totalSeconds * 100.0 : 0.0
            let remPct   = totalSeconds > 0 ? remSeconds   / totalSeconds * 100.0 : 0.0
            let corePct  = totalSeconds > 0 ? coreSeconds  / totalSeconds * 100.0 : 0.0

            let score = self.computeScore(
                totalSeconds: totalSeconds,
                deepSeconds:  deepSeconds,
                remSeconds:   remSeconds,
                coreSeconds:  coreSeconds,
                hasStageData: hasStageData)

            DispatchQueue.main.async {
                self.sleepDuration = durationString
                self.sleepScore    = score
                self.deepMinutes   = Int(deepSeconds  / 60.0)
                self.remMinutes    = Int(remSeconds   / 60.0)
                self.coreMinutes   = Int(coreSeconds  / 60.0)
                self.deepPercent   = deepPct
                self.remPercent    = remPct
                self.corePercent   = corePct
                WidgetDataWriter.persistSleep(duration: durationString, score: score)
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Helpers

    // Merge overlapping intervals and return their total duration in seconds.
    // Prevents double-counting when Apple Watch and iPhone both log the same segment.
    private func mergedDuration(of samples: [HKCategorySample]) -> TimeInterval {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var merged: [(start: Date, end: Date)] = []
        for s in sorted {
            if let last = merged.last, s.startDate <= last.end {
                merged[merged.count - 1].end = max(last.end, s.endDate)
            } else {
                merged.append((s.startDate, s.endDate))
            }
        }
        return merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    // Score 0–100 built from four independent components:
    //
    //   Duration  (40 pts) — peaks at 8 h; ±7 pts per hour of deviation.
    //   Deep      (25 pts) — ideal band 13–23 % of total sleep.
    //   REM       (25 pts) — ideal band 18–25 % of total sleep.
    //   Balance   (10 pts) — core sleep in the 45–65 % band.
    //
    // Without stage data the duration score is scaled linearly to 0–100.
    private func computeScore(
        totalSeconds: TimeInterval,
        deepSeconds:  TimeInterval,
        remSeconds:   TimeInterval,
        coreSeconds:  TimeInterval,
        hasStageData: Bool
    ) -> Double {
        guard totalSeconds > 0 else { return 0 }

        let hrs = totalSeconds / 3600.0
        let durationPts = max(0.0, 40.0 - abs(hrs - 8.0) * 7.0)

        guard hasStageData else {
            return min(100.0, durationPts / 40.0 * 100.0)
        }

        let deepRatio = deepSeconds / totalSeconds
        let remRatio  = remSeconds  / totalSeconds
        let coreRatio = coreSeconds / totalSeconds

        let deepPts    = stagePts(ratio: deepRatio, low: 0.13, high: 0.23, max: 25.0)
        let remPts     = stagePts(ratio: remRatio,  low: 0.18, high: 0.25, max: 25.0)
        let balancePts = stagePts(ratio: coreRatio, low: 0.45, high: 0.65, max: 10.0)

        return min(100.0, durationPts + deepPts + remPts + balancePts)
    }

    // Linear ramp [0 → low] → full credit [low → high] → gentle fall-off above high.
    private func stagePts(ratio: Double, low: Double, high: Double, max: Double) -> Double {
        if ratio <= 0    { return 0 }
        if ratio <= low  { return max * (ratio / low) }
        if ratio <= high { return max }
        return Swift.max(0, max * (1.0 - (ratio - high) * 3.0))
    }
}
