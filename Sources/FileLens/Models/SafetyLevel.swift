import SwiftUI

/// 文件安全等级枚举
enum SafetyLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case critical   // 不可动 - 系统核心文件
    case caution    // 谨慎 - App 运行文件
    case cleanable  // 可清理 - 缓存/日志
    case safe       // 可整理 - 用户文件

    var id: String { rawValue }

    /// SF Symbols 图标
    var iconName: String {
        switch self {
        case .critical:   return "lock.fill"
        case .caution:    return "exclamationmark.triangle.fill"
        case .cleanable:  return "trash.fill"
        case .safe:       return "checkmark.circle.fill"
        }
    }

    /// 中文标签
    var label: String {
        switch self {
        case .critical:   return "不可动"
        case .caution:    return "谨慎"
        case .cleanable:  return "可清理"
        case .safe:       return "可整理"
        }
    }

    /// 中文说明
    var description: String {
        switch self {
        case .critical:   return "系统核心文件"
        case .caution:    return "应用运行文件"
        case .cleanable:  return "临时文件"
        case .safe:       return "用户文件"
        }
    }

    /// 排序优先级（从危险到安全）
    var sortOrder: Int {
        switch self {
        case .critical:   return 0
        case .caution:    return 1
        case .cleanable:  return 2
        case .safe:       return 3
        }
    }
}
