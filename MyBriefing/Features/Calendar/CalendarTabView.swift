import SwiftUI
import EventKit
import EventKitUI
import Combine

enum CalendarViewMode: String, CaseIterable {
    case daily    = "Day"
    case threeDay = "3 Day"
    case weekly   = "Week"
    case monthly  = "Month"
}

private let hourHeight: CGFloat = 60
private let timeColumnWidth: CGFloat = 56

// MARK: - CalendarTabView

struct CalendarTabView: View {
    @EnvironmentObject private var calendarMgr: CalendarManager
    @EnvironmentObject private var zoneSettings: ZoneSettingsManager
    @State private var viewMode: CalendarViewMode = .daily
    @State private var selectedDate = Date()
    @State private var now = Date()
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    let calTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @State private var isShowingEventEditor = false
    @State private var newEventDate = Date()
    @State private var calDragDirection: Edge = .trailing
    @State private var draggingEventID: String? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var resizingEventID: String? = nil
    @State private var resizeOffset: CGFloat = 0
    // Which event is in "edit mode" — only this event shows the resize handle.
    @State private var editingEventID: String? = nil

    private var navTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        switch viewMode {
        case .daily, .threeDay:
            f.dateFormat = "d MMMM EEEE"
            return f.string(from: selectedDate).uppercased()
        case .weekly:
            var cal = Calendar.current; cal.firstWeekday = 2
            guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else {
                f.dateFormat = "d MMMM"; return f.string(from: selectedDate).uppercased()
            }
            let sf = DateFormatter(); sf.dateFormat = "d MMM"; sf.locale = Locale(identifier: "en_US")
            let ef = DateFormatter(); ef.dateFormat = "d MMM"; ef.locale = Locale(identifier: "en_US")
            let endDay = cal.date(byAdding: .day, value: 6, to: interval.start) ?? interval.start
            return "\(sf.string(from: interval.start)) – \(ef.string(from: endDay))"
        case .monthly:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: selectedDate).uppercased()
        }
    }

    private var visibleHours: [Int] {
        var hours: [Int] = []
        if zoneSettings.z1Enabled && zoneSettings.z1Start <= zoneSettings.z1End {
            hours.append(contentsOf: zoneSettings.z1Start...zoneSettings.z1End)
        }
        if zoneSettings.zoneGapEnabled && zoneSettings.z1Enabled && zoneSettings.z2Enabled && zoneSettings.z2Start > zoneSettings.z1End + 1 {
            hours.append(contentsOf: (zoneSettings.z1End + 1)...(zoneSettings.z2Start - 1))
        }
        if zoneSettings.z2Enabled && zoneSettings.z2Start <= zoneSettings.z2End {
            hours.append(contentsOf: zoneSettings.z2Start...zoneSettings.z2End)
        }
        if zoneSettings.zoneGapEnabled && zoneSettings.z2Enabled && zoneSettings.z3Enabled && zoneSettings.z3Start > zoneSettings.z2End + 1 {
            hours.append(contentsOf: (zoneSettings.z2End + 1)...(zoneSettings.z3Start - 1))
        }
        if zoneSettings.z3Enabled && zoneSettings.z3Start <= zoneSettings.z3End {
            hours.append(contentsOf: zoneSettings.z3Start...zoneSettings.z3End)
        }
        return Array(Set(hours)).sorted()
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            (colorScheme == .dark
                ? LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.22), Color.clear], startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [Color.accentColor.opacity(0.11), Color.clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 200).ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                Picker("View", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

                HStack(spacing: 12) {
                    Button(action: { shiftDate(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Circle())
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 7, x: 0, y: 4)
                    }
                    Text(navTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .center).lineLimit(1).minimumScaleFactor(0.5)
                    Button(action: { shiftDate(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Circle())
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 7, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)

                Divider()

                Group {
                    switch viewMode {
                    case .daily:    dailyTimeline
                    case .threeDay: threeDayTimeline
                    case .weekly:   WeeklyBlueprintView(selectedDate: selectedDate)
                    case .monthly:  MonthlyInsightsView(selectedDate: selectedDate)
                    }
                }
                .id(selectedDate)
                .transition(.push(from: calDragDirection))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > abs(v) else { return }
                    if h < -50 { shiftDate(by: 1) }
                    else if h > 50 { shiftDate(by: -1) }
                }
        )
        .task { reloadEvents() }
        .onChange(of: selectedDate) { _, _ in reloadEvents() }
        .onChange(of: viewMode)     { _, _ in reloadEvents() }
        .onReceive(calTimer) { date in now = date }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarsUpdated"))) { _ in reloadEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .resetCalendarToToday)) { _ in
            calDragDirection = .leading
            withAnimation(.easeInOut(duration: 0.2)) { selectedDate = Date() }
        }
        .sheet(isPresented: $isShowingEventEditor, onDismiss: { reloadEvents() }) {
            EventEditViewController(eventStore: EKEventStore(), date: newEventDate)
        }
    }

    // MARK: - Daily Timeline

    private var dailyTimeline: some View {
        let allDayEvts = calendarMgr.events.filter { $0.isAllDay }
        return VStack(spacing: 0) {
            if !allDayEvts.isEmpty {
                allDayBar(events: allDayEvts)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if zoneSettings.showZoneWatermarks {
                            zoneWatermarks()
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(visibleHours.enumerated()), id: \.element) { index, hour in
                                HStack(alignment: .top, spacing: 0) {
                                    ZStack(alignment: .topTrailing) {
                                        leftColumnBackground(hour: hour)
                                        Text(String(format: "%d:00", hour))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(zoneNameForHour(hour).isEmpty ? .primary : .white)
                                            .lineLimit(1)
                                            .padding(.trailing, 4)
                                            .offset(y: -8)
                                    }
                                    .frame(width: timeColumnWidth)
                                    ZStack(alignment: .top) {
                                        Color(UIColor.secondarySystemGroupedBackground)
                                        Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.trailing, 12)
                                }
                                .frame(height: hourHeight, alignment: .top)
                                .contentShape(Rectangle())
                                .onLongPressGesture {
                                    let cal = Calendar.current
                                    if let newDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                                        newEventDate = newDate
                                        isShowingEventEditor = true
                                    }
                                }
                                .id(hour)
                            }
                        }
                        if zoneSettings.showZoneWatermarks {
                            ForEach(computeZoneBlocks()) { block in
                                let blockH = CGFloat(block.length) * hourHeight
                                Text(block.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.88))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                    .frame(width: blockH - 4, height: 14)
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 14, height: blockH - 4)
                                    .offset(y: CGFloat(block.startIndex) * hourHeight + 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        ForEach(calendarMgr.events.filter { !$0.isAllDay }, id: \.eventIdentifier) { event in
                            let cal    = Calendar.current
                            let sod    = cal.startOfDay(for: selectedDate)
                            let eod    = cal.date(byAdding: .day, value: 1, to: sod) ?? sod
                            let rStart = max(event.startDate, sod)
                            let rEnd   = min(event.endDate,   eod)
                            if rEnd > rStart {
                                let rH = cal.component(.hour,   from: rStart)
                                let rM = cal.component(.minute, from: rStart)
                                let eH = cal.component(.hour,   from: rEnd)
                                let eM = cal.component(.minute, from: rEnd)
                                let oH = cal.component(.hour,   from: event.startDate)
                                let oM = cal.component(.minute, from: event.startDate)
                                if offsetForTime(hour: rH, minute: rM) == nil,
                                   let first = visibleHours.first, rH < first,
                                   let cH = clampedHeightForPreTimelineEvent(endHour: eH, endMinute: eM) {
                                    timelineEventCard(event, earlyStartLabel: String(format: "Started at %d:%02d", oH, oM))
                                        .frame(height: max(cH, 28))
                                        .padding(.leading, timeColumnWidth).padding(.trailing, 12)
                                        .offset(y: 0)
                                        .onTapGesture {
                                            if let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)") { openURL(url) }
                                        }
                                }
                            }
                        }
                        let layouts = computeEventLayouts(for: selectedDate)
                        GeometryReader { geo in
                            let avail = geo.size.width - timeColumnWidth - 12
                            ForEach(layouts) { layout in
                                let isDragging = draggingEventID == layout.event.eventIdentifier
                                let isResizing = resizingEventID == layout.event.eventIdentifier
                                let colW   = max(avail / CGFloat(layout.totalColumns), 40)
                                let xPos   = timeColumnWidth + colW * CGFloat(layout.column)
                                let finalH = max(layout.height + (isResizing ? resizeOffset : 0), 28)
                                timelineEventCard(layout.event, earlyStartLabel: layout.crossLabel)
                                    .overlay(alignment: .bottom) {
                                        // Resize handle — only visible when this event is in edit mode.
                                        if editingEventID == layout.event.eventIdentifier {
                                            Capsule()
                                                .fill(Color(cgColor: layout.event.calendar.cgColor).opacity(0.75))
                                                .frame(width: 32, height: 5)
                                                .padding(.bottom, 2)
                                                .gesture(
                                                    DragGesture()
                                                        .onChanged { drag in
                                                            resizingEventID = layout.event.eventIdentifier
                                                            resizeOffset = drag.translation.height
                                                        }
                                                        .onEnded { drag in
                                                            let ds = round(Double(drag.translation.height / hourHeight) * 3600 / 900) * 900
                                                            let dur = max(layout.event.endDate.timeIntervalSince(layout.event.startDate) + ds, 900)
                                                            calendarMgr.updateEventTimes(layout.event, start: layout.event.startDate, end: layout.event.startDate.addingTimeInterval(dur))
                                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                            resizingEventID = nil; resizeOffset = 0
                                                            editingEventID = nil
                                                        }
                                                )
                                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
                                        }
                                    }
                                    .frame(width: colW - 2, height: finalH)
                                    .offset(x: xPos, y: layout.topOffset + (isDragging ? dragOffset : 0))
                                    .zIndex(isDragging || isResizing ? 100 : 0)
                                    .animation(.easeInOut(duration: 0.18), value: editingEventID)
                                    .gesture(
                                        LongPressGesture(minimumDuration: 0.4)
                                            .sequenced(before: DragGesture())
                                            .onChanged { state in
                                                switch state {
                                                case .first(true):
                                                    // Long press fired, finger still down, no drag yet → enter edit mode.
                                                    if editingEventID != layout.event.eventIdentifier {
                                                        editingEventID = layout.event.eventIdentifier
                                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                    }
                                                case .second(true, let drag?):
                                                    // Drag started after long press → move mode; hide resize handle.
                                                    editingEventID = nil
                                                    draggingEventID = layout.event.eventIdentifier
                                                    dragOffset = drag.translation.height
                                                default: break
                                                }
                                            }
                                            .onEnded { state in
                                                if case .second(true, let drag?) = state {
                                                    let ds = round(Double(drag.translation.height / hourHeight) * 3600 / 900) * 900
                                                    calendarMgr.updateEventTimes(layout.event,
                                                        start: layout.event.startDate.addingTimeInterval(ds),
                                                        end:   layout.event.endDate.addingTimeInterval(ds))
                                                }
                                                draggingEventID = nil; dragOffset = 0
                                            }
                                    )
                                    .onTapGesture {
                                        // First tap on a selected event exits edit mode without opening Calendar.
                                        // Tap on a non-selected event clears any other edit mode and opens Calendar.
                                        let wasEditing = editingEventID == layout.event.eventIdentifier
                                        editingEventID = nil
                                        if !wasEditing {
                                            if let url = URL(string: "calshow:\(layout.event.startDate.timeIntervalSinceReferenceDate)") { openURL(url) }
                                        }
                                    }
                            }
                        }
                        if Calendar.current.isDateInToday(selectedDate) {
                            let cal = Calendar.current
                            let h = cal.component(.hour, from: now)
                            let m = cal.component(.minute, from: now)
                            if let off = offsetForTime(hour: h, minute: m) {
                                HStack(spacing: 0) {
                                    Circle().fill(Color.red).frame(width: 8, height: 8).padding(.leading, timeColumnWidth + 4)
                                    Rectangle().fill(Color.red).frame(height: 2).padding(.trailing, 12)
                                }
                                .offset(y: off)
                                .zIndex(10)
                            }
                        }
                    }
                    .frame(minHeight: CGFloat(visibleHours.count) * hourHeight)
                }
                .onAppear {
                    let h = Calendar.current.component(.hour, from: Date())
                    let closestHour = visibleHours.min(by: { abs($0 - h) < abs($1 - h) }) ?? (visibleHours.first ?? 0)
                    proxy.scrollTo(closestHour, anchor: .top)
                }
                .refreshable { reloadEvents() }
            }
        }
    }

    // MARK: - Zone Watermarks

    @ViewBuilder
    private func zoneWatermarks() -> some View {
        if zoneSettings.z1Enabled { watermark(for: zoneSettings.z1Name, start: zoneSettings.z1Start, end: zoneSettings.z1End, color: .blue) }
        if zoneSettings.z2Enabled { watermark(for: zoneSettings.z2Name, start: zoneSettings.z2Start, end: zoneSettings.z2End, color: .purple) }
        if zoneSettings.z3Enabled { watermark(for: zoneSettings.z3Name, start: zoneSettings.z3Start, end: zoneSettings.z3End, color: .green) }
    }

    @ViewBuilder
    private func watermark(for name: String, start: Int, end: Int, color: Color) -> some View {
        if let startIdx = visibleHours.firstIndex(of: start),
           let endIdx   = visibleHours.firstIndex(of: end),
           startIdx <= endIdx {
            let height  = CGFloat(endIdx - startIdx + 1) * hourHeight
            let yOffset = CGFloat(startIdx) * hourHeight
            VStack {
                Spacer()
                Text(name.uppercased())
                    .font(.system(size: 110, weight: .ultraLight))
                    .foregroundColor(color.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 2, x: 1, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.2).padding(.horizontal, 20)
                Spacer()
            }
            .frame(maxWidth: .infinity).frame(height: height).clipped()
            .padding(.top, yOffset).padding(.leading, timeColumnWidth)
            .allowsHitTesting(false)
        }
    }

    // MARK: - All-Day Bar

    @ViewBuilder
    private func allDayBar(events: [EKEvent]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(events, id: \.eventIdentifier) { event in
                    let color = Color(cgColor: event.calendar.cgColor)
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(event.title ?? "Untitled")
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15)).clipShape(Capsule())
                    .onTapGesture {
                        if let url = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)") { openURL(url) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Event Card

    @ViewBuilder
    private func timelineEventCard(_ event: EKEvent, earlyStartLabel: String? = nil) -> some View {
        let eventColor = Color(cgColor: event.calendar.cgColor)
        HStack(spacing: 0) {
            Rectangle().fill(eventColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let label = earlyStartLabel {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.left").font(.system(size: 7, weight: .bold))
                        Text(label).font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(eventColor).padding(.bottom, 1)
                }
                Text(event.title ?? "Untitled").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.top, 4)
            Spacer(minLength: 0)
        }
        .background(eventColor.opacity(0.15))
        .cornerRadius(5)
    }

    // MARK: - Zone Helpers

    private func offsetForTime(hour: Int, minute: Int) -> CGFloat? {
        guard let idx = visibleHours.firstIndex(of: hour) else { return nil }
        return CGFloat(idx) * hourHeight + CGFloat(minute) / 60.0 * hourHeight
    }

    private func isZone1(_ h: Int) -> Bool { zoneSettings.z1Enabled && h >= zoneSettings.z1Start && h <= zoneSettings.z1End }
    private func isZone2(_ h: Int) -> Bool { zoneSettings.z2Enabled && h >= zoneSettings.z2Start && h <= zoneSettings.z2End }
    private func isZone3(_ h: Int) -> Bool { zoneSettings.z3Enabled && h >= zoneSettings.z3Start && h <= zoneSettings.z3End }

    private func zoneColorForHour(_ h: Int) -> Color {
        let op: Double = colorScheme == .dark ? 0.55 : 0.72
        if isZone1(h) { return Color.blue.opacity(op) }
        if isZone2(h) { return Color.purple.opacity(op) }
        if isZone3(h) { return Color.green.opacity(op) }
        return Color(UIColor.systemGroupedBackground)
    }

    private func zoneNameForHour(_ h: Int) -> String {
        if isZone1(h) { return zoneSettings.z1Name }
        if isZone2(h) { return zoneSettings.z2Name }
        if isZone3(h) { return zoneSettings.z3Name }
        return ""
    }

    @ViewBuilder
    private func leftColumnBackground(hour: Int) -> some View {
        if !zoneNameForHour(hour).isEmpty {
            zoneColorForHour(hour)
        } else if zoneSettings.zoneGapEnabled {
            StripedBackground()
        } else {
            Color(UIColor.systemGroupedBackground)
        }
    }

    // MARK: - Zone Block Grouping

    private struct ZoneBlock: Identifiable {
        let id: Int; let name: String; let color: Color
        let startIndex: Int; let length: Int
    }

    private func computeZoneBlocks() -> [ZoneBlock] {
        var blocks: [ZoneBlock] = []; var i = 0
        while i < visibleHours.count {
            let hour = visibleHours[i]; let name = zoneNameForHour(hour)
            guard !name.isEmpty else { i += 1; continue }
            var j = i + 1
            while j < visibleHours.count && zoneNameForHour(visibleHours[j]) == name { j += 1 }
            blocks.append(ZoneBlock(id: i, name: name, color: zoneColorForHour(hour), startIndex: i, length: j - i))
            i = j
        }
        return blocks
    }

    // MARK: - Overlap Layout

    private struct EventLayout: Identifiable {
        let event: EKEvent; let column: Int; let totalColumns: Int
        let topOffset: CGFloat; let height: CGFloat; let crossLabel: String?
        var id: String { event.eventIdentifier }
    }

    private func computeEventLayouts(for date: Date) -> [EventLayout] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        struct Info {
            let event: EKEvent; let renderStart, renderEnd: Date
            let topOffset, height: CGFloat; let crossLabel: String?
        }
        var infos: [Info] = []
        for event in calendarMgr.events where !event.isAllDay {
            let rStart = max(event.startDate, startOfDay)
            let rEnd   = min(event.endDate,   endOfDay)
            guard rEnd > rStart else { continue }
            let rH = cal.component(.hour,   from: rStart)
            let rM = cal.component(.minute, from: rStart)
            guard let topOff = offsetForTime(hour: rH, minute: rM) else { continue }
            let evtH    = CGFloat(rEnd.timeIntervalSince(rStart) / 3600.0) * hourHeight
            let isCross = event.startDate < startOfDay
            let oH = cal.component(.hour,   from: event.startDate)
            let oM = cal.component(.minute, from: event.startDate)
            infos.append(Info(event: event, renderStart: rStart, renderEnd: rEnd,
                              topOffset: topOff, height: max(evtH, 28),
                              crossLabel: isCross ? String(format: "Started at %d:%02d", oH, oM) : nil))
        }
        infos.sort { $0.renderStart < $1.renderStart }
        var colEnds: [Date] = []; var cols: [Int] = []
        for info in infos {
            var assigned = -1
            for c in 0..<colEnds.count where colEnds[c] <= info.renderStart {
                assigned = c; colEnds[c] = info.renderEnd; break
            }
            if assigned == -1 { assigned = colEnds.count; colEnds.append(info.renderEnd) }
            cols.append(assigned)
        }
        return infos.enumerated().map { i, info in
            var maxCol = cols[i]
            for j in 0..<infos.count where j != i {
                if info.renderStart < infos[j].renderEnd && info.renderEnd > infos[j].renderStart {
                    maxCol = max(maxCol, cols[j])
                }
            }
            return EventLayout(event: info.event, column: cols[i], totalColumns: maxCol + 1,
                               topOffset: info.topOffset, height: info.height, crossLabel: info.crossLabel)
        }
    }

    private func clampedHeightForPreTimelineEvent(endHour: Int, endMinute: Int) -> CGFloat? {
        guard let firstVisible = visibleHours.first else { return nil }
        guard endHour > firstVisible || (endHour == firstVisible && endMinute > 0) else { return nil }
        if let idx = visibleHours.firstIndex(of: endHour) {
            let h = CGFloat(idx) * hourHeight + CGFloat(endMinute) / 60.0 * hourHeight
            return h > 0 ? h : nil
        }
        if let last = visibleHours.last, endHour > last { return CGFloat(visibleHours.count) * hourHeight }
        if let lastBefore = visibleHours.filter({ $0 < endHour }).last,
           let idx = visibleHours.firstIndex(of: lastBefore) { return CGFloat(idx + 1) * hourHeight }
        return nil
    }

    // MARK: - 3-Day Timeline

    private var threeDayTimeline: some View {
        let cal = Calendar.current
        let base = cal.startOfDay(for: selectedDate)
        let dates = (0..<3).compactMap { cal.date(byAdding: .day, value: $0, to: base) }
        let totalHeight = CGFloat(visibleHours.count) * hourHeight
        let fmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE\nd"; return f }()

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: timeColumnWidth)
                ForEach(dates, id: \.timeIntervalSinceReferenceDate) { day in
                    let isToday = cal.isDateInToday(day)
                    Text(fmt.string(from: day))
                        .font(.system(size: 11, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundColor(isToday ? .accentColor : .secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleHours.enumerated()), id: \.element) { _, hour in
                                ZStack(alignment: .topTrailing) {
                                    Color(UIColor.systemGroupedBackground)
                                    Text(String(format: "%d:00", hour))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .padding(.trailing, 4).offset(y: -8)
                                }
                                .frame(width: timeColumnWidth, height: hourHeight).id(hour)
                            }
                        }
                        ForEach(Array(dates.enumerated()), id: \.offset) { colIdx, day in
                            let dayStart2 = cal.startOfDay(for: day)
                            let dayEnd2   = cal.date(byAdding: .day, value: 1, to: dayStart2)!
                            let colEvents = calendarMgr.events.filter { !$0.isAllDay && $0.startDate < dayEnd2 && $0.endDate > dayStart2 }
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(Array(visibleHours.enumerated()), id: \.element) { _, hour in
                                        ZStack(alignment: .top) {
                                            let zOp = colorScheme == .dark ? 0.28 : 0.14
                                            if isZone1(hour) { Color.blue.opacity(zOp) }
                                            else if isZone2(hour) { Color.purple.opacity(zOp) }
                                            else if isZone3(hour) { Color.green.opacity(zOp) }
                                            else { Color.clear }
                                            Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 1)
                                        }
                                        .frame(height: hourHeight)
                                    }
                                }
                                if colIdx > 0 {
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1).frame(maxHeight: .infinity)
                                }
                                ForEach(colEvents, id: \.eventIdentifier) { event in
                                    let rStart = max(event.startDate, dayStart2)
                                    let rEnd   = min(event.endDate,   dayEnd2)
                                    if rEnd > rStart {
                                        let rH = cal.component(.hour,   from: rStart)
                                        let rM = cal.component(.minute, from: rStart)
                                        let evH = CGFloat(rEnd.timeIntervalSince(rStart) / 3600.0) * hourHeight
                                        if let topOff = offsetForTime(hour: rH, minute: rM) {
                                            let evtColor = Color(cgColor: event.calendar.cgColor)
                                            HStack(spacing: 0) {
                                                Rectangle().fill(evtColor).frame(width: 2)
                                                Text(event.title ?? "")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .lineLimit(3).foregroundColor(evtColor)
                                                    .padding(.horizontal, 2).padding(.top, 2)
                                                Spacer(minLength: 0)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .frame(height: max(evH, 16))
                                            .background(evtColor.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                            .padding(.trailing, 1)
                                            .offset(y: topOff)
                                        }
                                    }
                                }
                                if cal.isDateInToday(day) {
                                    let h = cal.component(.hour,   from: now)
                                    let m = cal.component(.minute, from: now)
                                    if let off = offsetForTime(hour: h, minute: m) {
                                        HStack(spacing: 0) {
                                            Circle().fill(Color.red).frame(width: 6, height: 6)
                                            Rectangle().fill(Color.red).frame(maxWidth: .infinity).frame(height: 1.5)
                                        }
                                        .frame(maxWidth: .infinity).offset(y: off).zIndex(10)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: totalHeight)
                        }
                    }
                    .padding(.trailing, 8)
                }
                .onAppear {
                    let h = Calendar.current.component(.hour, from: Date())
                    let closest = visibleHours.min(by: { abs($0 - h) < abs($1 - h) }) ?? (visibleHours.first ?? 0)
                    proxy.scrollTo(closest, anchor: .top)
                }
                .refreshable { reloadEvents() }
            }
        }
    }

    // MARK: - Actions

    private func reloadEvents() {
        let cal = Calendar.current
        switch viewMode {
        case .threeDay:
            let base = cal.startOfDay(for: selectedDate)
            let end  = cal.date(byAdding: .day, value: 3, to: base) ?? base
            calendarMgr.loadEventsInRange(from: base, to: end)
        case .daily:
            calendarMgr.loadEvents(for: selectedDate)
        case .weekly, .monthly:
            break
        }
    }

    private func shiftDate(by amount: Int) {
        calDragDirection = amount > 0 ? .trailing : .leading
        let unit: Calendar.Component; var actual = amount
        switch viewMode {
        case .weekly:   unit = .weekOfYear
        case .monthly:  unit = .month
        case .threeDay: unit = .day; actual = amount * 3
        case .daily:    unit = .day
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = Calendar.current.date(byAdding: unit, value: actual, to: selectedDate) ?? selectedDate
        }
    }
}

// MARK: - Weekly Blueprint & Insights

struct WeeklyBlueprintView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @Environment(\.colorScheme) private var colorScheme
    let selectedDate: Date

    @State private var dayDataMap: [String: DayData] = [:]
    private let service = LocalDayDataService()

    private var weekDays: [Date] {
        var cal = Calendar.current; cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var workoutDoneCount: Int     { weekDays.filter { workout.status(for: $0) == .done }.count }
    private var workoutScheduledCount: Int { weekDays.filter { !workout.exerciseLabel(for: $0).isEmpty }.count }

    private var weekAvgMood: Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let moods = weekDays
            .filter { Calendar.current.startOfDay(for: $0) <= today }
            .compactMap { date -> Int? in
                let m = dayDataMap[LocalDayDataService.dateKey(for: date)]?.mood ?? 0
                return m > 0 ? m : nil
            }
        guard !moods.isEmpty else { return nil }
        return Double(moods.reduce(0, +)) / Double(moods.count)
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55), lineWidth: 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                insightsSection
                blueprintSection
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
        }
        .onAppear { loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
    }

    // MARK: Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WEEKLY INSIGHTS")
            HStack(spacing: 12) {
                insightCard(icon: "dumbbell.fill", color: .indigo,
                            value: workoutScheduledCount == 0 ? "—" : "\(workoutDoneCount)/\(workoutScheduledCount)",
                            label: "Workouts Done")
                insightCard(icon: "face.smiling", color: .orange,
                            value: weekAvgMood.map { "\(moodEmoji(for: Int($0.rounded()))) \(String(format: "%.1f", $0))" } ?? "—",
                            label: "Avg Mood")
            }
        }
    }

    @ViewBuilder
    private func insightCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: color.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 14, x: 0, y: 6)
    }

    // MARK: Blueprint

    private var blueprintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WEEKLY BLUEPRINT")
            VStack(spacing: 8) {
                ForEach(weekDays, id: \.self) { date in
                    blueprintRow(for: date)
                }
            }
        }
    }

    @ViewBuilder
    private func blueprintRow(for date: Date) -> some View {
        let cal     = Calendar.current
        let isToday = cal.isDateInToday(date)
        let isFut   = cal.startOfDay(for: date) > cal.startOfDay(for: Date())
        let label   = workout.exerciseLabel(for: date)
        let isRest  = label.isEmpty
        let status  = workout.status(for: date)
        let meals   = (dayDataMap[LocalDayDataService.dateKey(for: date)]?.meals ?? []).filter { !$0.name.isEmpty }
        let wfmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "en_US"); return f }()

        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 1) {
                Text(wfmt.string(from: date))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isToday ? .white : .secondary)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(isToday ? .white : .primary)
            }
            .frame(width: 38, height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isToday ? Color.accentColor : Color.secondary.opacity(0.1)))

            // Accent rule
            Capsule()
                .fill(isRest ? Color.secondary.opacity(0.2) : Color.accentColor.opacity(isToday ? 0.55 : 0.3))
                .frame(width: 2, height: 46)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                if isRest {
                    Text("Rest Day")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary).italic()
                } else {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
                if !meals.isEmpty {
                    Text(meals.map { $0.name }.joined(separator: " · "))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Status icon for past/today scheduled days
            if !isRest && !isFut {
                Group {
                    switch status {
                    case .done:     Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    case .notDone:  Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    case .postpone: Image(systemName: "arrow.right.circle.fill").foregroundColor(.orange)
                    case .neutral:  Image(systemName: "circle.dashed").foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .font(.system(size: 18))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.accentColor.opacity(0.09))
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(isToday ? Color.accentColor.opacity(0.35) : Color.white.opacity(colorScheme == .dark ? 0.1 : 0.45), lineWidth: 1))
        .shadow(color: Color.accentColor.opacity(isToday ? 0.12 : 0.06), radius: 8, x: 0, y: 3)
        .opacity(isFut ? 0.55 : 1.0)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary).tracking(1.5)
    }

    private func loadData() { dayDataMap = service.batchLoad(dates: weekDays) }
}

// MARK: - Monthly Insights

struct MonthlyInsightsView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @Environment(\.colorScheme) private var colorScheme
    let selectedDate: Date

    @State private var dayDataMap: [String: DayData] = [:]
    private let service = LocalDayDataService()

    // Mon-aligned grid; nil = blank filler cell
    private var monthGrid: [Date?] {
        var cal = Calendar.current; cal.firstWeekday = 2
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)),
              let range = cal.range(of: .day, in: .month, for: selectedDate) else { return [] }
        let firstWeekday  = cal.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - 2 + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...range.count {
            result.append(cal.date(bySetting: .day, value: day, of: monthStart))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var allMonthDates: [Date] { monthGrid.compactMap { $0 } }

    private var totalDone: Int { allMonthDates.filter { workout.status(for: $0) == .done }.count }

    private var monthAvgMood: Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let moods = allMonthDates
            .filter { Calendar.current.startOfDay(for: $0) <= today }
            .compactMap { date -> Int? in
                let m = dayDataMap[LocalDayDataService.dateKey(for: date)]?.mood ?? 0
                return m > 0 ? m : nil
            }
        guard !moods.isEmpty else { return nil }
        return Double(moods.reduce(0, +)) / Double(moods.count)
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55), lineWidth: 1)
    }
    private var shadowColor: Color { Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.09) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                consistencyMapSection
                overviewSection
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
        }
        .onAppear { loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
    }

    // MARK: Consistency Map

    private var consistencyMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("CONSISTENCY MAP")
            VStack(spacing: 10) {
                // Weekday headers
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(["M","T","W","T","F","S","S"][i])
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary).frame(maxWidth: .infinity)
                    }
                }
                // Day cells
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<monthGrid.count, id: \.self) { i in
                        if let date = monthGrid[i] {
                            consistencyCell(date: date)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                // Legend
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        legendDot(.accentColor,               "Done")
                        legendDot(.red.opacity(0.65),         "Missed")
                        legendDot(.orange.opacity(0.65),      "Postponed")
                        legendDot(Color.accentColor.opacity(0.28), "Planned")
                        legendDot(Color.secondary.opacity(0.22),   "Rest")
                    }
                    .font(.system(size: 10, design: .rounded)).foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(glassBorder)
            .shadow(color: shadowColor, radius: 14, x: 0, y: 6)
        }
    }

    @ViewBuilder
    private func consistencyCell(date: Date) -> some View {
        let cal     = Calendar.current
        let today   = cal.startOfDay(for: Date())
        let isFut   = cal.startOfDay(for: date) > today
        let isToday = cal.isDateInToday(date)
        let label   = workout.exerciseLabel(for: date)
        let isRest  = label.isEmpty
        let status  = workout.status(for: date)
        let dayNum  = cal.component(.day, from: date)

        let fillColor: Color = {
            if isRest  { return Color.secondary.opacity(0.18) }
            if isFut   { return Color.accentColor.opacity(0.18) }
            switch status {
            case .done:     return .accentColor
            case .notDone:  return .red.opacity(0.65)
            case .postpone: return .orange.opacity(0.65)
            case .neutral:  return Color.accentColor.opacity(0.28)
            }
        }()

        let textColor: Color = (!isRest && !isFut && status == .done) ? .white : .primary.opacity(isFut ? 0.4 : 0.75)

        ZStack {
            Circle().fill(fillColor)
            if isToday { Circle().stroke(Color.accentColor, lineWidth: 2) }
            Text("\(dayNum)")
                .font(.system(size: 11, weight: (!isRest && !isFut && status == .done) ? .bold : .regular, design: .rounded))
                .foregroundColor(textColor)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(label) }
    }

    // MARK: Overview Cards

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MONTHLY OVERVIEW")
            HStack(spacing: 12) {
                overviewCard(icon: "checkmark.seal.fill", color: .green,
                             value: "\(totalDone)", label: "Workouts Done")
                overviewCard(icon: "face.smiling", color: .orange,
                             value: monthAvgMood.map { "\(moodEmoji(for: Int($0.rounded()))) \(String(format: "%.1f", $0))" } ?? "—",
                             label: "Monthly Mood Avg")
            }
        }
    }

    @ViewBuilder
    private func overviewCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(glassBorder)
        .shadow(color: color.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 14, x: 0, y: 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary).tracking(1.5)
    }

    private func loadData() { dayDataMap = service.batchLoad(dates: allMonthDates) }
}
