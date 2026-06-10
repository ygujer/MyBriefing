import WidgetKit
import SwiftUI
import AppIntents

// MARK: - View Model

struct WidgetViewData {
    var sleepText:     String
    var moodText:      String
    var workoutText:   String
    var workoutStatus: Int       // WidgetWorkoutStatus.rawValue
    var breakfastText: String
    var dinnerText:    String
    var viewZones:     [ViewZone]

    static let placeholder = WidgetViewData(
        sleepText:     "7h 15m (82)",
        moodText:      "Mod: 8",
        workoutText:   "Push",
        workoutStatus: 1,
        breakfastText: "Klasik Kahvaltı",
        dinnerText:    "Tavuk Pilav",
        viewZones: [ViewZone(name: "Sabah Odağı", hours: [7, 8, 9, 10, 11],
                             tasks: [9: "SwiftUI Çalış", 10: "Toplantı"])]
    )
}

struct ViewZone {
    let name:  String
    let hours: [Int]
    let tasks: [Int: String]
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    private let appGroupID = "group.com.Ygujer.MyBriefing.mybriefing"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: .placeholder, pageIndex: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), data: fetchData(), pageIndex: getPageIndex()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry      = SimpleEntry(date: Date(), data: fetchData(), pageIndex: getPageIndex())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func getPageIndex() -> Int {
        UserDefaults(suiteName: appGroupID)?.integer(forKey: "zonePageIndex") ?? 0
    }

    private func fetchData() -> WidgetViewData {
        guard let raw     = UserDefaults(suiteName: appGroupID)?.data(forKey: "widget_day_data"),
              let decoded = try? JSONDecoder().decode(WidgetDayData.self, from: raw) else {
            return .placeholder
        }

        let mappedZones = decoded.zones.map { zone -> ViewZone in
            let s = zone.startHour, e = zone.endHour
            return ViewZone(name: zone.name,
                            hours: s <= e ? Array(s...e) : [],
                            tasks: zone.tasks ?? [:])
        }

        let score = Int(decoded.sleepScore)
        return WidgetViewData(
            sleepText:     decoded.sleepDuration + (score > 0 ? " (\(score))" : ""),
            moodText:      decoded.mood > 0 ? "Mod: \(decoded.mood)" : "—",
            workoutText:   decoded.workoutLabel.isEmpty ? "Dinlenme" : decoded.workoutLabel,
            workoutStatus: decoded.workoutStatus,
            breakfastText: decoded.breakfastName.isEmpty ? "Yok" : decoded.breakfastName,
            dinnerText:    decoded.dinnerName.isEmpty    ? "Yok" : decoded.dinnerName,
            viewZones:     mappedZones
        )
    }
}

struct SimpleEntry: TimelineEntry {
    let date:      Date
    let data:      WidgetViewData
    let pageIndex: Int
}

// MARK: - Interactive Intents

struct NextZonePageIntent: AppIntent {
    static var title: LocalizedStringResource = "Sonraki Zone"
    init() {}
    func perform() async throws -> some IntentResult {
        let ud = UserDefaults(suiteName: "group.com.Ygujer.MyBriefing.mybriefing")
        ud?.set((ud?.integer(forKey: "zonePageIndex") ?? 0) + 1, forKey: "zonePageIndex")
        return .result()
    }
}

struct PreviousZonePageIntent: AppIntent {
    static var title: LocalizedStringResource = "Önceki Zone"
    init() {}
    func perform() async throws -> some IntentResult {
        let ud = UserDefaults(suiteName: "group.com.Ygujer.MyBriefing.mybriefing")
        ud?.set(max(0, (ud?.integer(forKey: "zonePageIndex") ?? 0) - 1), forKey: "zonePageIndex")
        return .result()
    }
}

// MARK: - Root Entry View

struct MyBriefingWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 8) {
            // ── Top row ──────────────────────────────────────────────────────
            HStack(spacing: 6) {
                WidgetCard(title: "Uyku", value: entry.data.sleepText,
                           icon: "bed.double.fill", color: .indigo)
                WidgetCard(title: "Mod", value: entry.data.moodText,
                           icon: "face.smiling", color: .yellow)
                WidgetCard(title: "Spor",
                           value: entry.data.workoutText,
                           icon:  "dumbbell.fill",
                           color: .green,
                           statusDotColor: workoutDotColor(
                               status: entry.data.workoutStatus,
                               label:  entry.data.workoutText))
            }

            // ── Middle row ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                WidgetCard(title: "Kahvaltı", value: entry.data.breakfastText,
                           icon: "cup.and.saucer.fill", color: .orange)
                WidgetCard(title: "Akşam",   value: entry.data.dinnerText,
                           icon: "fork.knife", color: .red)
            }

            // ── Zone timeline ────────────────────────────────────────────────
            ZoneTimelinePanel(entry: entry)
        }
        .padding(14)
        .widgetURL(URL(string: "mybriefing://home"))
    }

    // Dot color: gray for rest day, otherwise driven by workout status.
    private func workoutDotColor(status: Int, label: String) -> Color {
        if label == "Dinlenme" { return .gray.opacity(0.7) }
        switch WidgetWorkoutStatus(rawValue: status) ?? .neutral {
        case .done:     return .green
        case .notDone:  return .red
        case .postpone: return .orange
        case .neutral:  return .blue
        }
    }
}

// MARK: - Zone Timeline Panel

struct ZoneTimelinePanel: View {
    var entry: Provider.Entry

    private var zones:       [ViewZone] { entry.data.viewZones }
    private var safeIndex:   Int        { zones.isEmpty ? 0 : abs(entry.pageIndex) % max(1, zones.count) }
    private var currentZone: ViewZone?  { zones.isEmpty ? nil : zones[safeIndex] }
    private var zoneColor:   Color      { color(for: currentZone?.name ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            timelineContent
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    // ── Header with zone name + prev/next buttons ─────────────────────────
    private var headerRow: some View {
        HStack {
            Text(currentZone?.name ?? "Program Boş")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            HStack(spacing: 16) {
                Button(intent: PreviousZonePageIntent()) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Button(intent: NextZonePageIntent()) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Per-hour rows with optional current-time indicator ────────────────
    @ViewBuilder
    private var timelineContent: some View {
        if let zone = currentZone, !zone.hours.isEmpty {
            let now         = Date()
            let currentHour = Calendar.current.component(.hour, from: now)
            let currentMin  = Calendar.current.component(.minute, from: now)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(zone.hours.prefix(5)), id: \.self) { hour in
                    let taskText = zone.tasks[hour]
                    let isPast   = hour < currentHour

                    HStack(spacing: 8) {
                        // Hour label
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(isPast ? zoneColor.opacity(0.35) : zoneColor)
                            .frame(width: 38, alignment: .trailing)

                        // Vertical divider
                        Rectangle()
                            .fill(isPast ? zoneColor.opacity(0.2) : zoneColor.opacity(0.65))
                            .frame(width: 2)

                        // Event title or empty-slot placeholder
                        if let title = taskText {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isPast ? .white.opacity(0.45) : .white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("·  ·  ·")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.15))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(height: 22)
                    .overlay(
                        GeometryReader { geo in
                            if hour == currentHour {
                                let y = (CGFloat(currentMin) / 60.0) * geo.size.height
                                HStack(spacing: 0) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(height: 1)
                                }
                                .offset(x: 43, y: y - 3)
                            }
                        }
                    )
                }
            }
        } else {
            Text("Aktif zone bulunamadı.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)
        }
    }

    private func color(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("sabah") || n.contains("morning") || n.contains("1") { return .cyan }
        if n.contains("öğle")  || n.contains("midday")  || n.contains("2") { return .orange }
        if n.contains("akşam") || n.contains("evening") || n.contains("3") { return .green }
        return .indigo
    }
}

// MARK: - WidgetCard

struct WidgetCard: View {
    let title:          String
    let value:          String
    let icon:           String
    let color:          Color
    var statusDotColor: Color? = nil   // non-nil only for the workout card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Card header: icon + label
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            // Value row: optional status dot + text
            HStack(spacing: 5) {
                if let dot = statusDotColor {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Widget Configuration

@main
struct MyBriefingWidget: Widget {
    let kind: String = "MyBriefingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                MyBriefingWidgetEntryView(entry: entry)
                    .containerBackground(Color(red: 0.1, green: 0.1, blue: 0.12), for: .widget)
            } else {
                MyBriefingWidgetEntryView(entry: entry)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            }
        }
        .configurationDisplayName("MyBriefing Dashboard")
        .description("Günlük özetin tek bakışta burada.")
        .supportedFamilies([.systemLarge])
    }
}
