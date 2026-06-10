import Foundation

// MARK: - 规则匹配条件

/// 路径匹配方式
enum PathMatchType: String, Codable {
    case prefix    // 路径前缀匹配
    case contains  // 路径包含匹配
    case suffix    // 路径后缀匹配
    case exact     // 精确匹配
}

/// 文件名匹配方式
enum NameMatchType: String, Codable {
    case contains  // 文件名包含
    case exact     // 文件名精确匹配
    case prefix    // 文件名前缀
    case suffix    // 文件名后缀（含扩展名）
    case ext       // 扩展名匹配
}

/// 分类规则匹配条件
struct ClassificationCondition: Codable {
    /// 路径匹配（完整路径）
    var pathMatch: String?
    var pathMatchType: PathMatchType = .prefix

    /// 文件名匹配
    var nameMatch: String?
    var nameMatchType: NameMatchType = .contains

    /// 扩展名列表（任一匹配即可）
    var extensions: [String]?
}

// MARK: - 分类规则

/// 单条分类规则
struct ClassificationRule: Codable, Identifiable {
    let id: String
    let level: SafetyLevel           // 目标安全等级
    let priority: Int                // 优先级（越大越优先，同级按数组顺序）
    let description: String          // 规则说明（中文）
    let conditions: [ClassificationCondition] // 条件列表（OR 关系）

    /// 检查文件是否匹配此规则
    func matches(fileItem: FileItem) -> Bool {
        for condition in conditions {
            if matchCondition(condition, fileItem: fileItem) {
                return true
            }
        }
        return false
    }

    /// 匹配单个条件
    private func matchCondition(_ cond: ClassificationCondition, fileItem: FileItem) -> Bool {
        let path = fileItem.path
        let name = fileItem.name
        let ext = fileItem.fileExtension.lowercased()

        // 扩展名匹配（如果指定了扩展名，必须匹配其一，否则直接跳过此条件）
        if let exts = cond.extensions {
            let lowerExts = exts.map { $0.lowercased() }
            if !lowerExts.contains(ext) {
                return false  // 扩展名不匹配，无论是否有路径/名称条件都跳过
            }
            // 扩展名匹配了，如果还有路径或名称条件，需要同时满足
            if cond.pathMatch != nil || cond.nameMatch != nil {
                return matchAdditionalConditions(cond, path: path, name: name, fileExt: ext)
            }
            return true  // 仅扩展名匹配即通过
        }

        return matchAdditionalConditions(cond, path: path, name: name, fileExt: ext)
    }

    /// 匹配路径和名称条件（统一大小写不敏感）
    private func matchAdditionalConditions(
        _ cond: ClassificationCondition,
        path: String,
        name: String,
        fileExt: String
    ) -> Bool {
        var pathMatched = cond.pathMatch == nil // 无路径条件时视为满足
        var nameMatched = cond.nameMatch == nil  // 无名称条件时视为满足

        let pathLower = path.lowercased()
        let nameLower = name.lowercased()

        // 路径匹配（全部大小写不敏感）
        if let pattern = cond.pathMatch {
            let p = pattern.lowercased()
            switch cond.pathMatchType {
            case .prefix:
                pathMatched = pathLower.hasPrefix(p)
            case .contains:
                pathMatched = pathLower.contains(p)
            case .suffix:
                pathMatched = pathLower.hasSuffix(p)
            case .exact:
                pathMatched = pathLower == p
            }
        }

        // 文件名匹配（全部大小写不敏感）
        if let pattern = cond.nameMatch {
            let p = pattern.lowercased()
            switch cond.nameMatchType {
            case .contains:
                nameMatched = nameLower.contains(p)
            case .exact:
                nameMatched = nameLower == p
            case .prefix:
                nameMatched = nameLower.hasPrefix(p)
            case .suffix:
                nameMatched = nameLower.hasSuffix(p)
            case .ext:
                nameMatched = fileExt == p
            }
        }

        return pathMatched && nameMatched
    }
}

// MARK: - 规则配置文件

/// 完整的分类规则配置
struct ClassificationConfig: Codable {
    let version: String
    let description: String
    let rules: [ClassificationRule]

    /// 按优先级排序后的规则
    var sortedRules: [ClassificationRule] {
        rules.sorted { $0.priority > $1.priority }
    }
}
