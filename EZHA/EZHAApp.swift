import SwiftUI

@main
struct EZHAApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var logStore = FoodLogStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(logStore)
        }
    }
}
