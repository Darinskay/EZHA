import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        Group {
            if sessionManager.isAuthenticated {
                MainTabView()
            } else {
                AuthLandingView()
            }
        }
    }
}
