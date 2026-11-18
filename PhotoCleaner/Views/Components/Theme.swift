import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.49, green: 0.45, blue: 0.98)
    static let scanner = LinearGradient(colors: [Color(red: 0.42, green: 0.27, blue: 0.95),
                                                 Color(red: 0.86, green: 0.25, blue: 0.62)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let swipe = LinearGradient(colors: [Color(red: 0.10, green: 0.62, blue: 0.95),
                                               Color(red: 0.13, green: 0.83, blue: 0.62)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let background = LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.14),
                                                    Color(red: 0.02, green: 0.02, blue: 0.05)],
                                           startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.07)
    static let keep = Color(red: 0.20, green: 0.84, blue: 0.48)
    static let delete = Color(red: 1.00, green: 0.30, blue: 0.36)
    static let skip = Color(red: 0.35, green: 0.62, blue: 1.00)
}

struct ScreenBackground: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

/// Rounded "glass" panel used across screens.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

extension Int {
    var grouped: String {
        NumberFormatter.localizedString(from: NSNumber(value: self), number: .decimal)
    }
}
