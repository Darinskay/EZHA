import SwiftUI

struct AuthLandingView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("EZHA")
                .font(.largeTitle.weight(.bold))
            Text("Track meals and macros with a mocked AI flow.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    sessionManager.signIn()
                } label: {
                    Text("Create account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    sessionManager.signIn()
                } label: {
                    Text("Log in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
