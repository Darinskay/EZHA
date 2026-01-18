import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        ZStack {
            if sessionManager.isAuthenticated {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                AuthLandingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: sessionManager.isAuthenticated)
    }
}
