import Foundation

/// 文件信息模型
struct FileItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String           // 文件名
    let path: String           // 完整路径
    let size: Int64            // 文件大小 (bytes)
    let createdAt: Date        // 创建时间
    let modifiedAt: Date       // 修改时间
    let accessedAt: Date       // 访问时间
    let fileExtension: String  // 扩展名
    let safetyLevel: SafetyLevel // 安全等级
    let fileType: FileType     // 文件类型
    let description: String    // 中文说明
    let isDirectory: Bool      // 是否为目录

    /// 格式化后的文件大小
    var formattedSize: String {
        FileItem.byteFormatter.string(fromByteCount: size)
    }

    /// 格式化的创建时间
    var formattedCreated: String {
        FileItem.dateFormatter.string(from: createdAt)
    }

    /// 格式化的修改时间
    var formattedModified: String {
        FileItem.dateFormatter.string(from: modifiedAt)
    }

    /// 完整成员初始化器（用于 withSafetyLevel 等场景）
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        size: Int64,
        createdAt: Date,
        modifiedAt: Date,
        accessedAt: Date,
        fileExtension: String? = nil,
        safetyLevel: SafetyLevel? = nil,
        fileType: FileType? = nil,
        description: String? = nil,
        isDirectory: Bool
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.accessedAt = accessedAt
        self.isDirectory = isDirectory

        let ext = fileExtension ?? URL(fileURLWithPath: name).pathExtension
        self.fileExtension = ext
        self.fileType = fileType ?? FileType.from(extension: ext, path: path)
        self.safetyLevel = safetyLevel ?? FileItem.evaluateSafety(path: path, fileType: self.fileType)
        self.description = description ?? FileItem.generateDescription(
            name: name, fileType: self.fileType, safetyLevel: self.safetyLevel
        )
    }

    // MARK: - 安全等级判定

    /// 初始安全等级判定（仅作为 fallback，SafetyClassifier 会在扫描后重新分类）
    private static func evaluateSafety(path: String, fileType: FileType) -> SafetyLevel {
        let p = path.lowercased()

        // 系统核心路径 → 不可动
        if p.contains("/system/") || p.contains("/usr/") ||
           p.contains("/sbin/") || p.contains("/private/var/db/") ||
           (p.hasPrefix("/library/frameworks/") && p.contains(".framework")) {
            return .critical
        }

        // 应用程序路径 → 谨慎
        if p.contains("/applications/") || p.contains(".app/") ||
           p.contains("/library/application support/") ||
           p.contains("/library/preferences/") {
            return .caution
        }

        // 缓存/日志路径 → 可清理（仅匹配明确的缓存目录，不匹配文件名子串）
        if p.contains("/caches/") || p.contains("/logs/") ||
           p.contains("/tmp/") || p.contains("/.gradle/") ||
           p.contains("/.npm/") || p.contains("/.cargo/") {
            return .cleanable
        }

        // 默认 → 可整理（由 SafetyClassifier 重新精确分类）
        return .safe
    }

    // MARK: - 中文说明生成

    static func generateDescription(
        name: String, fileType: FileType, safetyLevel: SafetyLevel
    ) -> String {
        let typeDesc: String
        switch fileType {
        case .system:      typeDesc = "系统"
        case .application: typeDesc = "应用"
        case .cache:       typeDesc = "缓存"
        case .document:    typeDesc = "文档"
        case .image:       typeDesc = "图片"
        case .video:       typeDesc = "视频"
        case .audio:       typeDesc = "音频"
        case .archive:     typeDesc = "压缩包"
        case .installer:   typeDesc = "安装包"
        case .code:        typeDesc = "源代码"
        case .other:       typeDesc = "其他"
        }

        let safetyDesc: String
        switch safetyLevel {
        case .critical:   safetyDesc = "系统核心，切勿修改"
        case .caution:    safetyDesc = "应用相关，谨慎操作"
        case .cleanable:  safetyDesc = "临时文件，可安全清理"
        case .safe:       safetyDesc = "用户文件，自由管理"
        }

        return "\(typeDesc)文件 · \(safetyDesc)"
    }

    // MARK: - 格式化工具

    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
