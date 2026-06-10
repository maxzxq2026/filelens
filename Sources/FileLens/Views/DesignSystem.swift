import SwiftUI

enum FL {
    static let accent = Color.accentColor
    static let background = Color(nsColor: .windowBackgroundColor)
    static let text = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let textQuaternary = Color(nsColor: .quaternaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)

    static let titleFont = Font.system(size: 14, weight: .semibold)
    static let headlineFont = Font.system(size: 13, weight: .medium)
    static let bodyFont = Font.system(size: 13)
    static let captionFont = Font.system(size: 11)
    static let microFont = Font.system(size: 10)
    static let monoFont = Font.system(size: 11, design: .monospaced)

    static let paddingXS: CGFloat = 4
    static let paddingS: CGFloat = 8
    static let paddingM: CGFloat = 12
    static let paddingL: CGFloat = 16

    static let smallRadius: CGFloat = 6
    static let mediumRadius: CGFloat = 8
    static let capsuleRadius: CGFloat = 20

    static let windowWidth: CGFloat = 420

    // 以下属性仍被视图引用，保留
    static let destructive = Color.red
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardRadius: CGFloat = 8
    static let cardShadow = Color.primary.opacity(0.06)

    // 安全等级颜色（macOS 系统色，自适应暗色模式）
    static let criticalColor = Color(nsColor: .systemRed)
    static let cautionColor = Color(nsColor: .systemOrange)
    static let cleanableColor = Color(nsColor: .systemTeal)
    static let safeColor = Color(nsColor: .systemGreen)
}

// MARK: - 安全等级颜色扩展

extension SafetyLevel {
    var flColor: Color {
        switch self {
        case .critical:  return FL.criticalColor
        case .caution:   return FL.cautionColor
        case .cleanable: return FL.cleanableColor
        case .safe:      return FL.safeColor
        }
    }

    var color: Color {
        switch self {
        case .critical:   return Color(nsColor: .systemRed)
        case .caution:    return Color(nsColor: .systemOrange)
        case .cleanable:  return Color(nsColor: .systemTeal)
        case .safe:       return Color(nsColor: .systemGreen)
        }
    }
}
