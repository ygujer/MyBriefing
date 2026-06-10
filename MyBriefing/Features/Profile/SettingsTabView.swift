import SwiftUI
import EventKit

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("mealCalendarIdentifier") private var mealCalendarIdentifier: String = ""
    @AppStorage("workoutCalendarIdentifier") private var workoutCalendarIdentifier: String = ""
    @EnvironmentObject private var calendarManager: CalendarManager

    var body: some View {
        Form {
            Section("Manage Calendars") {
                // Workout Calendar
                VStack(alignment: .leading, spacing: 6) {
                    Label("Workout Calendar", systemImage: "dumbbell")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        if let sel = calendarManager.writableCalendars.first(where: { $0.calendarIdentifier == workoutCalendarIdentifier }) {
                            Circle().fill(Color(cgColor: sel.cgColor)).frame(width: 10, height: 10)
                        }
                        Picker("", selection: $workoutCalendarIdentifier) {
                            Text("Default Calendar").tag("")
                            ForEach(calendarManager.writableCalendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().tint(.accentColor)
                    }
                }
                .padding(.vertical, 3)

                // Meal Calendar
                VStack(alignment: .leading, spacing: 6) {
                    Label("Meal Target Calendar", systemImage: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        if let sel = calendarManager.writableCalendars.first(where: { $0.calendarIdentifier == mealCalendarIdentifier }) {
                            Circle().fill(Color(cgColor: sel.cgColor)).frame(width: 10, height: 10)
                        }
                        Picker("", selection: $mealCalendarIdentifier) {
                            Text("Default Calendar").tag("")
                            ForEach(calendarManager.writableCalendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().tint(.accentColor)
                    }
                }
                .padding(.vertical, 3)

                NavigationLink(destination: CalendarsSettingsView()) {
                    Label("Enabled Calendars", systemImage: "calendar.badge.checkmark")
                        .font(.system(size: 15))
                }
            }

            Section {
                NavigationLink(destination: ZonesSettingsView()) {
                    Label("Zones", systemImage: "clock.fill")
                        .font(.system(size: 15))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { calendarManager.loadWritableCalendars() }
    }
}

// MARK: - Manage Quick Picks

struct ManageQuickPicksView: View {
    @EnvironmentObject var quickPickStore: QuickPickStore
    @State private var newName = ""
    @State private var newCategory: QuickPickCategory = .breakfast

    private var breakfastPicks: [QuickPickMeal] { quickPickStore.meals.filter { $0.category == .breakfast } }
    private var dinnerPicks: [QuickPickMeal]    { quickPickStore.meals.filter { $0.category == .dinner } }

    var body: some View {
        Form {
            Section("New Quick Pick") {
                TextField("Meal name", text: $newName)

                Picker("Category", selection: $newCategory) {
                    ForEach(QuickPickCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Button(action: addMeal) {
                    Label("Add Quick Pick", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !breakfastPicks.isEmpty {
                Section {
                    ForEach(breakfastPicks) { pick in
                        Text(pick.name).font(.system(size: 15, design: .rounded))
                    }
                    .onDelete { delete(from: breakfastPicks, at: $0) }
                } header: {
                    Label("Breakfast", systemImage: "sun.rise.fill").foregroundColor(.orange)
                }
            }

            if !dinnerPicks.isEmpty {
                Section {
                    ForEach(dinnerPicks) { pick in
                        Text(pick.name).font(.system(size: 15, design: .rounded))
                    }
                    .onDelete { delete(from: dinnerPicks, at: $0) }
                } header: {
                    Label("Dinner", systemImage: "moon.stars.fill").foregroundColor(.indigo)
                }
            }

            if breakfastPicks.isEmpty && dinnerPicks.isEmpty {
                Section {
                    Text("No quick picks yet. Add your first one above.")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, design: .rounded))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Quick Picks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
    }

    private func addMeal() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        quickPickStore.add(QuickPickMeal(name: name, category: newCategory))
        newName = ""
    }

    private func delete(from picks: [QuickPickMeal], at offsets: IndexSet) {
        let ids = offsets.map { picks[$0].id }
        quickPickStore.meals.removeAll { ids.contains($0.id) }
    }
}

// MARK: - Zones

struct ZonesSettingsView: View {
    @EnvironmentObject var zoneSettings: ZoneSettingsManager

    var body: some View {
        Form {
            Section("Time Zones") {
                zoneRow(title: $zoneSettings.z1Name, isEnabled: $zoneSettings.z1Enabled,
                        start: $zoneSettings.z1Start, end: $zoneSettings.z1End)
                zoneRow(title: $zoneSettings.z2Name, isEnabled: $zoneSettings.z2Enabled,
                        start: $zoneSettings.z2Start, end: $zoneSettings.z2End)
                zoneRow(title: $zoneSettings.z3Name, isEnabled: $zoneSettings.z3Enabled,
                        start: $zoneSettings.z3Start, end: $zoneSettings.z3End)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Zones")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func zoneRow(title: Binding<String>, isEnabled: Binding<Bool>, start: Binding<Int>, end: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Button(action: { isEnabled.wrappedValue.toggle() }) {
                Image(systemName: isEnabled.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled.wrappedValue ? .accentColor : .gray)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)

            TextField("Name", text: title)
                .font(.system(size: 15, weight: .semibold))
                .minimumScaleFactor(0.6).lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Text("From").font(.system(size: 11)).foregroundColor(.secondary).fixedSize()
                Picker("", selection: start) {
                    ForEach(0...23, id: \.self) { Text(String(format: "%d:00", $0)).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                Text("to").font(.system(size: 11)).foregroundColor(.secondary).fixedSize()
                Picker("", selection: end) {
                    ForEach(0...23, id: \.self) { Text(String(format: "%d:00", $0)).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Calendars

struct CalendarsSettingsView: View {
    @EnvironmentObject private var calendarManager: CalendarManager
    @State private var groupedCalendars: [(EKSource, [EKCalendar])] = []
    @State private var disabledIDs: [String] = []
    @State private var expandedGroups: Set<String> = []
    @State private var refreshRotation: Double = 0

    var body: some View {
        Form {
            Section(header: HStack {
                Text("Enabled Calendars")
                Spacer()
                Button(action: {
                    withAnimation(.linear(duration: 0.5)) { refreshRotation += 360 }
                    loadCalendars()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(refreshRotation))
                }
                .buttonStyle(.plain).foregroundColor(.accentColor)
            }) {
                ForEach(groupedCalendars, id: \.0.sourceIdentifier) { source, calendars in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(source.sourceIdentifier) },
                            set: { if $0 { expandedGroups.insert(source.sourceIdentifier) } else { expandedGroups.remove(source.sourceIdentifier) } }
                        )
                    ) {
                        ForEach(calendars, id: \.calendarIdentifier) { cal in
                            Toggle(cal.title, isOn: calendarBinding(for: cal))
                                .toggleStyle(SwitchToggleStyle(tint: Color(cgColor: cal.cgColor)))
                        }
                    } label: {
                        HStack {
                            Text(source.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isGroupEnabled(calendars: calendars) },
                                set: { _ in toggleGroup(calendars: calendars) }
                            )).labelsHidden()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCalendars() }
    }

    private func calendarBinding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !disabledIDs.contains(cal.calendarIdentifier) },
            set: { enabled in
                if enabled { disabledIDs.removeAll { $0 == cal.calendarIdentifier } }
                else if !disabledIDs.contains(cal.calendarIdentifier) { disabledIDs.append(cal.calendarIdentifier) }
                saveDisabledIDs()
            }
        )
    }

    private func loadCalendars() {
        calendarManager.loadWritableCalendars()
        let store = EKEventStore()
        let grouped = Dictionary(grouping: store.calendars(for: .event), by: { $0.source })
        groupedCalendars = grouped.compactMap { source, cals -> (EKSource, [EKCalendar])? in
            guard let source else { return nil }
            return (source, cals)
        }.sorted { $0.0.title < $1.0.title }
        let raw = UserDefaults.standard.string(forKey: "disabledCalendarIDs") ?? ""
        disabledIDs = raw.components(separatedBy: ",")
    }

    private func isGroupEnabled(calendars: [EKCalendar]) -> Bool {
        calendars.contains { !disabledIDs.contains($0.calendarIdentifier) }
    }

    private func toggleGroup(calendars: [EKCalendar]) {
        let enabled = isGroupEnabled(calendars: calendars)
        for cal in calendars {
            if enabled { if !disabledIDs.contains(cal.calendarIdentifier) { disabledIDs.append(cal.calendarIdentifier) } }
            else { disabledIDs.removeAll { $0 == cal.calendarIdentifier } }
        }
        saveDisabledIDs()
    }

    private func saveDisabledIDs() {
        UserDefaults.standard.set(disabledIDs.joined(separator: ","), forKey: "disabledCalendarIDs")
        NotificationCenter.default.post(name: Notification.Name("CalendarsUpdated"), object: nil)
    }
}
