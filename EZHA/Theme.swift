import SwiftUI

// MARK: - App Colors
// Primary: Magenta - Color(red: 0.8, green: 0.2, blue: 0.6)
// Secondary: Indigo - .indigo

enum AppColors {
    static let primary = Color(red: 0.8, green: 0.2, blue: 0.6)
    static let secondary = Color.indigo
}

extension LinearGradient {
    static var purpleGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.9, green: 0.4, blue: 0.8),  // Light magenta
                Color(red: 0.5, green: 0.2, blue: 0.7)   // Dark purple
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension Color {
    /// Primary app color - magenta for main action buttons
    static let appPrimary = Color(red: 0.8, green: 0.2, blue: 0.6)
    
    /// Secondary app color - indigo for secondary action buttons
    static let appSecondary = Color.indigo
    
    /// Legacy alias for appPrimary
    static var magentaTheme: Color { appPrimary }
}
