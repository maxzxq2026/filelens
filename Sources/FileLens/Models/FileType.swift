import Foundation

/// 文件类型枚举
enum FileType: String, Codable, CaseIterable, Identifiable, Hashable {
    case system      // 系统文件
    case application // 应用程序
    case cache       // 缓存
    case document    // 文档
    case image       // 图片
    case video       // 视频
    case audio       // 音频
    case archive     // 压缩包
    case installer   // 安装包
    case code        // 源代码
    case other       // 其他

    var id: String { rawValue }

    /// 中文名称
    var label: String {
        switch self {
        case .system:      return "系统文件"
        case .application: return "应用程序"
        case .cache:       return "缓存文件"
        case .document:    return "文档"
        case .image:       return "图片"
        case .video:       return "视频"
        case .audio:       return "音频"
        case .archive:     return "压缩包"
        case .installer:   return "安装包"
        case .code:        return "源代码"
        case .other:       return "其他"
        }
    }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .system:      return "gearshape.2"
        case .application: return "app.badge"
        case .cache:       return "archivebox"
        case .document:    return "doc.text"
        case .image:       return "photo"
        case .video:       return "film"
        case .audio:       return "music.note"
        case .archive:     return "doc.zipper"
        case .installer:   return "arrow.down.app"
        case .code:        return "chevron.left.forwardslash.chevron.right"
        case .other:       return "questionmark.folder"
        }
    }

    /// 根据文件扩展名推断类型（支持路径上下文判断 .key 等歧义扩展名）
    static func from(extension ext: String, path: String = "") -> FileType {
        let lower = ext.lowercased()
        switch lower {
        // 系统
        case "kext", "dylib", "plist", "sys", "drv":
            return .system
        // 应用
        case "app", "ipa", "apk", "xpc", "framework", "bundle":
            return .application
        // 缓存
        case "cache", "tmp", "temp", "log", "bak":
            return .cache
        // 文档
        case "txt", "md", "pdf", "doc", "docx", "xls", "xlsx",
             "ppt", "pptx", "rtf", "csv", "json", "xml", "yaml",
             "yml", "html", "htm", "pages", "numbers":
            return .document
        // 源代码
        case "swift", "py", "js", "ts", "java", "kt", "c", "cpp",
             "h", "rb", "go", "rs", "sh", "zsh":
            return .code
        // .key 歧义：SSH/keychain 路径视为密钥文件，否则为 Keynote
        case "key":
            let p = path.lowercased()
            if p.contains("/.ssh/") || p.contains("/keychain/") || p.contains("/keychains/") {
                return .other
            }
            return .document
        // 图片
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
             "webp", "svg", "ico", "heic", "heif", "psd", "ai",
             "sketch", "fig", "pxd":
            return .image
        // 视频
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm",
             "m4v", "3gp":
            return .video
        // 音频
        case "mp3", "wav", "aac", "flac", "ogg", "wma", "m4a",
             "opus", "aiff":
            return .audio
        // 压缩包
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz",
             "tgz", "dmg", "iso", "img":
            return .archive
        // 安装包
        case "pkg", "deb", "rpm", "msi", "exe":
            return .installer
        default:
            return .other
        }
    }
}
