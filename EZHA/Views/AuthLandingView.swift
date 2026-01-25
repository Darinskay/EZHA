import SwiftUI
import UIKit

struct AuthLandingView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = true
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
        .overlay(
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Text("EZHA")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Smarter meal logging with AI estimates you can edit.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 18) {
                        Picker("Auth Mode", selection: $isCreatingAccount) {
                            Text("Create").tag(true)
                            Text("Log in").tag(false)
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope")
                                    .foregroundColor(.secondary)
                                TextField("Email", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.separator).opacity(0.7), lineWidth: 1)
                            )

                            HStack(spacing: 10) {
                                Image(systemName: "lock")
                                    .foregroundColor(.secondary)
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.separator).opacity(0.7), lineWidth: 1)
                            )
                        }

                        if let errorMessage = sessionManager.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        Button {
                            if sessionManager.isLoading {
                                return
                            }
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmedEmail.isEmpty || password.isEmpty {
                                sessionManager.errorMessage = "Email and password are required."
                                return
                            }
                            triggerHaptic()
                            Task {
                                if isCreatingAccount {
                                    await sessionManager.signUp(email: trimmedEmail, password: password)
                                } else {
                                    await sessionManager.signIn(email: trimmedEmail, password: password)
                                }
                            }
                        } label: {
                            ZStack {
                                Text(isCreatingAccount ? "Create account" : "Log in")
                                    .opacity(sessionManager.isLoading ? 0 : 1)
                                if sessionManager.isLoading {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .frame(height: 48)
                        .background(.linearGradient(colors: [Color(red: 0.9, green: 0.4, blue: 0.8), Color(red: 0.5, green: 0.2, blue: 0.7)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundColor(.white)

                        Button {
                            if sessionManager.isLoading {
                                return
                            }
                            triggerHaptic()
                            Task {
                                await sessionManager.signInWithGoogle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                GoogleMark()
                                    .frame(width: 18, height: 18)
                                Text("Continue with Google")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .frame(height: 48)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.separator).opacity(0.8), lineWidth: 1)
                        )
                        .foregroundColor(.primary)
                        .disabled(sessionManager.isLoading)
                    }
                    .padding(24)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color(.separator).opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 40)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 24)
                .animation(.easeOut(duration: 0.5), value: hasAppeared)
            }
        )
        .onAppear {
            hasAppeared = true
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let strokeWidth = max(size.width * 0.18, 2.4)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (min(size.width, size.height) - strokeWidth) / 2
            let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)

            func drawArc(start: Double, end: Double, color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                context.stroke(path, with: .color(color), style: style)
            }

            drawArc(start: -45, end: 45, color: Color(red: 0.26, green: 0.52, blue: 0.96))
            drawArc(start: 45, end: 135, color: Color(red: 0.92, green: 0.26, blue: 0.21))
            drawArc(start: 135, end: 225, color: Color(red: 0.98, green: 0.74, blue: 0.02))
            drawArc(start: 225, end: 315, color: Color(red: 0.22, green: 0.74, blue: 0.29))

            var bar = Path()
            bar.move(to: CGPoint(x: center.x, y: center.y))
            bar.addLine(to: CGPoint(x: center.x + radius * 0.6, y: center.y))
            context.stroke(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), style: style)
        }
    }
}
