import SwiftUI

struct AuthLandingView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = true

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
            VStack(spacing: 16) {
                Picker("Auth Mode", selection: $isCreatingAccount) {
                    Text("Create").tag(true)
                    Text("Log in").tag(false)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage = sessionManager.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        if isCreatingAccount {
                            await sessionManager.signUp(email: email, password: password)
                        } else {
                            await sessionManager.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    HStack {
                        if sessionManager.isLoading {
                            ProgressView()
                        }
                        Text(isCreatingAccount ? "Create account" : "Log in")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionManager.isLoading || email.isEmpty || password.isEmpty)

                Button {
                    Task {
                        await sessionManager.signInWithGoogle()
                    }
                } label: {
                    Text("Continue with Google")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sessionManager.isLoading)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
