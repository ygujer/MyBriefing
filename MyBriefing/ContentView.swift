import SwiftUI

extension Notification.Name {
    static let resetHomeToToday = Notification.Name("resetHomeToToday")
    static let homeTabActivated = Notification.Name("homeTabActivated")
    static let resetCalendarToToday = Notification.Name("resetCalendarToToday")
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {

            // SCREEN CONTENT
            ZStack {
                HomeView().opacity(selectedTab == 0 ? 1 : 0)
                CalendarTabView().opacity(selectedTab == 1 ? 1 : 0)
                ProgressTabView().opacity(selectedTab == 2 ? 1 : 0)
                WorkoutTabView().opacity(selectedTab == 3 ? 1 : 0)
                FoodTabView().opacity(selectedTab == 4 ? 1 : 0)
                ProfileTabView().opacity(selectedTab == 5 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 65)

            // STICKY NAVIGATION BAR
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer()
                    customTabItem(icon: "house.fill", title: "Home", index: 0)
                    Spacer()
                    customTabItem(icon: "calendar", title: "Calendar", index: 1)
                    Spacer()
                    customTabItem(icon: "chart.line.uptrend.xyaxis", title: "Progress", index: 2)
                    Spacer()
                    customTabItem(icon: "dumbbell.fill", title: "Workout", index: 3)
                    Spacer()
                    customTabItem(icon: "fork.knife", title: "Food", index: 4)
                    Spacer()
                    customTabItem(icon: "person.crop.circle.fill", title: "Profile", index: 5)
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 5)
            }
            .background(Color(UIColor.systemBackground).ignoresSafeArea(edges: .bottom))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.3)),
                alignment: .top
            )
            .zIndex(999)
        }
        .ignoresSafeArea(.keyboard)
        .onOpenURL { url in
            guard url.scheme == "mybriefing" else { return }
            selectedTab = 0
        }
    }

    @ViewBuilder
    func customTabItem(icon: String, title: String, index: Int) -> some View {
        Button(action: {
            if selectedTab == 0 && index == 0 {
                NotificationCenter.default.post(name: .resetHomeToToday, object: nil)
            } else if index == 0 {
                NotificationCenter.default.post(name: .homeTabActivated, object: nil)
            } else if selectedTab == 1 && index == 1 {
                NotificationCenter.default.post(name: .resetCalendarToToday, object: nil)
            }
            selectedTab = index
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .scaleEffect(selectedTab == index ? 1.15 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: selectedTab)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selectedTab == index ? .primary : .gray)
            .frame(minWidth: 44)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
        .environmentObject(ZoneSettingsManager())
        .environmentObject(CalendarManager())
}

// MARK: - Keyboard helpers (Done toolbar is injected globally via UIKit swizzle in MyBriefingApp)

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func addGlobalKeyboardDoneButton() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
