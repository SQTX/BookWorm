import SwiftUI

extension Color {
    /// The mark of a starred book. Two shades, because one gold cannot be both
    /// legible on white and visible on black: the light one is darkened enough
    /// to read as gold rather than as pale yellow.
    static let gold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.74, blue: 0.35, alpha: 1)
            : UIColor(red: 0.72, green: 0.55, blue: 0.11, alpha: 1)
    })
}
