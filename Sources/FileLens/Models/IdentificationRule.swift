import Foundation

// MARK: - 识别规则匹配方式

/// 识别规则类型
enum IdentificationMatchType: String, Codable {
    case exactName       // 精确文件名匹配
    case containsName    // 文件名包含关键词
    case fileExtension   // 扩展名匹配
    case pathPrefix      // 路径前缀匹配
    case pathContains    // 路径包含
    case appBundle       // .app 包名匹配
}

// MARK: - 单条识别规则

struct IdentificationRule: Codable, Identifiable {
    let id: String
    let matchType: IdentificationMatchType  // 匹配方式
    let pattern: String                      // 匹配模式
    let description: String                  // 中文说明
    let category: String?                    // 分类标签（可选）

    /// 检查文件是否匹配（统一大小写不敏感）
    func matches(fileItem: FileItem) -> Bool {
        switch matchType {
        case .exactName:
            return fileItem.name.lowercased() == pattern.lowercased()
        case .containsName:
            return fileItem.name.localizedCaseInsensitiveContains(pattern)
        case .fileExtension:
            return fileItem.fileExtension.lowercased() == pattern.lowercased()
        case .pathPrefix:
            return fileItem.path.lowercased().hasPrefix(pattern.lowercased())
        case .pathContains:
            return fileItem.path.localizedCaseInsensitiveContains(pattern)
        case .appBundle:
            // 匹配 /Applications/XXX.app 或路径中包含 XXX.app/
            // 对特殊字符（如 +、.、() 等）进行转义，避免误匹配
            let appPattern = pattern.hasSuffix(".app") ? pattern : pattern + ".app"
            let escaped = NSRegularExpression.escapedPattern(for: appPattern)
            let pathLower = fileItem.path.lowercased()
            let appLower = appPattern.lowercased()
            let regex = try? NSRegularExpression(pattern: "/\(escaped)/|/\(escaped)$", options: .caseInsensitive)
            let range = NSRange(pathLower.startIndex..., in: pathLower)
            return (regex?.firstMatch(in: pathLower, range: range) != nil) ||
                   fileItem.name.lowercased() == appLower
        }
    }
}

// MARK: - 识别配置

struct IdentificationConfig: Codable {
    let version: String
    let description: String
    let rules: [IdentificationRule]
}
