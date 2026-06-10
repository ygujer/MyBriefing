import SwiftUI
import HealthKit
import EventKit
import Combine

struct HomeView: View {
    @StateObject private var health = HealthManager()
    @StateObject private var dataManager = DayDataManager()
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var workout: WorkoutManager
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentDate = Date()
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM EEEE"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }

    @State private var editingRestDay = false
    @State private var dragDirection: Edge = .trailing
    @State private var showSleepDetails = false
    @State private var showMoodSlider = false

    @FocusState private var isRestDayFocused: Bool

    @State private var currentHour = Calendar.current.component(.hour, from: Date())
    @State private var currentMinute = Calendar.current.component(.minute, from: Date())
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var zoneSelection: Int = 0
    @State private var mealSyncTasks: [Int: Task<Void, Never>] = [:]

    @EnvironmentObject private var zoneSettings: ZoneSettingsManager

    private var shadowOpacity: Double { colorScheme == .dark ? 0.28 : 0.06 }
    private var isDateInToday: Bool { Calendar.current.isDateInToday(currentDate) }
    private var isDateInFuture: Bool { Calendar.current.startOfDay(for: currentDate) > Calendar.current.startOfDay(for: Date()) }
    private var sleepScoreText: String { health.sleepScore > 0 ? "\(Int(health.sleepScore.rounded(.up)))" : "-" }

    // Gradient background
    private var topGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom)
    }
    // Card glass border
    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55), lineWidth: 1)
    }
    // Premium card shadow
    private var cardShadowColor: Color { Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.09) }

    // Header helpers
    private var headerDayText: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: currentDate)
    }
    private var headerMonthWeekdayText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM • EEEE"
        return f.string(from: currentDate).uppercased()
    }
    private var headerGradient: LinearGradient {
        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                topGradient
                    .frame(height: 340)
                    .ignoresSafeArea(edges: .top)
                VStack(spacing: 14) {
                // HEADER
                HStack(spacing: 16) {
                    // Left chevron — gradient circle
                    Button(action: { swipeDate(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(headerGradient)
                            .clipShape(Circle())
                            .shadow(color: Color.accentColor.opacity(0.45), radius: 8, x: 0, y: 4)
                    }
                    Spacer()
                    // Massive date block
                    VStack(spacing: 0) {
                        Text(headerMonthWeekdayText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)
                        Text(headerDayText)
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(isDateInToday
                                ? LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.primary, Color.primary.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    Spacer()
                    // Right chevron — gradient circle
                    Button(action: { swipeDate(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(headerGradient)
                            .clipShape(Circle())
                            .shadow(color: Color.accentColor.opacity(0.45), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)

                VStack(spacing: 12) {
                    // SLEEP & MOOD
                    HStack(spacing: 12) {
                        // Sleep card
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 10) {
                                Text("🌙").font(.system(size: 28))
                                Text(health.sleepDuration)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Spacer(minLength: 0)
                            ZStack {
                                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
                                Circle().trim(from: 0.0, to: CGFloat(health.sleepScore) / 100.0)
                                    .stroke(scoreColor(score: health.sleepScore), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text(sleepScoreText)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }.frame(width: 56, height: 56)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(glassBorder)
                        .shadow(color: cardShadowColor, radius: 14, x: 0, y: 6)
                        .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
                        .onTapGesture { showSleepDetails = true }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            if let url = URL(string: "x-apple-health://SleepHealthAppPlugin.healthplugin") { openURL(url) }
                        }

                        // Mood card
                        moodCard()
                    }
                    .padding(.horizontal, 16)

                    // FOOD CARD
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FOOD")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .tracking(1.5)
                        ForEach(dataManager.currentDayData.meals.indices, id: \.self) { idx in
                            if idx < dataManager.currentDayData.meals.count {
                                if idx > 0 { Divider() }
                                HStack(spacing: 6) {
                                    Text("\(dataManager.currentDayData.meals[idx].type):")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("", text: Binding(
                                        get: {
                                            guard idx < dataManager.currentDayData.meals.count else { return "" }
                                            return dataManager.currentDayData.meals[idx].name
                                        },
                                        set: {
                                            guard idx < dataManager.currentDayData.meals.count else { return }
                                            dataManager.currentDayData.meals[idx].name = $0
                                            dataManager.saveData(for: currentDate)
                                            scheduleMealSync(for: idx)
                                        }
                                    ))
                                    .font(.system(size: 15, design: .rounded))
                                    Spacer(minLength: 0)
                                    DatePicker("", selection: mealTimeBinding(for: idx), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .scaleEffect(0.82)
                                        .frame(width: 80)
                                        .clipped()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(glassBorder)
                    .shadow(color: cardShadowColor, radius: 14, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)

                    // WORKOUT CARD
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WORKOUT")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .tracking(1.5)

                        let label    = workout.exerciseLabel(for: currentDate)
                        let wStatus  = workout.status(for: currentDate)
                        let isOffDay = label.isEmpty

                        HStack {
                            if isOffDay {
                                if editingRestDay {
                                    TextField("", text: Binding(
                                        get: { workout.entry(for: currentDate)?.labelOverride ?? "" },
                                        set: { v in workout.setLabelOverride(v.isEmpty ? nil : v, for: currentDate) }
                                    ))
                                    .font(.system(size: 16, design: .rounded))
                                    .keyboardType(.default)
                                    .focused($isRestDayFocused)
                                    .onAppear { isRestDayFocused = true }
                                    .onSubmit { editingRestDay = false }
                                } else if let ov = workout.entry(for: currentDate)?.labelOverride, !ov.isEmpty {
                                    Text(ov)
                                        .font(.system(size: 16, design: .rounded))
                                        .onTapGesture { editingRestDay = true }
                                    Spacer()
                                } else {
                                    Text("Rest Day")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .italic()
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                        .onTapGesture { editingRestDay = true }
                                    Spacer()
                                }
                            } else {
                                HStack(spacing: 6) {
                                    if wStatus == .postpone {
                                        Text("Postponed")
                                            .font(.system(size: 16, weight: .medium, design: .serif))
                                            .italic()
                                            .foregroundColor(.secondary)
                                    } else {
                                        TextField("...", text: Binding(
                                            get: { label },
                                            set: { v in workout.setLabelOverride(v.isEmpty ? nil : v, for: currentDate) }
                                        ))
                                        .font(.system(size: 16, design: .rounded))
                                        .minimumScaleFactor(0.4)
                                        .lineLimit(1)
                                    }

                                    Spacer()

                                    if wStatus != .postpone {
                                        DatePicker("", selection: workoutTimeBinding, displayedComponents: .hourAndMinute)
                                            .labelsHidden()
                                            .scaleEffect(0.82)
                                            .frame(width: 80)
                                            .clipped()
                                    }

                                    HStack(spacing: 8) {
                                        // DONE — tap to activate, long-press to revert
                                        WorkoutStatusButton(
                                            systemImage: "checkmark",
                                            isActive: wStatus == .done,
                                            activeGradient: LinearGradient(
                                                colors: [Color(red: 0.18, green: 0.8, blue: 0.42), Color(red: 0.05, green: 0.6, blue: 0.28)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                            shadowColor: Color.green.opacity(0.5),
                                            action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    let doneTime = workout.markDone(for: currentDate)
                                                    calendar.upsertWorkoutEvent(for: currentDate, label: label, startTime: doneTime)
                                                }
                                            },
                                            deactivateAction: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    workout.resetToNeutral(for: currentDate)
                                                    calendar.deleteWorkoutEvent(for: currentDate)
                                                }
                                            }
                                        )

                                        // NOT DONE — tap to activate, long-press to revert
                                        WorkoutStatusButton(
                                            systemImage: "minus",
                                            isActive: wStatus == .notDone,
                                            activeGradient: LinearGradient(
                                                colors: [Color(red: 0.95, green: 0.28, blue: 0.28), Color(red: 0.75, green: 0.1, blue: 0.1)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                            shadowColor: Color.red.opacity(0.5),
                                            action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    workout.markNotDone(for: currentDate)
                                                    calendar.deleteWorkoutEvent(for: currentDate)
                                                }
                                            },
                                            deactivateAction: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    workout.resetToNeutral(for: currentDate)
                                                }
                                            }
                                        )

                                        // POSTPONE — tap to activate, long-press to revert
                                        WorkoutStatusButton(
                                            systemImage: "arrow.right",
                                            isActive: wStatus == .postpone,
                                            activeGradient: LinearGradient(
                                                colors: [Color(red: 1.0, green: 0.62, blue: 0.1), Color(red: 0.85, green: 0.42, blue: 0.0)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing),
                                            shadowColor: Color.orange.opacity(0.5),
                                            action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    workout.postpone(from: currentDate)
                                                    calendar.deleteWorkoutEvent(for: currentDate)
                                                    if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) {
                                                        let tLabel = workout.exerciseLabel(for: tomorrow)
                                                        if !tLabel.isEmpty {
                                                            calendar.upsertWorkoutEvent(for: tomorrow, label: tLabel, startTime: workout.plannedTime(for: tomorrow))
                                                        }
                                                    }
                                                }
                                            },
                                            deactivateAction: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                                    workout.undoPostpone(from: currentDate)
                                                    let restoredLabel = workout.exerciseLabel(for: currentDate)
                                                    if !restoredLabel.isEmpty {
                                                        calendar.upsertWorkoutEvent(for: currentDate, label: restoredLabel, startTime: workout.plannedTime(for: currentDate))
                                                    }
                                                    if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) {
                                                        let tLabel = workout.exerciseLabel(for: tomorrow)
                                                        if tLabel.isEmpty {
                                                            calendar.deleteWorkoutEvent(for: tomorrow)
                                                        } else {
                                                            calendar.upsertWorkoutEvent(for: tomorrow, label: tLabel, startTime: workout.plannedTime(for: tomorrow))
                                                        }
                                                    }
                                                }
                                            }
                                        )
                                    }
                                    .id(currentDate)
                                    .disabled(isDateInFuture)
                                    .opacity(isDateInFuture ? 0.3 : 1.0)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(glassBorder)
                    .shadow(color: cardShadowColor, radius: 14, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)

                    // ZONE CARD
                    TabView(selection: $zoneSelection) {
                        if zoneSettings.z1Enabled && zoneSettings.z1Start <= zoneSettings.z1End { zoneColumn(title: zoneSettings.z1Name, hours: Array(zoneSettings.z1Start...zoneSettings.z1End)).tag(0) }
                        if zoneSettings.z2Enabled && zoneSettings.z2Start <= zoneSettings.z2End { zoneColumn(title: zoneSettings.z2Name, hours: Array(zoneSettings.z2Start...zoneSettings.z2End)).tag(1) }
                        if zoneSettings.z3Enabled && zoneSettings.z3Start <= zoneSettings.z3End { zoneColumn(title: zoneSettings.z3Name, hours: Array(zoneSettings.z3Start...zoneSettings.z3End)).tag(2) }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(glassBorder)
                    .shadow(color: cardShadowColor, radius: 14, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .id(currentDate)
                .transition(.push(from: dragDirection))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .center) {
                if showMoodSlider { moodPopupOverlay }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let h = value.translation.width
                        let v = value.translation.height
                        guard abs(h) > abs(v) else { return }
                        if h < -50 { swipeDate(by: 1) }
                        else if h > 50 { swipeDate(by: -1) }
                    }
            )
            .addGlobalKeyboardDoneButton()
        }
        .onAppear { refreshAllData() }
        .task { await health.start(); refreshAllData() }
        .onReceive(timer) { now in
            currentHour = Calendar.current.component(.hour, from: now)
            currentMinute = Calendar.current.component(.minute, from: now)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ForceHomeRefresh"))) { _ in
            refreshAllData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarsUpdated"))) { _ in
            calendar.loadEvents(for: currentDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetHomeToToday)) { _ in
            let today = Calendar.current.startOfDay(for: Date())
            editingRestDay = false
            let offset = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: currentDate), to: today).day ?? 0
            if offset != 0 {
                dragDirection = offset > 0 ? .trailing : .leading
                withAnimation(.easeInOut(duration: 0.2)) { currentDate = today }
            } else {
                currentDate = today
            }
            refreshAllData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabActivated)) { _ in
            calendar.loadEvents(for: currentDate)
        }
        .onChange(of: calendar.events) { _, newEvents in
            guard let d = calendar.lastLoadedDate,
                  Calendar.current.isDate(d, inSameDayAs: currentDate) else { return }
            parseFoodFromEvents(newEvents)
            parseWorkoutFromEvents(newEvents)
        }
        .onChange(of: isRestDayFocused) { _, focused in
            if !focused { editingRestDay = false }
        }
        .sheet(isPresented: $showSleepDetails) {
            SleepDetailsSheet(health: health)
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func refreshAllData() {
        dataManager.loadData(for: currentDate)
        calendar.loadEvents(for: currentDate)
        health.fetchSleepData(for: currentDate)
        if Calendar.current.isDateInToday(currentDate) {
            zoneSelection = zoneIndexForCurrentHour()
        }
        // ⚠️ Do NOT call upsertWorkoutEvent here. Calendar writes happen only on explicit
        // user action (button taps). Passive refreshes must never overwrite calendar edits.
    }

    private func zoneIndexForCurrentHour() -> Int {
        let h = Calendar.current.component(.hour, from: Date())
        if zoneSettings.z1Enabled && h >= zoneSettings.z1Start && h <= zoneSettings.z1End { return 0 }
        if zoneSettings.z2Enabled && h >= zoneSettings.z2Start && h <= zoneSettings.z2End { return 1 }
        if zoneSettings.z3Enabled && h >= zoneSettings.z3Start && h <= zoneSettings.z3End { return 2 }
        if h < (zoneSettings.z1Enabled ? zoneSettings.z1Start : 24) { return 0 }
        if h < (zoneSettings.z2Enabled ? zoneSettings.z2Start : 24) { return zoneSettings.z1Enabled ? 0 : 1 }
        return zoneSettings.z3Enabled ? 2 : (zoneSettings.z2Enabled ? 1 : 0)
    }

    private func mealTimeBinding(for idx: Int) -> Binding<Date> {
        Binding(
            get: {
                guard idx < dataManager.currentDayData.meals.count else { return Date() }
                let meal = dataManager.currentDayData.meals[idx]
                if let t = meal.mealTime { return t }
                let h = meal.type == "Breakfast" ? 12 : 18
                return Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: currentDate) ?? Date()
            },
            set: { newTime in
                guard idx < dataManager.currentDayData.meals.count else { return }
                dataManager.currentDayData.meals[idx].mealTime = newTime
                dataManager.saveData(for: currentDate)
                scheduleMealSync(for: idx)
            }
        )
    }

    private var workoutTimeBinding: Binding<Date> {
        Binding(
            get: {
                let e = workout.entry(for: currentDate)
                if e?.status == .done, let t = e?.completedAt { return t }
                return workout.plannedTime(for: currentDate)
            },
            set: { newTime in
                let wStatus = workout.status(for: currentDate)
                if wStatus == .done {
                    workout.setCompletedTime(newTime, for: currentDate)
                } else {
                    workout.setPlannedTimeOverride(newTime, for: currentDate)
                }
                let label = workout.exerciseLabel(for: currentDate)
                if !label.isEmpty, wStatus != .notDone, wStatus != .postpone {
                    calendar.upsertWorkoutEvent(for: currentDate, label: label, startTime: newTime)
                }
            }
        )
    }

    func scoreColor(score: Double) -> Color {
        let normalized = max(0.0, min(100.0, score)) / 100.0
        return Color(hue: normalized * 0.33, saturation: 0.85, brightness: 0.9)
    }

    @ViewBuilder
    private func moodCard() -> some View {
        let val = dataManager.currentDayData.mood
        VStack(alignment: .center, spacing: 6) {
            Text("MOOD")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(1.5)
            Text(val > 0 ? "\(moodEmoji(for: val)) \(val)" : "—")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: 116)
        .frame(minHeight: 90)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: cardShadowColor, radius: 14, x: 0, y: 6)
        .shadow(color: Color.black.opacity(shadowOpacity * 0.4), radius: 4, x: 0, y: 2)
        .onTapGesture { withAnimation(.snappy) { showMoodSlider = true } }
    }

    @ViewBuilder
    private var moodPopupOverlay: some View {
        let val = dataManager.currentDayData.mood
        ZStack {
            // Dimmed blurred backdrop — tap outside to dismiss
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { showMoodSlider = false } }

            // Popup card
            VStack(spacing: 20) {
                Text("HOW ARE YOU FEELING?")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                Text(val > 0 ? "\(moodEmoji(for: val)) \(val)" : "—")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: val)

                Slider(
                    value: Binding(
                        get: { Double(val > 0 ? val : 5) },
                        set: { v in
                            dataManager.currentDayData.mood = Int(v.rounded())
                            dataManager.saveData(for: currentDate)
                        }
                    ),
                    in: 1...10,
                    step: 1
                )
                .tint(.accentColor)

                HStack(spacing: 0) {
                    ForEach(1...10, id: \.self) { i in
                        Text("\(i)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .offset(y: -12)

                Button(action: { withAnimation(.snappy) { showMoodSlider = false } }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.6), lineWidth: 1)
            )
            .shadow(color: Color.accentColor.opacity(0.25), radius: 40, x: 0, y: 20)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    @ViewBuilder
    func zoneColumn(title: String, hours: [Int]) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.bottom, 14)
            ForEach(hours, id: \.self) { hour in
                hourRow(hour: hour).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    func hourRow(hour: Int) -> some View {
        let hourEvents = calendar.events.filter { event in
            guard !event.isAllDay else { return false }
            let cal = Calendar.current
            let startH = cal.component(.hour, from: event.startDate)
            // Events ending at midnight next day (e.g. 23:00–00:00) must show in hour 23
            let crossesMidnight = !cal.isDate(event.startDate, inSameDayAs: event.endDate)
            if crossesMidnight { return hour >= startH }
            let endH = cal.component(.hour, from: event.endDate)
            let endM = cal.component(.minute, from: event.endDate)
            let adjustedEndH = (endM == 0 && endH > startH) ? endH - 1 : endH
            return hour >= startH && hour <= adjustedEndH
        }

        return ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                Divider()
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                if hour == currentHour {
                    HStack(spacing: 0) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Rectangle().fill(Color.red).frame(height: 1.5)
                    }
                    .offset(y: CGFloat(currentMinute) / 60.0 * geo.size.height)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                Text(String(format: "%d:00", hour))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(.gray)
                    .frame(width: 44, alignment: .trailing)
                if !hourEvents.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(hourEvents.enumerated()), id: \.element.eventIdentifier) { index, event in
                            if index > 0 {
                                Text("|")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                            Text(event.title ?? "")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(cgColor: event.calendar.cgColor))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func parseFoodFromEvents(_ events: [EKEvent]) {
        var anyChanged = false
        for event in events {
            guard let title = event.title?.lowercased(), let fullTitle = event.title else { continue }
            let parts = fullTitle.components(separatedBy: "-")
            guard parts.count > 1 else { continue }
            let value = parts[1...].joined(separator: "-").trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, let eventStart: Date = event.startDate else { continue }

            let mealType: String
            if title.hasPrefix("kahvaltı -") || title.hasPrefix("kahvaltı-") { mealType = "breakfast" }
            else if title.hasPrefix("yemek -") || title.hasPrefix("yemek-") { mealType = "dinner" }
            else { continue }

            guard let idx = dataManager.currentDayData.meals.firstIndex(where: { $0.type.lowercased() == mealType }) else { continue }

            // Two-way name sync: update app whenever calendar name differs (no write-back to avoid loops)
            if dataManager.currentDayData.meals[idx].name != value {
                dataManager.currentDayData.meals[idx].name = value
                anyChanged = true
            }
            // Two-way time sync: update when calendar event was moved (>60s threshold prevents loops)
            if let stored = dataManager.currentDayData.meals[idx].mealTime {
                if abs(stored.timeIntervalSince(eventStart)) > 60 {
                    dataManager.currentDayData.meals[idx].mealTime = eventStart
                    anyChanged = true
                }
            } else {
                dataManager.currentDayData.meals[idx].mealTime = eventStart
                anyChanged = true
            }
        }
        if anyChanged { dataManager.saveData(for: currentDate) }
    }

    private func parseWorkoutFromEvents(_ events: [EKEvent]) {
        guard let event = events.first(where: { calendar.isAppWorkoutEvent($0) }),
              let eventStart: Date = event.startDate else { return }

        let wStatus = workout.status(for: currentDate)

        // Two-way label sync: update labelOverride only when calendar label differs from both
        // the split-scheduled name and the current override (prevents write-back loops)
        if let calLabel = calendar.workoutLabelFromEvent(event), !calLabel.isEmpty {
            let scheduled = workout.exerciseLabel(for: currentDate)
            let currentOverride = workout.entry(for: currentDate)?.labelOverride
            if calLabel != scheduled && calLabel != currentOverride {
                workout.setLabelOverride(calLabel, for: currentDate)
            }
        }

        // Two-way time sync (60s threshold prevents loops)
        switch wStatus {
        case .neutral:
            let planned = workout.plannedTime(for: currentDate)
            if abs(planned.timeIntervalSince(eventStart)) > 60 {
                workout.setPlannedTimeOverride(eventStart, for: currentDate)
            }
        case .done:
            if let completedAt = workout.entry(for: currentDate)?.completedAt,
               abs(completedAt.timeIntervalSince(eventStart)) > 60 {
                workout.setCompletedTime(eventStart, for: currentDate)
            }
        default:
            break
        }
    }

    private func scheduleMealSync(for idx: Int) {
        guard idx < dataManager.currentDayData.meals.count else { return }
        mealSyncTasks[idx]?.cancel()
        mealSyncTasks[idx] = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            calendar.syncMealEvents(dataManager.currentDayData.meals, for: currentDate)
        }
    }

    private func swipeDate(by days: Int) {
        mealSyncTasks.values.forEach { $0.cancel() }
        mealSyncTasks.removeAll()
        editingRestDay = false
        if days == 0 { return }
        dragDirection = days > 0 ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.2)) {
            currentDate = Calendar.current.date(byAdding: .day, value: days, to: currentDate) ?? currentDate
        }
        refreshAllData()
    }

    private func changeDate(by days: Int) {
        swipeDate(by: days)
    }
}

private struct WorkoutStatusButton: View {
    let systemImage: String
    let isActive: Bool
    let activeGradient: LinearGradient
    let shadowColor: Color
    let action: () -> Void
    let deactivateAction: () -> Void

    private var baseButton: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(isActive ? .white : .secondary)
            .frame(width: 34, height: 34)
            .background(
                isActive
                    ? activeGradient
                    : LinearGradient(colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
            .shadow(color: isActive ? shadowColor : .clear, radius: 8, y: 4)
            .scaleEffect(isActive ? 1.08 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
            .contentShape(Circle())
    }

    @ViewBuilder
    var body: some View {
        if isActive {
            baseButton
                .onLongPressGesture(minimumDuration: 1.0) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    deactivateAction()
                }
        } else {
            baseButton
                .onTapGesture { action() }
        }
    }
}
