import SwiftUI

@main
struct EZHAApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .onOpenURL { url in
                    Task {
                        do {
                            try await SupabaseConfig.client.auth.session(from: url)
                        } catch {
                            sessionManager.errorMessage = error.localizedDescription
                        }
                    }
                }
        }
    }
}
