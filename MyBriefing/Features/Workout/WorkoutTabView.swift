import SwiftUI

struct WorkoutTabView: View {
    @EnvironmentObject private var manager: WorkoutManager
    @EnvironmentObject private var calendar: CalendarManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    private let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    @State private var showFeedback = false
    @State private var feedbackMessage = ""
    @FocusState private var focusedRow: Int?
    @State private var showAddSplitAlert = false
    @State private var newSplitName = ""
    @State private var showDeleteConfirm = false

    private var shadowOpacity: Double { colorScheme == .dark ? 0.28 : 0.06 }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                (colorScheme == .dark
                    ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 200).ignoresSafeArea(edges: .top)
                VStack(spacing: 0) {

                VStack(spacing: 14) {
                    // HEADER: picker menu + add/delete button
                    HStack(alignment: .center, spacing: 0) {
                        Color.clear.frame(width: 42)
                        Spacer()

                        Menu {
                            ForEach(WorkoutMode.allCases.filter { $0 != .custom }) { mode in
                                Button(mode.rawValue) { manager.selectedSplitKey = mode.rawValue }
                            }
                            if !manager.customSplitNames.isEmpty {
                                Divider()
                                ForEach(manager.customSplitNames, id: \.self) { name in
                                    Button(name) { manager.selectedSplitKey = name }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(manager.currentDisplayName)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5), lineWidth: 1))
                            .shadow(color: Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.09), radius: 12, x: 0, y: 5)
                            .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
                        }

                        Spacer()

                        Button(action: {
                            if manager.isCustomSplit {
                                showDeleteConfirm = true
                            } else {
                                newSplitName = ""
                                showAddSplitAlert = true
                            }
                        }) {
                            Image(systemName: manager.isCustomSplit ? "trash" : "plus.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(manager.isCustomSplit ? .red : .accentColor)
                                .frame(width: 42, height: 42)
                                .background(manager.isCustomSplit ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    if !manager.selectedSplitKey.isEmpty {
                    Text("Tap text to edit · Long press to toggle Off Day")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)

                    VStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { idx in
                            dayRow(idx: idx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(.easeInOut(duration: 0.2), value: manager.selectedSplitKey)
                    }
                }

                if manager.selectedSplitKey.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.28))
                        Text("No Split Selected")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("Use the menu above to select\nor create a training split.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    Spacer()
                } else {
                    Spacer(minLength: 10)

                    HStack(spacing: 12) {
                        WorkoutActionButton(title: "Add to\nThis Week", color: .indigo, action: applyToCurrentWeek)
                        WorkoutActionButton(title: "Add to\nNext Week", color: .teal,   action: applyToNextWeek)
                        WorkoutActionButton(title: "Remove\nUpcoming",  color: .red,    action: resetFutureDays)
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 10)
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .addGlobalKeyboardDoneButton()
        }
        .onAppear {
            calendar.syncWorkoutsFromCalendar(into: manager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                calendar.syncWorkoutsFromCalendar(into: manager)
            }
        }
        .overlay(
            VStack {
                Spacer()
                if showFeedback {
                    Text(feedbackMessage)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.black.opacity(0.78))
                        .clipShape(Capsule())
                        .padding(.bottom, 120)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showFeedback)
        )
        .alert("New Split", isPresented: $showAddSplitAlert) {
            TextField("Split name", text: $newSplitName)
            Button("Create") { manager.addCustomSplit(name: newSplitName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for your new custom workout split.")
        }
        .confirmationDialog(
            "Delete \"\(manager.currentDisplayName)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Split", role: .destructive) { manager.deleteCurrentCustomSplit() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This split and all its data will be permanently removed.")
        }
    }

    // MARK: - Sub-views

    /// The calendar date for split day `idx` (0 = Mon) in the current week.
    private func thisWeekDate(for idx: Int) -> Date {
        let mon = monday(of: Date())
        return Calendar.current.date(byAdding: .day, value: idx, to: mon) ?? mon
    }

    @ViewBuilder
    private func dayRow(idx: Int) -> some View {
        let isOff       = manager.currentPlan().offDays.contains(idx)
        let isPostponed = manager.status(for: thisWeekDate(for: idx)) == .postpone

        HStack(spacing: 12) {
            Text(weekdayNames[idx])
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(width: 50, alignment: .leading)
                .foregroundColor(isOff ? .secondary : .primary)

            if isOff {
                Text("Off Day")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            } else if isPostponed {
                Text("Postponed")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                TextField("...", text: Binding(
                    get: { manager.currentPlan().days[idx] },
                    set: { manager.updateExercise(at: idx, to: $0) }
                ))
                .font(.system(size: 16, design: .rounded))
                .focused($focusedRow, equals: idx)
                .onSubmit { focusedRow = nil }

                let storedTime: Date? = manager.currentPlan().times.count > idx ? manager.currentPlan().times[idx] : nil
                if let t = storedTime {
                    DatePicker("", selection: Binding(
                        get: { t },
                        set: { manager.updateTime(at: idx, to: $0) }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .scaleEffect(0.82)
                    .frame(width: 78)
                    .clipped()
                    Button(action: { manager.updateTime(at: idx, to: nil) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        let t2 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
                        manager.updateTime(at: idx, to: t2)
                    }) {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary.opacity(0.45))
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)                 // Fixed height — same for every row state
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.45), lineWidth: 1))
        .shadow(color: Color.accentColor.opacity(isOff ? 0 : (colorScheme == .dark ? 0.14 : 0.07)), radius: 8, x: 0, y: 4)
        .opacity(isOff ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                manager.toggleOffDay(at: idx)
            }
        )
    }

    // MARK: - Actions

    /// Returns the Monday of the week containing `date` (firstWeekday = Monday).
    private func monday(of date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today   = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: today) // 1=Sun, 2=Mon … 7=Sat
        // Distance back to Monday: Mon→0, Tue→1, …, Sun→6
        let daysBack = weekday == 1 ? 6 : weekday - 2
        return cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func applyToCurrentWeek() {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        let mon   = monday(of: Date())
        // Apply from today through Sunday — never overwrite past days
        let dates = (0..<7)
            .compactMap { cal.date(byAdding: .day, value: $0, to: mon) }
            .filter { cal.startOfDay(for: $0) >= today }
        applyLabelsAndSyncCalendar(for: dates)
        NotificationCenter.default.post(name: Notification.Name("ForceHomeRefresh"), object: nil)
        showSuccessMessage("Added to this week!")
    }

    private func applyToNextWeek() {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let mon      = monday(of: Date())
        guard let nextMon = cal.date(byAdding: .day, value: 7, to: mon) else { return }
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: nextMon) }
        applyLabelsAndSyncCalendar(for: dates)
        NotificationCenter.default.post(name: Notification.Name("ForceHomeRefresh"), object: nil)
        showSuccessMessage("Added to next week!")
    }

    private func resetFutureDays() {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }

        manager.nukeUpcoming(from: tomorrow)
        calendar.deleteAllFutureWorkoutEvents(from: tomorrow)

        NotificationCenter.default.post(name: Notification.Name("ForceHomeRefresh"), object: nil)
        showSuccessMessage("Upcoming workouts removed!")
    }

    private func applyLabelsAndSyncCalendar(for dates: [Date]) {
        manager.scheduleRange(dates)
        for date in dates {
            let label = manager.exerciseLabel(for: date)
            if label.isEmpty {
                calendar.deleteWorkoutEvent(for: date)
            } else {
                calendar.upsertWorkoutEvent(
                    for: date,
                    label: label,
                    startTime: manager.plannedTime(for: date)
                )
            }
        }
    }

    private func showSuccessMessage(_ text: String) {
        feedbackMessage = text
        withAnimation { showFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showFeedback = false }
        }
    }
}

private struct WorkoutActionButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)          // Fixed height — same for all three
                .background(
                    LinearGradient(
                        colors: [color, color.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: color.opacity(0.45), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
