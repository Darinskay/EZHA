import SwiftUI

@main
struct EZHAApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
        }
    }
}
