import Foundation

/// 整理动作类型
enum ActionType: String, Codable {
    case move      // 移动文件
    case skip      // 跳过（非 safe 等级）
    case conflict  // 冲突（目标已存在同名文件，将自动重命名）
}

/// 单个整理动作
struct OrganizeAction: Identifiable {
    let id = UUID()
    let file: StoredFile
    let originalPath: String  // 文件整理前的原始路径（用于撤销）
    let destination: URL
    let action: ActionType
    let targetFolder: String   // 目标文件夹名称（如 "文档"、"图片"）
    let resolvedDestination: URL  // 最终实际目标（初始化时一次性计算）

    init(file: StoredFile, destination: URL, action: ActionType, targetFolder: String) {
        self.file = file
        self.originalPath = file.path
        self.destination = destination
        self.action = action
        self.targetFolder = targetFolder
        // 初始化时计算一次，避免 SwiftUI diff 时重复触发文件 I/O
        self.resolvedDestination = action == .conflict
            ? OrganizeAction.resolveConflict(destination)
            : destination
    }
}

extension OrganizeAction {
    /// 常见的双扩展名（需要整体保留）
    private static let doubleExtensions: Set<String> = [
        "tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz4",
    ]

    /// 解决文件名冲突，自动添加序号（最多尝试 100 次防止死循环）
    static func resolveConflict(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let fullName = url.lastPathComponent

        // 检测双扩展名（如 .tar.gz）
        let (baseName, fullExt) = splitDoubleExtension(fullName)

        let maxRetries = 100
        var counter = 1
        var candidate: URL
        repeat {
            let newName = fullExt.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(fullExt)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        } while fm.fileExists(atPath: candidate.path) && counter <= maxRetries

        return candidate
    }

    /// 分离文件名和可能的双扩展名
    private static func splitDoubleExtension(_ filename: String) -> (baseName: String, ext: String) {
        for doubleExt in doubleExtensions {
            if filename.lowercased().hasSuffix(".\(doubleExt)") {
                let baseEnd = filename.index(filename.endIndex, offsetBy: -(doubleExt.count + 1))
                let baseName = String(filename[..<baseEnd])
                let ext = String(filename[filename.index(after: baseEnd)...])
                return (baseName, ext)
            }
        }
        // 单扩展名或无扩展名
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        return (baseName, ext)
    }
}

/// 整理预览
struct OrganizePreview {
    let actions: [OrganizeAction]

    /// 按目标文件夹分组
    var groupedByFolder: [String: [OrganizeAction]] {
        Dictionary(grouping: actions, by: \.targetFolder)
    }

    /// 需要移动的文件数
    var moveCount: Int {
        actions.filter { $0.action == .move }.count
    }

    /// 冲突文件数
    var conflictCount: Int {
        actions.filter { $0.action == .conflict }.count
    }

    /// 跳过的文件数
    var skipCount: Int {
        actions.filter { $0.action == .skip }.count
    }

    /// 总移动大小
    var totalMoveSize: Int64 {
        actions.filter { $0.action == .move || $0.action == .conflict }
            .reduce(0) { $0 + $1.file.size }
    }

    /// 格式化的总大小
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalMoveSize, countStyle: .file)
    }
}
