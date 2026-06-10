import SwiftUI

struct SleepDetailsSheet: View {
    @ObservedObject var health: HealthManager

    private var hasStageData: Bool {
        health.deepMinutes > 0 || health.remMinutes > 0 || health.coreMinutes > 0
    }

    private var scoreColor: Color {
        let n = max(0.0, min(100.0, health.sleepScore)) / 100.0
        return Color(hue: n * 0.33, saturation: 0.85, brightness: 0.9)
    }

    private var scoreLabel: String {
        switch health.sleepScore {
        case 85...: return "Excellent"
        case 70..<85: return "Good"
        case 55..<70: return "Fair"
        case 40..<55: return "Poor"
        default:      return "Very Poor"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // SCORE HEADER
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    Circle().trim(from: 0.0, to: CGFloat(health.sleepScore) / 100.0)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(health.sleepScore > 0 ? "\(Int(ceil(health.sleepScore)))" : "-")
                            .font(.system(size: 28, weight: .heavy))
                        Text("/ 100").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Sleep Analysis").font(.system(size: 22, weight: .heavy))
                    HStack(spacing: 6) {
                        Text("🌙").font(.system(size: 18))
                        Text(health.sleepDuration).font(.system(size: 17, weight: .semibold)).foregroundColor(.secondary)
                    }
                    Text(scoreLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(scoreColor)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 20)

            Divider().padding(.horizontal, 16)

            // STAGE TILES
            if hasStageData {
                HStack(spacing: 10) {
                    stageTile(title: "Deep", icon: "moon.zzz.fill",
                              minutes: health.deepMinutes, percent: health.deepPercent,
                              color: .blue)
                    stageTile(title: "REM", icon: "waveform.path.ecg",
                              minutes: health.remMinutes,  percent: health.remPercent,
                              color: .purple)
                    stageTile(title: "Core", icon: "moon.fill",
                              minutes: health.coreMinutes, percent: health.corePercent,
                              color: .teal)
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            } else {
                Text("Stage breakdown requires Apple Watch data.")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.vertical, 20)
            }

            Divider().padding(.horizontal, 16)

            // METHODOLOGY
            VStack(alignment: .leading, spacing: 8) {
                Text("How the score is calculated").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                scoreRow(label: "Duration",   pts: "40 pt", detail: "Target 8 h · ±7 pt/h from ideal")
                scoreRow(label: "Deep sleep", pts: "25 pt", detail: "Ideal 13–23 % · physical recovery")
                scoreRow(label: "REM sleep",  pts: "25 pt", detail: "Ideal 18–25 % · memory & mood")
                scoreRow(label: "Balance",    pts: "10 pt", detail: "Core sleep 45–65 % of total")
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground).cornerRadius(14))
            .padding(.horizontal, 16).padding(.top, 14)

            Spacer()
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func stageTile(title: String, icon: String, minutes: Int, percent: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(color)
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
            Text(formattedMinutes(minutes)).font(.system(size: 16, weight: .heavy))
            Text(minutes > 0 ? String(format: "%.0f%%", percent) : "—")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.1))
        .cornerRadius(14)
    }

    @ViewBuilder
    private func scoreRow(label: String, pts: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(pts)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
