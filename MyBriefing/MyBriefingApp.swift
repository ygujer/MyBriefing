import SwiftUI
import UIKit
import EventKit

@main
struct MyBriefingApp: App {
    @AppStorage("appTheme") private var appTheme: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var zoneSettings = ZoneSettingsManager()
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var quickPickStore = QuickPickStore()

    init() {
        installGlobalKeyboardDoneBar()
    }

    private var preferredScheme: ColorScheme? {
        switch appTheme {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await calendarManager.start() }
                .environmentObject(workoutManager)
                .environmentObject(zoneSettings)
                .environmentObject(calendarManager)
                .environmentObject(quickPickStore)
                .preferredColorScheme(preferredScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background {
                // loadEvents is synchronous — reload today so we always get fresh data.
                calendarManager.loadEvents(for: Date())

                // Mirror HomeView's hourRow(hour:) span logic exactly:
                // an event occupies every hour it covers, not just its start hour.
                // This makes multi-hour and midnight-crossing events (e.g. sleep) visible
                // in all their zone rows, just like on the home screen.
                let cal = Calendar.current
                var dailyEvents: [Int: String] = [:]
                for event in calendarManager.events where !event.isAllDay {
                    guard let title = event.title, !title.isEmpty else { continue }
                    let startH = cal.component(.hour, from: event.startDate)
                    let crossesMidnight = !cal.isDate(event.startDate, inSameDayAs: event.endDate)
                    if crossesMidnight {
                        for h in startH...23 where dailyEvents[h] == nil { dailyEvents[h] = title }
                    } else {
                        let endH = cal.component(.hour, from: event.endDate)
                        let endM = cal.component(.minute, from: event.endDate)
                        let adjustedEnd = (endM == 0 && endH > startH) ? endH - 1 : endH
                        for h in startH...max(startH, adjustedEnd) where dailyEvents[h] == nil {
                            dailyEvents[h] = title
                        }
                    }
                }

                WidgetDataWriter.shared.sync(
                    workoutManager: workoutManager,
                    zoneSettings:   zoneSettings,
                    dailyEvents:    dailyEvents
                )
            }
        }
    }
}

// MARK: - Global UIKit "Done" toolbar injected into every UITextField / UITextView

private func installGlobalKeyboardDoneBar() {
    swizzleInputAccessory(on: UITextField.self,
                          replacement: #selector(UITextField._globalDoneAccessoryView))
    swizzleInputAccessory(on: UITextView.self,
                          replacement: #selector(UITextView._globalDoneAccessoryViewTV))
}

private func swizzleInputAccessory(on cls: AnyClass, replacement: Selector) {
    let getter = NSSelectorFromString("inputAccessoryView")
    guard let orig = class_getInstanceMethod(cls, getter),
          let repl = class_getInstanceMethod(cls, replacement) else { return }
    method_exchangeImplementations(orig, repl)
}

// One shared toolbar reused across all inputs (safe on iPhone — single active keyboard).
private let _globalDoneBar: UIToolbar = {
    let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    bar.items = [
        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        UIBarButtonItem(title: "Done", style: .done, target: nil,
                        action: #selector(UIResponder.resignFirstResponder))
    ]
    bar.sizeToFit()
    return bar
}()

extension UITextField {
    // After the swizzle, calling `self._globalDoneAccessoryView()` dispatches through
    // the ObjC runtime and hits the ORIGINAL inputAccessoryView implementation — not ours.
    @objc func _globalDoneAccessoryView() -> UIView? {
        self._globalDoneAccessoryView() ?? _globalDoneBar
    }
}

extension UITextView {
    @objc func _globalDoneAccessoryViewTV() -> UIView? {
        self._globalDoneAccessoryViewTV() ?? _globalDoneBar
    }
}
