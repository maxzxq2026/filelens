import Foundation

/// 一键整理服务
/// 将桌面/下载目录的文件按类型自动归类到子文件夹
final class FileOrganizer: @unchecked Sendable {

    static let shared = FileOrganizer()

    private let fileManager = FileManager.default
    private let storage = StorageService.shared

    /// 上次执行的整理动作（用于撤销），用 NSLock 保护
    private var lastActions: [OrganizeAction] = []
    private let actionsLock = NSLock()

    // MARK: - 整理规则

    /// 文件类型 → 目标文件夹名
    static let organizeRules: [(extensions: [String], folder: String)] = [
        (["pdf", "doc", "docx", "txt", "rtf", "xls", "xlsx",
          "ppt", "pptx", "csv", "pages", "numbers", "key",
          "md", "json", "xml", "yaml", "yml", "html", "htm"], "文档"),

        (["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
          "webp", "svg", "heic", "heif", "ico", "psd", "ai",
          "sketch", "fig", "raw", "cr2", "nef", "arw", "dng"], "图片"),

        (["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm",
          "m4v", "3gp", "mpg", "mpeg", "mts", "mxf"], "视频"),

        (["mp3", "wav", "aac", "flac", "ogg", "wma", "m4a",
          "opus", "aiff", "alac", "mid", "midi"], "音频"),

        (["zip", "rar", "7z", "tar", "gz", "bz2", "xz",
          "tgz", "tbz2", "zst", "lz4", "iso"], "压缩包"),

        (["dmg", "pkg", "mpkg", "deb", "rpm", "msi", "exe",
          "app", "ipa", "apk"], "安装包"),
    ]

    /// 根据扩展名获取目标文件夹
    static func targetFolder(for ext: String) -> String {
        let lower = ext.lowercased()
        for rule in organizeRules {
            if rule.extensions.contains(lower) {
                return rule.folder
            }
        }
        return "其他"
    }

    // MARK: - 生成整理方案

    /// 检查目录是否在 iCloud Drive 中
    private func isICloudDirectory(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/Mobile Documents/") || path.contains("/iCloud~")
    }

    /// 为文件列表生成整理方案
    func generatePlan(for files: [StoredFile]) -> [OrganizeAction] {
        guard let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return [] }

        // 如果 Desktop 在 iCloud 中，提示用户
        if isICloudDirectory(desktop) {
            print("[FileLens] 注意：桌面目录位于 iCloud Drive 中，移动文件将触发 iCloud 同步")
        }

        return files.compactMap { file -> OrganizeAction? in
            // 只整理 safe 等级的文件
            guard file.safetyLevel == "safe" else {
                return OrganizeAction(
                    file: file,
                    destination: desktop,
                    action: .skip,
                    targetFolder: Self.targetFolder(for: file.fileExtension)
                )
            }

            let folder = Self.targetFolder(for: file.fileExtension)
            let targetDir = desktop.appendingPathComponent(folder)
            let destination = targetDir.appendingPathComponent(file.name)

            // 检查是否冲突
            let hasConflict = fileManager.fileExists(atPath: destination.path)

            return OrganizeAction(
                file: file,
                destination: destination,
                action: hasConflict ? .conflict : .move,
                targetFolder: folder
            )
        }
    }

    /// 生成预览
    func previewPlan(_ plan: [OrganizeAction]) -> OrganizePreview {
        OrganizePreview(actions: plan)
    }

    // MARK: - 执行整理

    /// 执行整理方案（只执行 .move，跳过 .conflict 等待用户确认）
    func executePlan(_ plan: [OrganizeAction]) async throws {
        guard let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let actionsToExecute = plan.filter { $0.action == .move }

        // 记录成功移动的动作（用于撤销），逐个追加避免中途失败导致级联错误
        actionsLock.lock()
        lastActions = []
        actionsLock.unlock()

        for action in actionsToExecute {
            let sourceURL = URL(fileURLWithPath: action.file.path)
            let targetDir = desktop.appendingPathComponent(action.targetFolder)

            // 创建目标目录
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

            // 解决冲突
            let finalDest = action.resolvedDestination

            // 移动文件
            try fileManager.moveItem(at: sourceURL, to: finalDest)

            // 成功后记录到撤销列表
            actionsLock.lock()
            lastActions.append(action)
            actionsLock.unlock()

            // 更新存储中的路径
            if let storedFile = storage.loadFiles().first(where: { $0.id == action.file.id }) {
                let updated = StoredFile(
                    id: storedFile.id,
                    name: storedFile.name,
                    path: finalDest.path,
                    size: storedFile.size,
                    createdAt: storedFile.createdAt,
                    modifiedAt: storedFile.modifiedAt,
                    accessedAt: storedFile.accessedAt,
                    fileExtension: storedFile.fileExtension,
                    safetyLevel: storedFile.safetyLevel,
                    fileType: storedFile.fileType,
                    description: storedFile.description,
                    scannedAt: storedFile.scannedAt,
                    isDeleted: false
                )
                storage.updateFile(updated)
            }
        }
    }

    // MARK: - 撤销

    /// 撤销上次整理
    func undoLastPlan() throws {
        actionsLock.lock()
        guard !lastActions.isEmpty else { actionsLock.unlock(); return }
        let actionsSnapshot = lastActions
        actionsLock.unlock()

        for action in actionsSnapshot.reversed() {
            let sourceURL = URL(fileURLWithPath: action.originalPath)   // 原始位置（显式保存）
            let currentURL = action.resolvedDestination                 // 当前位置

            guard fileManager.fileExists(atPath: currentURL.path) else { continue }

            // 确保原始目录存在
            let sourceDir = sourceURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)

            // 如果原始位置已存在，解决冲突
            let finalSource: URL
            if fileManager.fileExists(atPath: sourceURL.path) {
                finalSource = OrganizeAction.resolveConflict(sourceURL)
            } else {
                finalSource = sourceURL
            }

            // 移回原位
            try fileManager.moveItem(at: currentURL, to: finalSource)

            // 更新存储
            if let storedFile = storage.loadFiles().first(where: { $0.id == action.file.id }) {
                let updated = StoredFile(
                    id: storedFile.id,
                    name: storedFile.name,
                    path: finalSource.path,
                    size: storedFile.size,
                    createdAt: storedFile.createdAt,
                    modifiedAt: storedFile.modifiedAt,
                    accessedAt: storedFile.accessedAt,
                    fileExtension: storedFile.fileExtension,
                    safetyLevel: storedFile.safetyLevel,
                    fileType: storedFile.fileType,
                    description: storedFile.description,
                    scannedAt: storedFile.scannedAt,
                    isDeleted: false
                )
                storage.updateFile(updated)
            }
        }

        actionsLock.lock()
        lastActions.removeAll()
        actionsLock.unlock()
    }

    /// 是否可以撤销
    var canUndo: Bool {
        actionsLock.lock()
        defer { actionsLock.unlock() }
        return !lastActions.isEmpty
    }
}
