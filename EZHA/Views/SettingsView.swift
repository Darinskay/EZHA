import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(role: .destructive) {
                        Task {
                            await sessionManager.signOut()
                        }
                    } label: {
                        Text("Sign out")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
