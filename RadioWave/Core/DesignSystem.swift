import SwiftUI

extension Color {
    static let radioGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let radioOrange = Color(red: 1.0, green: 0.584, blue: 0)
    static let radioBlue = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let surfacePrimary = Color(red: 0.11, green: 0.11, blue: 0.118)
    static let surfaceSecondary = Color(red: 0.17, green: 0.17, blue: 0.18)
}

extension Font {
    static let radioFrequency = Font.system(.largeTitle, design: .monospaced).weight(.medium)
    static let radioLabel = Font.system(size: 10, design: .monospaced).weight(.medium)
    static let radioBody = Font.system(size: 12)
    static let radioCaption = Font.system(size: 10, design: .monospaced)
}
