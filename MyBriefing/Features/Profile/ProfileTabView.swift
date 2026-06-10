import SwiftUI
import EventKit

struct ProfileTabView: View {
    @EnvironmentObject var zoneSettings: ZoneSettingsManager
    @AppStorage("appTheme") private var appTheme: Int = 0
    @AppStorage("streakFreezeDays") private var streakFreezeDays: Int = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                (colorScheme == .dark
                    ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 200).ignoresSafeArea(edges: .top)

                Form {
                    // ── Profile header ─────────────────────────────────
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(
                                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.6)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(UIDevice.current.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text("MyBriefing")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    // ── Appearance ─────────────────────────────────────
                    Section("Appearance") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("App Theme", systemImage: "circle.lefthalf.filled")
                                .font(.system(size: 15))
                            Picker("App Theme", selection: $appTheme) {
                                Text("System").tag(0)
                                Text("Light").tag(1)
                                Text("Dark").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)

                        Toggle("Show zone background text", isOn: $zoneSettings.showZoneWatermarks)
                        Toggle("Add pattern to gap periods", isOn: $zoneSettings.zoneGapEnabled)
                    }

                    // ── Streak ─────────────────────────────────────────────
                    Section("Streak") {
                        HStack(spacing: 12) {
                            Label("Freeze Days", systemImage: "snowflake")
                                .font(.system(size: 15))
                            Spacer()
                            Picker("", selection: $streakFreezeDays) {
                                ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }

                    // ── Quick Picks (NavigationLink — complex add/delete UI) ──
                    Section {
                        NavigationLink(destination: ManageQuickPicksView()) {
                            Label("Manage Quick Picks", systemImage: "list.star")
                                .font(.system(size: 15))
                        }
                    }

                    // ── Advanced ───────────────────────────────────────
                    Section {
                        NavigationLink(destination: AdvancedSettingsView()) {
                            Label("Advanced", systemImage: "gearshape.fill")
                                .font(.system(size: 15))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    ProfileTabView()
        .environmentObject(ZoneSettingsManager())
        .environmentObject(QuickPickStore())
}
