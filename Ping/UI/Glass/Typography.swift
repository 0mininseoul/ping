import SwiftUI

enum PingFont {
    static let display = Font.system(size: 28, weight: .bold)
    static let wordmark = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 14, weight: .medium)
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
    static let numeric = Font.system(size: 24, weight: .semibold).monospacedDigit()
}
