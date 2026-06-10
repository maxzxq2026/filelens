import Foundation

/// 安全分级服务
/// 负责根据可配置的规则集对文件进行安全等级分类
final class SafetyClassifier: @unchecked Sendable {

    /// 当前加载的规则（按优先级降序）
    private(set) var rules: [ClassificationRule]

    /// 初始化：加载规则
    init(config: ClassificationConfig? = nil) {
        if let config = config {
            self.rules = config.sortedRules
        } else {
            self.rules = Self.defaultConfig().sortedRules
        }
    }

    /// 从 JSON Data 加载规则
    convenience init(jsonData: Data) throws {
        let config = try JSONDecoder().decode(ClassificationConfig.self, from: jsonData)
        self.init(config: config)
    }

    /// 从文件 URL 加载规则
    convenience init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        try self.init(jsonData: data)
    }

    // MARK: - 核心 API

    /// 对单个文件分类
    func classify(file: FileItem) -> SafetyLevel {
        for rule in rules {
            if rule.matches(fileItem: file) {
                return rule.level
            }
        }
        // 兜底：未匹配任何规则 → 可整理
        return .safe
    }

    /// 批量分类，返回更新了 safetyLevel 的文件列表
    func classify(files: [FileItem]) -> [FileItem] {
        files.map { file in
            let level = classify(file: file)
            // 仅当安全等级与初始化不同时重建
            if level == file.safetyLevel {
                return file
            }
            return file.withSafetyLevel(level)
        }
    }

    /// 对已有的 ScanResult 重新分类
    func classify(result: ScanResult) -> ScanResult {
        let classified = classify(files: result.files)
        return ScanResult(
            files: classified,
            totalSize: result.totalSize,
            scanPaths: result.scanPaths,
            scanDuration: result.scanDuration,
            scannedCount: result.scannedCount,
            skippedCount: result.skippedCount
        )
    }

    // MARK: - 规则管理

    /// 动态追加规则
    func addRule(_ rule: ClassificationRule) {
        rules.append(rule)
        rules.sort { $0.priority > $1.priority }
    }

    /// 移除规则
    func removeRule(id: String) {
        rules.removeAll { $0.id == id }
    }

    /// 重新加载配置
    func reload(config: ClassificationConfig) {
        self.rules = config.sortedRules
    }

    /// 导出当前规则为 JSON
    func exportJSON() throws -> Data {
        let config = ClassificationConfig(
            version: "1.0",
            description: "FileLens 安全分级规则",
            rules: rules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    // MARK: - 默认规则

    /// 默认分类规则配置
    static func defaultConfig() -> ClassificationConfig {
        ClassificationConfig(
            version: "1.0",
            description: "FileLens 默认安全分级规则 — 系统目录 > App目录 > 缓存目录 > 用户目录",
            rules: [
                // ========== 🔴 不可动 (priority: 100) ==========
                ClassificationRule(
                    id: "critical-system-dirs",
                    level: .critical,
                    priority: 100,
                    description: "系统核心目录下的所有文件",
                    conditions: [
                        ClassificationCondition(pathMatch: "/System/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/usr/lib/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/usr/bin/", pathMatchType: .prefix),
                    ]
                ),
                ClassificationRule(
                    id: "critical-system-files",
                    level: .critical,
                    priority: 100,
                    description: "系统核心文件名",
                    conditions: [
                        ClassificationCondition(nameMatch: "libSystem", nameMatchType: .contains),
                        ClassificationCondition(nameMatch: "libc++", nameMatchType: .contains),
                        ClassificationCondition(nameMatch: "libobjc", nameMatchType: .contains),
                        ClassificationCondition(nameMatch: "kernel", nameMatchType: .contains),
                    ]
                ),
                ClassificationRule(
                    id: "critical-extensions",
                    level: .critical,
                    priority: 95,
                    description: "内核扩展和驱动",
                    conditions: [
                        ClassificationCondition(extensions: ["kext", "driver"]),
                    ]
                ),

                // ========== 🟠 谨慎 (priority: 70-80) ==========
                ClassificationRule(
                    id: "caution-app-bundles",
                    level: .caution,
                    priority: 80,
                    description: "Applications 下的 .app 包内容",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Applications/", pathMatchType: .prefix),
                    ]
                ),
                ClassificationRule(
                    id: "caution-app-contents",
                    level: .caution,
                    priority: 75,
                    description: "App 包内的结构目录",
                    conditions: [
                        ClassificationCondition(
                            pathMatch: ".app/Contents/",
                            pathMatchType: .contains,
                            nameMatch: "MacOS",
                            nameMatchType: .exact
                        ),
                        ClassificationCondition(
                            pathMatch: ".app/Contents/",
                            pathMatchType: .contains,
                            nameMatch: "Resources",
                            nameMatchType: .exact
                        ),
                        ClassificationCondition(
                            pathMatch: ".app/Contents/",
                            pathMatchType: .contains,
                            nameMatch: "Frameworks",
                            nameMatchType: .exact
                        ),
                    ]
                ),
                ClassificationRule(
                    id: "caution-library-support",
                    level: .caution,
                    priority: 72,
                    description: "用户 Library 下的 App 支持文件",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Library/Application Support/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/Library/Preferences/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/Library/Containers/", pathMatchType: .prefix),
                    ]
                ),
                ClassificationRule(
                    id: "caution-dylib",
                    level: .caution,
                    priority: 70,
                    description: "非系统目录下的动态库",
                    conditions: [
                        ClassificationCondition(extensions: ["dylib"]),
                    ]
                ),

                // ========== 🟡 可清理 (priority: 40-60) ==========
                ClassificationRule(
                    id: "cleanable-cache-dirs",
                    level: .cleanable,
                    priority: 60,
                    description: "缓存和日志目录",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Library/Caches/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/Library/Logs/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/tmp/", pathMatchType: .prefix),
                        ClassificationCondition(pathMatch: "/tmp", pathMatchType: .exact),
                    ]
                ),
                ClassificationRule(
                    id: "cleanable-dev-caches",
                    level: .cleanable,
                    priority: 55,
                    description: "开发工具缓存目录",
                    conditions: [
                        ClassificationCondition(pathMatch: "/.gradle/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/.npm/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/.cargo/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/node_modules/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/__pycache__/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/.cache/", pathMatchType: .contains),
                        ClassificationCondition(pathMatch: "/DerivedData/", pathMatchType: .contains),
                    ]
                ),
                ClassificationRule(
                    id: "cleanable-cache-extensions",
                    level: .cleanable,
                    priority: 50,
                    description: "缓存/临时文件扩展名",
                    conditions: [
                        ClassificationCondition(extensions: ["log", "cache", "tmp", "temp", "bak"]),
                    ]
                ),
                ClassificationRule(
                    id: "cleanable-cache-names",
                    level: .cleanable,
                    priority: 45,
                    description: "文件名包含缓存/临时关键词",
                    conditions: [
                        ClassificationCondition(nameMatch: "cache", nameMatchType: .contains),
                        ClassificationCondition(nameMatch: "temp", nameMatchType: .contains),
                        ClassificationCondition(nameMatch: "log", nameMatchType: .contains),
                    ]
                ),

                // ========== 🟢 可整理 (priority: 10-20) ==========
                ClassificationRule(
                    id: "safe-downloads",
                    level: .safe,
                    priority: 20,
                    description: "下载目录文件",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Downloads/", pathMatchType: .prefix),
                    ]
                ),
                ClassificationRule(
                    id: "safe-desktop",
                    level: .safe,
                    priority: 20,
                    description: "桌面文件",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Desktop/", pathMatchType: .prefix),
                    ]
                ),
                ClassificationRule(
                    id: "safe-documents",
                    level: .safe,
                    priority: 15,
                    description: "文档目录文件",
                    conditions: [
                        ClassificationCondition(pathMatch: "/Documents/", pathMatchType: .prefix),
                    ]
                ),
            ]
        )
    }
}

// MARK: - FileItem 扩展

extension FileItem {
    /// 创建一个仅更新了 safetyLevel 和 description 的新实例
    func withSafetyLevel(_ level: SafetyLevel) -> FileItem {
        let newDesc = FileItem.generateDescription(
            name: name, fileType: fileType, safetyLevel: level
        )
        return FileItem(
            id: id,
            name: name,
            path: path,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            accessedAt: accessedAt,
            fileExtension: fileExtension,
            safetyLevel: level,
            fileType: fileType,
            description: newDesc,
            isDirectory: isDirectory
        )
    }
}
