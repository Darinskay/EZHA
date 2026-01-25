import SwiftUI

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
    static var magentaTheme: Color {
        Color(red: 0.8, green: 0.2, blue: 0.6)
    }
}
