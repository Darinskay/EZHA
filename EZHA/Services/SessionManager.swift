import Foundation
import Supabase
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
        observeAuthChanges()
        Task { await refreshSession() }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signIn(email: String, password: String) async {
        await performAuth {
            _ = try await self.supabase.auth.signIn(email: email, password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await performAuth {
            _ = try await self.supabase.auth.signUp(email: email, password: password)
        }
    }

    func signInWithGoogle() async {
        await performAuth {
            _ = try await self.supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.oauthRedirectURL
            )
        }
    }

    func signOut() async {
        await performAuth {
            try await self.supabase.auth.signOut()
        }
    }

    private func observeAuthChanges() {
        authStateTask = Task {
            for await state in self.supabase.auth.authStateChanges {
                isAuthenticated = state.session != nil
            }
        }
    }

    private func refreshSession() async {
        do {
            _ = try await supabase.auth.session
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    private func performAuth(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
