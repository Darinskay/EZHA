import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "White"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@main
struct EZHAApp: App {
    @StateObject private var sessionManager = SessionManager()
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .preferredColorScheme(currentAppearance.colorScheme)
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

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearance) ?? .system
    }
}
