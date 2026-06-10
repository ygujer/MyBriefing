import SwiftUI

struct ProgressTabView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("streakFreezeDays") private var streakFreezeDays: Int = 1
    @State private var dayDataMap: [String: DayData] = [:]
    private let service = LocalDayDataService()

    // ── Styling helpers ────────────────────────────────────────────

    private var shadowOpacity: Double { colorScheme == .dark ? 0.28 : 0.06 }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55), lineWidth: 1)
    }

    private var cardShadow: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.09)
    }

    // ── Date helpers ───────────────────────────────────────────────

    private var last14Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    // Full Mon-Sun of current week
    private var fullWeek: [Date] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    // Mon to today only (for counting)
    private var weekToDate: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return fullWeek.filter { $0 <= today }
    }

    // ── Stats ──────────────────────────────────────────────────────

    // Numerator: done days in the full Mon–Sun week
    private var weekDoneCount: Int {
        fullWeek.filter { workout.status(for: $0) == .done }.count
    }

    // Denominator: scheduled (non-rest) days in the full Mon–Sun week
    private var weekScheduledCount: Int {
        fullWeek.filter { !workout.exerciseLabel(for: $0).isEmpty }.count
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())   // start from TODAY so a done today shows instantly
        var streak = 0
        var freezesLeft = streakFreezeDays

        for _ in 0..<366 {
            let label   = workout.exerciseLabel(for: day)
            let status  = workout.status(for: day)
            let isToday = cal.isDateInToday(day)

            if label.isEmpty {
                // Rest day — skip silently
            } else if status == .done {
                streak += 1
            } else if isToday && status == .neutral {
                // Today not yet acted on — don't count, don't penalise
            } else {
                if freezesLeft > 0 { freezesLeft -= 1 } else { break }
            }

            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        return streak
    }

    // ── Body ───────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                (colorScheme == .dark
                    ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 260).ignoresSafeArea(edges: .top)

                ScrollView {
                    VStack(spacing: 16) {

                        // ── Summary row ───────────────────────────
                        HStack(spacing: 12) {
                            statCard(icon: "flame.fill", color: .orange,
                                     value: "\(currentStreak)",
                                     label: streakFreezeDays > 0 ? "Streak (\(streakFreezeDays)🧊)" : "Day Streak")

                            statCard(icon: "checkmark.seal.fill", color: .green,
                                     value: weekScheduledCount == 0 ? "—" : "\(weekDoneCount)/\(weekScheduledCount)",
                                     label: "Done This Week")
                        }
                        .padding(.top, 4)

                        // ── Weekly bar chart ──────────────────────
                        weeklyBarsCard

                        // ── 14-day log ────────────────────────────
                        logCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { loadData() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ForceHomeRefresh"))) { _ in
            loadData()
        }
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: cardShadow, radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
    }

    // MARK: - Weekly Bars

    private var weeklyBarsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(1.5)

            HStack(spacing: 5) {
                ForEach(fullWeek, id: \.self) { date in
                    dayBarCell(date: date)
                }
            }
            .frame(height: 80)

            // Legend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    legendDot(.green,                       "Done")
                    legendDot(.red,                         "Missed")
                    legendDot(.orange,                      "Postponed")
                    legendDot(Color.accentColor.opacity(0.55), "Planned")
                    legendDot(Color.secondary.opacity(0.35),   "Rest")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: cardShadow, radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func dayBarCell(date: Date) -> some View {
        let cal     = Calendar.current
        let today   = cal.startOfDay(for: Date())
        let isFut   = cal.startOfDay(for: date) > today
        let isToday = cal.isDateInToday(date)
        let status  = workout.status(for: date)
        let label   = workout.exerciseLabel(for: date)
        let isOff   = label.isEmpty

        let fillColor: Color = {
            if isOff { return Color.secondary.opacity(0.22) }   // Rest day — gray
            if isFut { return Color.accentColor.opacity(0.55) } // Future planned — blue
            switch status {
            case .done:     return .green
            case .notDone:  return .red
            case .postpone: return .orange
            case .neutral:  return Color.accentColor.opacity(0.45)
            }
        }()

        let key   = LocalDayDataService.dateKey(for: date)
        let moodVal = dayDataMap[key]?.mood ?? 0

        VStack(spacing: 3) {
            // Mood emoji above bar
            Text(!isFut && moodVal > 0 ? moodEmoji(for: moodVal) : " ")
                .font(.system(size: 13))
                .frame(height: 18)

            // Status bar
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fillColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    isToday
                        ? RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                        : nil
                )

            // Day letter
            Text(dayLetter(date))
                .font(.system(size: 10, weight: isToday ? .bold : .regular, design: .rounded))
                .foregroundColor(isToday ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: - 14-Day Log

    private var logCard: some View {
        VStack(spacing: 0) {
            // Section header inside the card
            HStack {
                Text("LAST 14 DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1.5)
                Spacer()
                HStack(spacing: 16) {
                    Text("Mood").font(.system(size: 10, design: .rounded)).foregroundColor(.secondary)
                    Text("Status").font(.system(size: 10, design: .rounded)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Rows newest-first
            ForEach(last14Days.reversed(), id: \.self) { date in
                logRow(date: date)
                if date != last14Days.first {
                    Divider().padding(.leading, 16)
                }
            }

            Spacer(minLength: 10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: cardShadow, radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func logRow(date: Date) -> some View {
        let cal     = Calendar.current
        let today   = cal.startOfDay(for: Date())
        let isFut   = cal.startOfDay(for: date) > today
        let isToday = cal.isDateInToday(date)
        let key     = LocalDayDataService.dateKey(for: date)
        let data    = dayDataMap[key] ?? DayData()
        let status  = workout.status(for: date)
        let label   = workout.exerciseLabel(for: date)
        let isOff   = label.isEmpty

        HStack(spacing: 10) {
            // Date column
            VStack(alignment: .leading, spacing: 1) {
                Text(shortWeekday(date))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundColor(isToday ? .accentColor : .primary)
                Text(shortMonthDay(date))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(width: 40, alignment: .leading)

            // Workout label
            Text(isOff ? "Rest" : label)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(isOff ? .secondary.opacity(0.55) : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mood: emoji + number
            Group {
                if !isFut && data.mood > 0 {
                    Text("\(moodEmoji(for: data.mood)) \(data.mood)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                } else {
                    Text("—").font(.system(size: 15))
                }
            }
            .frame(width: 44, alignment: .center)

            // Status icon
            Group {
                if isFut {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.secondary.opacity(0.3))
                } else if isOff {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.secondary.opacity(0.4))
                } else {
                    switch status {
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    case .notDone:
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    case .postpone:
                        Image(systemName: "arrow.right.circle.fill").foregroundColor(.orange)
                    case .neutral:
                        Image(systemName: "circle.dashed").foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            .font(.system(size: 17))
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .opacity(isFut ? 0.35 : 1.0)
    }

    // MARK: - Helpers

    private func dayLetter(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    private func shortWeekday(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US")
        return f.string(from: date)
    }

    private func shortMonthDay(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func loadData() {
        dayDataMap = service.batchLoad(dates: last14Days)
    }
}
