import SwiftUI

extension Color {
    static let navy = Color(red: 0.039, green: 0.098, blue: 0.184)       // #0a192f
    static let accent = Color(red: 0.976, green: 0.451, blue: 0.086)     // #f97316
    static let okGreen = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let dupRed = Color(red: 0.863, green: 0.149, blue: 0.149)
    static let unknownGray = Color(red: 0.392, green: 0.455, blue: 0.545)
}

enum Haptics {
    static func tick() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
