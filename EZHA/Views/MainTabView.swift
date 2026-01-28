import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(0)
            FoodLibraryView()
                .tabItem {
                    Label("Library", systemImage: "bookmark")
                }
                .tag(1)
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
                .tag(2)
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTodayTab)) { _ in
            selectedTab = 0
        }
    }
}
