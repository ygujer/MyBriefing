import SwiftUI

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct FoodTabView: View {
    @State private var weekOffset: Int = 0
    @State private var selectedDate: IdentifiableDate? = nil
    @State private var refreshID = UUID()
    @State private var foodDragDirection: Edge = .trailing
    @Environment(\.colorScheme) private var colorScheme
    private let service = LocalDayDataService()

    private var shadowOpacity: Double { colorScheme == .dark ? 0.28 : 0.06 }

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = -(weekday == 1 ? 6 : weekday - 2)
        let monday = cal.date(byAdding: .day, value: mondayOffset + weekOffset * 7, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                (colorScheme == .dark
                    ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 220).ignoresSafeArea(edges: .top)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            Button(action: { shiftWeek(by: -1) }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(Circle())
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 7, x: 0, y: 4)
                            }
                            Spacer()
                            Text(weekTitle)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Spacer()
                            Button(action: { shiftWeek(by: 1) }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .clipShape(Circle())
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 7, x: 0, y: 4)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)

                        VStack(spacing: 10) {
                            let rows: [[Date?]] = [
                                [weekDates[0], weekDates[1]],
                                [weekDates[2], weekDates[3]],
                                [weekDates[4], weekDates[5]],
                                [weekDates[6], nil]
                            ]
                            ForEach(rows.indices, id: \.self) { rowIdx in
                                HStack(spacing: 10) {
                                    ForEach(0..<2, id: \.self) { colIdx in
                                        if let date = rows[rowIdx][colIdx] {
                                            dayBox(date: date)
                                        } else {
                                            Color.clear.frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 8)
                        .id("\(weekOffset)-\(refreshID)")
                        .transition(.push(from: foodDragDirection))
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .refreshable { refreshID = UUID() }
            }
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > abs(v) else { return }
                    if h < -50 { shiftWeek(by: 1) } else if h > 50 { shiftWeek(by: -1) }
                }
            )
            .sheet(item: $selectedDate, onDismiss: { refreshID = UUID() }) { item in
                MealDayDetailView(date: item.date)
            }
        }
    }

    private func shiftWeek(by amount: Int) {
        foodDragDirection = amount > 0 ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.2)) { weekOffset += amount }
    }

    private var weekTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: first)) – \(fmt.string(from: last))"
    }

    @ViewBuilder
    private func dayBox(date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let data = service.load(for: date)
        Button(action: { selectedDate = IdentifiableDate(date: date) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dayName(date))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isToday ? .accentColor : .primary)
                if data.meals.allSatisfy({ $0.name.isEmpty }) {
                    Text("No meals")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(data.meals) { meal in
                        HStack(spacing: 4) {
                            Text(meal.type + ":")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary).lineLimit(1)
                            Text(meal.name.isEmpty ? "—" : meal.name)
                                .font(.system(size: 11, design: .rounded)).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? Color.accentColor.opacity(0.55) : Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5),
                        lineWidth: isToday ? 1.5 : 1))
            .shadow(color: isToday ? Color.accentColor.opacity(0.35) : Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.07),
                    radius: isToday ? 12 : 10, x: 0, y: isToday ? 6 : 4)
        }
        .buttonStyle(.plain)
    }

    private func dayName(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "EEE d"
        return fmt.string(from: date)
    }
}

// MARK: - Meal Day Detail

struct MealDayDetailView: View {
    let date: Date
    @State private var dayData: DayData = DayData()
    @Environment(\.dismiss) private var dismiss
    private let service = LocalDayDataService()
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var quickPickStore: QuickPickStore
    @State private var mealSyncTasks: [UUID: Task<Void, Never>] = [:]

    private var dateTitle: String {
        let fmt = DateFormatter(); fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: date)
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Meal rows ──────────────────────────────────────
                ForEach(dayData.meals) { meal in
                    if let idx = dayData.meals.firstIndex(where: { $0.id == meal.id }) {
                        HStack(spacing: 8) {
                            TextField("Type", text: $dayData.meals[idx].type)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(width: 82)
                            TextField("Meal name", text: $dayData.meals[idx].name)
                                .font(.system(size: 15, design: .rounded))
                            Spacer(minLength: 0)
                            DatePicker("", selection: mealTimeBinding(for: idx), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .scaleEffect(0.85)
                                .frame(width: 84)
                                .clipped()
                        }
                        .padding(.vertical, 2)
                        .onChange(of: dayData.meals[idx].name) { _, newVal in
                            service.save(dayData, for: date)
                            scheduleSync(for: meal.id, newName: newVal)
                        }
                        .onChange(of: dayData.meals[idx].mealTime) { _, _ in
                            service.save(dayData, for: date)
                            scheduleSync(for: meal.id, newName: dayData.meals[idx].name)
                        }
                        .onChange(of: dayData.meals[idx].type) { _, _ in service.save(dayData, for: date) }
                    }
                }
                .onDelete { offsets in
                    guard !offsets.isEmpty, offsets.allSatisfy({ $0 < dayData.meals.count }) else { return }
                    dayData.meals.remove(atOffsets: offsets)
                    save()
                }

                Button(action: {
                    dayData.meals.append(Meal(type: "Meal \(dayData.meals.count + 1)"))
                    save()
                }) {
                    Label("Add Meal", systemImage: "plus.circle.fill").foregroundColor(.accentColor)
                }

                // ── Quick Pick ─────────────────────────────────────
                quickPickSection
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
            }
            .addGlobalKeyboardDoneButton()
        }
        .onAppear { dayData = service.load(for: date) }
    }

    // MARK: Quick Pick section

    @ViewBuilder
    private var quickPickSection: some View {
        let bfPicks  = quickPickStore.meals.filter { $0.category == .breakfast }
        let dinPicks = quickPickStore.meals.filter { $0.category == .dinner }

        if bfPicks.isEmpty && dinPicks.isEmpty {
            Section("Quick Pick") {
                Text("No quick picks saved yet.\nAdd them in Profile → Manage Quick Picks.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        } else {
            Section("Quick Pick") {
                if !bfPicks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Breakfast", systemImage: "sun.rise.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                        FlowLayout(spacing: 6) {
                            ForEach(bfPicks) { pick in quickPickPill(pick) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                if !dinPicks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dinner", systemImage: "moon.stars.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.indigo)
                        FlowLayout(spacing: 6) {
                            ForEach(dinPicks) { pick in quickPickPill(pick) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func quickPickPill(_ pick: QuickPickMeal) -> some View {
        Button(action: { quickAssign(pick) }) {
            Text(pick.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func quickAssign(_ pick: QuickPickMeal) {
        let target = pick.category.rawValue
        let idx: Int?
        if let i = dayData.meals.firstIndex(where: { $0.type == target && $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            idx = i
        } else if let i = dayData.meals.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            idx = i
        } else {
            idx = nil
        }

        if let i = idx {
            dayData.meals[i].name = pick.name
            save()
            scheduleSync(for: dayData.meals[i].id, newName: pick.name)
        } else {
            let newMeal = Meal(type: target, name: pick.name)
            dayData.meals.append(newMeal)
            save()
            scheduleSync(for: newMeal.id, newName: pick.name)
        }
    }

    private func scheduleSync(for mealID: UUID, newName: String) {
        mealSyncTasks[mealID]?.cancel()
        mealSyncTasks[mealID] = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            calendar.syncMealEvents(dayData.meals, for: date)
            NotificationCenter.default.post(name: Notification.Name("ForceHomeRefresh"), object: nil)
        }
    }

    private func mealTimeBinding(for idx: Int) -> Binding<Date> {
        Binding(
            get: {
                guard idx < dayData.meals.count else { return Date() }
                if let t = dayData.meals[idx].mealTime { return t }
                let h = dayData.meals[idx].type == "Breakfast" ? 8 : 12
                return Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: date) ?? Date()
            },
            set: { newTime in
                guard idx < dayData.meals.count else { return }
                dayData.meals[idx].mealTime = newTime
            }
        )
    }

    private func save() {
        service.save(dayData, for: date)
        NotificationCenter.default.post(name: Notification.Name("ForceHomeRefresh"), object: nil)
    }
}

// MARK: - Flow Layout (wrapping chip grid)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = max(proposal.width ?? 320, 1)
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            rowH = max(rowH, size.height); x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxX = bounds.width > 0 ? bounds.maxX : bounds.minX + max(proposal.width ?? 320, 1)
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowH = max(rowH, size.height); x += size.width + spacing
        }
    }
}
