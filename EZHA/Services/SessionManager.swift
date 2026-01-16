import Foundation
import SwiftUI

final class SessionManager: ObservableObject {
    @Published var isAuthenticated: Bool = false

    func signIn() {
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
    }
}
