import Foundation

/// 文件识别服务
/// 为每个文件生成精确的中文说明，覆盖系统文件、App、扩展名、目录等
final class FileIdentifier: @unchecked Sendable {

    /// 识别规则（按优先级：精确文件名 > App包名 > 路径 > 扩展名）
    private(set) var rules: [IdentificationRule]

    /// App 包名 → 中文名映射（快速查找）
    private var appNames: [String: String]

    init(config: IdentificationConfig? = nil) {
        if let config = config {
            self.rules = config.rules
            self.appNames = [:]
            for rule in config.rules where rule.matchType == .appBundle {
                appNames[rule.pattern] = rule.description
            }
        } else {
            let defaultConfig = Self.defaultConfig()
            self.rules = defaultConfig.rules
            self.appNames = Self.defaultAppNames()
        }
    }

    convenience init(jsonData: Data) throws {
        let config = try JSONDecoder().decode(IdentificationConfig.self, from: jsonData)
        self.init(config: config)
    }

    convenience init(configURL: URL) throws {
        let data = try Data(contentsOf: configURL)
        try self.init(jsonData: data)
    }

    // MARK: - 核心 API

    /// 识别单个文件，返回中文说明
    func identify(file: FileItem) -> String {
        // 1. 精确文件名匹配（系统文件）
        for rule in rules where rule.matchType == .exactName {
            if rule.matches(fileItem: file) {
                return rule.description
            }
        }

        // 2. App 包名匹配
        if let appDesc = matchAppBundle(file: file) {
            return appDesc
        }

        // 3. 文件名包含关键词匹配
        for rule in rules where rule.matchType == .containsName {
            if rule.matches(fileItem: file) {
                return rule.description
            }
        }

        // 4. 路径匹配（目录识别）
        for rule in rules where rule.matchType == .pathPrefix || rule.matchType == .pathContains {
            if rule.matches(fileItem: file) {
                return rule.description
            }
        }

        // 5. 上下文感知的扩展名匹配（处理歧义扩展名）
        if file.fileExtension.lowercased() == "key" {
            let pathLower = file.path.lowercased()
            if pathLower.contains("/.ssh/") || pathLower.contains("/keychain") ||
               pathLower.contains("/certificates/") || pathLower.contains("/credentials/") {
                return "密钥文件"
            }
            return "Keynote 演示文稿"
        }

        // 6. 扩展名匹配
        for rule in rules where rule.matchType == .fileExtension {
            if rule.matches(fileItem: file) {
                return rule.description
            }
        }

        // 6. 兜底
        let ext = file.fileExtension
        if ext.isEmpty {
            return file.isDirectory ? "文件夹" : "未知文件"
        }
        return "未知文件类型 (.\(ext))"
    }

    /// 批量识别，返回更新了 description 的文件列表
    func identify(files: [FileItem]) -> [FileItem] {
        files.map { file in
            let desc = identify(file: file)
            if desc == file.description { return file }
            return file.withDescription(desc)
        }
    }

    /// 对 ScanResult 重新识别
    func identify(result: ScanResult) -> ScanResult {
        let identified = identify(files: result.files)
        return ScanResult(
            files: identified,
            totalSize: result.totalSize,
            scanPaths: result.scanPaths,
            scanDuration: result.scanDuration,
            scannedCount: result.scannedCount,
            skippedCount: result.skippedCount
        )
    }

    // MARK: - App 包匹配

    private func matchAppBundle(file: FileItem) -> String? {
        let path = file.path
        let name = file.name

        // 从路径中提取 App 名称: /Applications/XXX.app/...
        if let range = path.range(of: ".app/") {
            let beforeApp = String(path[path.startIndex..<range.lowerBound])
            if let slashIndex = beforeApp.lastIndex(of: "/") {
                let appName = String(beforeApp[beforeApp.index(after: slashIndex)...])
                let appKey = appName.hasSuffix(".app") ? String(appName.dropLast(4)) : appName
                if let desc = appNames[appKey] {
                    return desc + (file.isDirectory ? " 内部目录" : "")
                }
                return appName.replacingOccurrences(of: ".app", with: "") + " 应用程序文件"
            }
        }

        // 直接匹配 .app 包本身
        if name.hasSuffix(".app") {
            let appName = String(name.dropLast(4))
            return appNames[appName] ?? appName + " 应用程序"
        }

        return nil
    }

    // MARK: - 规则管理

    func reload(config: IdentificationConfig) {
        self.rules = config.rules
        self.appNames = [:]
        for rule in config.rules where rule.matchType == .appBundle {
            appNames[rule.pattern] = rule.description
        }
    }

    func exportJSON() throws -> Data {
        let config = IdentificationConfig(
            version: "1.0",
            description: "FileLens 文件识别规则",
            rules: rules
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    // MARK: - App 名称映射

    private static func defaultAppNames() -> [String: String] {
        [
            // 开发工具
            "Xcode": "Xcode 开发工具",
            "Visual Studio Code": "VS Code 代码编辑器",
            "IntelliJ IDEA": "IntelliJ IDEA 开发工具",
            "IntelliJ IDEA CE": "IntelliJ IDEA 社区版",
            "Android Studio": "Android Studio 开发工具",
            "PyCharm": "PyCharm Python IDE",
            "WebStorm": "WebStorm 前端 IDE",
            "CLion": "CLion C/C++ IDE",
            "DataGrip": "DataGrip 数据库工具",
            "Terminal": "终端",
            "iTerm2": "iTerm2 终端",
            "Warp": "Warp 终端",
            "Hyper": "Hyper 终端",
            "Git": "Git 版本控制",
            "GitHub Desktop": "GitHub 桌面客户端",
            "Sourcetree": "Sourcetree Git 客户端",
            "Postman": "Postman API 调试工具",
            "Docker": "Docker 容器工具",
            "OrbStack": "OrbStack 容器/VM 工具",

            // 浏览器
            "Safari": "Safari 浏览器",
            "Google Chrome": "Chrome 浏览器",
            "Firefox": "Firefox 浏览器",
            "Arc": "Arc 浏览器",
            "Microsoft Edge": "Edge 浏览器",
            "Brave Browser": "Brave 浏览器",
            "Opera": "Opera 浏览器",
            "Chromium": "Chromium 浏览器",

            // 办公
            "Microsoft Word": "Word 文档编辑",
            "Microsoft Excel": "Excel 表格",
            "Microsoft PowerPoint": "PowerPoint 演示",
            "Microsoft Outlook": "Outlook 邮件客户端",
            "Microsoft Teams": "Teams 协作工具",
            "Pages": "Pages 文稿",
            "Numbers": "Numbers 表格",
            "Keynote": "Keynote 演示",
            "WPS": "WPS Office 办公套件",
            "Notion": "Notion 笔记协作",
            "Obsidian": "Obsidian 知识管理",
            "Bear": "Bear 笔记",
            "Typora": "Typora Markdown 编辑器",
            "Craft": "Craft 文档编辑",

            // 设计/创意
            "Blender": "Blender 3D建模软件",
            "Figma": "Figma 设计工具",
            "Sketch": "Sketch 设计工具",
            "Adobe Photoshop": "Photoshop 图像处理",
            "Adobe Illustrator": "Illustrator 矢量设计",
            "Adobe Premiere Pro": "Premiere 视频剪辑",
            "Adobe After Effects": "After Effects 特效制作",
            "Adobe Lightroom": "Lightroom 照片处理",
            "Affinity Designer": "Affinity Designer 矢量设计",
            "Affinity Photo": "Affinity Photo 图像处理",
            "Affinity Publisher": "Affinity Publisher 排版",
            "Pixelmator Pro": "Pixelmator Pro 图像编辑",
            "Canva": "Canva 在线设计",
            "DaVinci Resolve": "DaVinci Resolve 视频调色",
            "Final Cut Pro": "Final Cut Pro 视频剪辑",
            "Logic Pro": "Logic Pro 音乐制作",
            "GarageBand": "GarageBand 音乐创作",
            "MainStage": "MainStage 现场演出",

            // 社交/通讯
            "WeChat": "微信",
            "Telegram": "Telegram 即时通讯",
            "Discord": "Discord 社区语音",
            "Slack": "Slack 团队协作",
            "QQ": "QQ 即时通讯",
            "钉钉": "钉钉 办公协作",
            "飞书": "飞书 办公协作",
            "WhatsApp": "WhatsApp 即时通讯",
            "Signal": "Signal 加密通讯",
            "Zoom": "Zoom 视频会议",
            "腾讯会议": "腾讯会议",
            "Skype": "Skype 通讯",

            // 媒体
            "IINA": "IINA 视频播放器",
            "VLC": "VLC 媒体播放器",
            "Spotify": "Spotify 音乐播放",
            "Apple Music": "Apple Music 音乐",
            "Apple TV": "Apple TV 视频",
            "爱奇艺": "爱奇艺 视频",
            "NeteaseMusic": "网易云音乐",
            "QQMusic": "QQ 音乐",

            // 系统工具
            "Activity Monitor": "活动监视器",
            "Disk Utility": "磁盘工具",
            "System Settings": "系统设置",
            "System Preferences": "系统偏好设置",
            "Finder": "访达",
            "Preview": "预览",
            "TextEdit": "文本编辑",
            "Calendar": "日历",
            "Contacts": "通讯录",
            "Notes": "备忘录",
            "Reminders": "提醒事项",
            "Maps": "地图",
            "Photos": "照片",
            "FaceTime": "FaceTime 视频通话",
            "Messages": "信息",
            "Mail": "邮件",
            "Books": "图书",
            "Podcasts": "播客",
            "Voice Memos": "语音备忘录",
            "Shortcuts": "快捷指令",
            "Automator": "自动操作",
            "Script Editor": "脚本编辑器",
            "Keychain Access": "钥匙串访问",
            "Console": "控制台",
            "Boot Camp Assistant": "Boot Camp 助理",
            "Migration Assistant": "迁移助理",
            "Time Machine": "时间机器",

            // 第三方工具
            "1Password": "1Password 密码管理",
            "CleanMyMac": "CleanMyMac 系统清理",
            "The Unarchiver": "The Unarchiver 解压工具",
            "Keka": "Keka 压缩工具",
            "Raycast": "Raycast 效率启动器",
            "Alfred": "Alfred 效率工具",
            "Karabiner-Elements": "Karabiner 键盘自定义",
            "Stats": "Stats 系统监控",
            "iStat Menus": "iStat Menus 系统监控",
            "AppCleaner": "AppCleaner 应用卸载",
            "Downie": "Downie 视频下载",
            "Permute": "Permute 媒体转换",
            "BetterTouchTool": "BetterTouchTool 手势增强",
            "Bartender": "Bartender 菜单栏管理",
            "Magnet": "Magnet 窗口管理",
            "Rectangle": "Rectangle 窗口管理",
            "Logi Options+": "罗技 Options+ 外设管理",

            // 下载/传输
            "Thunder": "迅雷下载",
            "qBittorrent": "qBittorrent 下载",
            "FileZilla": "FileZilla FTP 客户端",
            "Transmit": "Transmit 文件传输",
            "Cyberduck": "Cyberduck 文件传输",

            // 虚拟化
            "VMware Fusion": "VMware Fusion 虚拟机",
            "Parallels Desktop": "Parallels 虚拟机",
            "UTM": "UTM 虚拟机",
            "VirtualBox": "VirtualBox 虚拟机",
        ]
    }

    // MARK: - 默认配置

    static func defaultConfig() -> IdentificationConfig {
        IdentificationConfig(
            version: "1.0",
            description: "FileLens 默认文件识别规则库（100+ 规则）",
            rules: buildRules()
        )
    }

    /// 构建完整规则库
    private static func buildRules() -> [IdentificationRule] {
        var rules: [IdentificationRule] = []

        // ====== 1. 精确文件名 — 系统核心文件 ======
        let systemFiles: [(String, String)] = [
            ("libSystem.B.dylib", "macOS 系统核心运行库"),
            ("libSystem.dylib", "macOS 系统核心运行库"),
            ("kernel", "系统内核文件"),
            ("kernelmanagerd", "内核管理守护进程"),
            ("launchd", "系统启动守护进程"),
            ("launchctl", "启动控制工具"),
            ("dyld", "动态链接器"),
            ("dyld_shared_cache", "动态链接共享缓存"),
            ("libobjc.A.dylib", "Objective-C 运行时库"),
            ("libc++.1.dylib", "C++ 标准库"),
            ("libc++abi.dylib", "C++ ABI 库"),
            ("libdispatch.dylib", "GCD 调度库"),
            ("libxpc.dylib", "XPC 通信库"),
            ("libz.1.dylib", "zlib 压缩库"),
            ("libcurl.4.dylib", "cURL 网络库"),
            ("libsqlite3.dylib", "SQLite 数据库库"),
            ("libcrypto.dylib", "OpenSSL 加密库"),
            ("libssl.dylib", "SSL/TLS 库"),
            ("libiconv.dylib", "字符编码转换库"),
            ("libxml2.dylib", "XML 解析库"),
            ("libpthread.dylib", "POSIX 线程库"),
            ("libcups.dylib", "CUPS 打印库"),
            ("libauto.dylib", "自动回收库"),
            ("libDiagnosticMessagesClient.dylib", "诊断消息客户端库"),
            ("sandboxd", "沙盒守护进程"),
            ("syslogd", "系统日志守护进程"),
            ("WindowServer", "窗口服务器"),
            ("Dock", "程序坞"),
            ("SystemUIServer", "系统 UI 服务"),
            ("cfprefsd", "偏好设置守护进程"),
            ("distnoted", "分布式通知守护进程"),
            ("securityd", "安全守护进程"),
            ("mds", "元数据搜索服务"),
            ("mds_stores", "元数据存储服务"),
            ("mdworker", "Spotlight 索引工作进程"),
            ("spotlight", "Spotlight 搜索"),
            ("iconservicesagent", "图标服务代理"),
            ("fontd", "字体守护进程"),
            ("lsd", "启动服务守护进程"),
            ("UserEventAgent", "用户事件代理"),
            ("loginwindow", "登录窗口"),
            ("bluetoothd", "蓝牙守护进程"),
            ("airportd", "Wi-Fi 守护进程"),
            ("coreaudiod", "核心音频守护进程"),
            ("hidd", "人机接口设备守护进程"),
            ("powerd", "电源管理守护进程"),
            ("diskarbitrationd", "磁盘仲裁守护进程"),
            ("fseventsd", "文件系统事件守护进程"),
            ("configd", "系统配置守护进程"),
            ("notifyd", "通知守护进程"),
            ("coreservicesd", "核心服务守护进程"),
            ("opendirectoryd", "开放目录守护进程"),
            ("deleted", "废纸篓清理守护进程"),
            ("kbdblayoutd", "键盘布局守护进程"),
            ("tccd", "透明度同意控制守护进程"),
            ("rtcreportingd", "RTC 报告守护进程"),
            ("endpointsecurity", "终端安全守护进程"),
        ]
        for (name, desc) in systemFiles {
            rules.append(IdentificationRule(
                id: "sys-\(name)", matchType: .exactName,
                pattern: name, description: desc, category: "系统核心"
            ))
        }

        // ====== 2. 文件名包含关键词 — 系统/开发相关 ======
        let nameKeywords: [(String, String)] = [
            ("libSystem", "macOS 系统运行库"),
            ("libc++", "C++ 标准库"),
            ("libobjc", "Objective-C 运行时库"),
            ("libdispatch", "GCD 并发库"),
            ("libsqlite", "SQLite 数据库库"),
            ("libcrypto", "加密库"),
            ("libssl", "SSL/TLS 安全库"),
            ("libcurl", "网络请求库"),
            ("libxml", "XML 解析库"),
            ("libz", "压缩库"),
            ("libiconv", "编码转换库"),
            ("libicu", "国际化组件库"),
            ("libclang", "Clang 编译器库"),
            ("libLLVM", "LLVM 编译器库"),
            ("libswift", "Swift 运行时库"),
            ("libpthread", "POSIX 线程库"),
            ("libnetwork", "网络库"),
            ("libpcap", "网络抓包库"),
            ("libffi", "外部函数接口库"),
            ("kernel", "内核相关文件"),
            ("boot", "启动相关文件"),
            ("firmware", "固件文件"),
        ]
        for (keyword, desc) in nameKeywords {
            rules.append(IdentificationRule(
                id: "name-\(keyword)", matchType: .containsName,
                pattern: keyword, description: desc, category: "系统库"
            ))
        }

        // ====== 3. 目录路径识别 ======
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories: [(String, String)] = [
            ("\(home)/Downloads/", "下载目录"),
            ("\(home)/Desktop/", "桌面文件"),
            ("\(home)/Documents/", "文稿目录"),
            ("\(home)/Library/Caches/", "应用缓存目录"),
            ("\(home)/Library/Logs/", "应用日志目录"),
            ("\(home)/Library/Preferences/", "应用偏好设置目录"),
            ("\(home)/Library/Application Support/", "应用支持文件目录"),
            ("\(home)/Library/Containers/", "应用沙盒容器目录"),
            ("\(home)/Library/Group Containers/", "应用组容器目录"),
            ("\(home)/Library/Saved Application State/", "应用状态保存目录"),
            ("\(home)/Library/HTTPStorages/", "HTTP 存储目录"),
            ("\(home)/Library/Cookies/", "Cookie 存储目录"),
            ("\(home)/Library/WebKit/", "WebKit 缓存目录"),
            ("\(home)/Library/Mail/", "邮件数据目录"),
            ("\(home)/Library/Messages/", "信息数据目录"),
            ("\(home)/Library/Safari/", "Safari 数据目录"),
            ("\(home)/Library/Keychains/", "钥匙串目录"),
            ("\(home)/Library/Fonts/", "用户字体目录"),
            ("\(home)/Library/ColorSync/", "色彩配置目录"),
            ("\(home)/Library/Printers/", "打印机驱动目录"),
            ("\(home)/Library/Audio/", "音频插件目录"),
            ("\(home)/Library/Automator/", "自动操作脚本目录"),
            ("\(home)/Library/Services/", "服务脚本目录"),
            ("\(home)/Library/Screen Savers/", "屏保目录"),
            ("\(home)/Library/PreferencePanes/", "偏好设置面板目录"),
            ("\(home)/Library/Spelling/", "拼写检查目录"),
            ("\(home)/Library/VoiceTrigger/", "语音触发目录"),
            ("/Applications/", "应用程序目录"),
            ("/System/", "系统核心目录"),
            ("/usr/lib/", "系统共享库目录"),
            ("/usr/bin/", "系统命令目录"),
            ("/usr/sbin/", "系统管理命令目录"),
            ("/usr/local/", "用户安装软件目录"),
            ("/Library/", "系统库目录"),
            ("/private/var/", "系统变量目录"),
            ("/private/tmp/", "系统临时目录"),
            ("/tmp/", "临时目录"),
            ("/opt/", "可选软件目录"),
        ]
        for (path, desc) in directories {
            rules.append(IdentificationRule(
                id: "dir-\(path.replacingOccurrences(of: "/", with: "_"))", matchType: .pathPrefix,
                pattern: path, description: desc, category: "目录"
            ))
        }

        // ====== 4. 扩展名识别（100+ 种） ======
        let extensions: [(String, String, String)] = [
            // 安装/磁盘映像
            ("dmg", "磁盘映像文件（安装包）", "安装包"),
            ("pkg", "macOS 安装包", "安装包"),
            ("mpkg", "macOS 多组件安装包", "安装包"),
            ("app", "macOS 应用程序", "应用"),
            ("ipa", "iOS 应用安装包", "安装包"),
            ("apk", "Android 应用安装包", "安装包"),
            ("deb", "Debian/Linux 安装包", "安装包"),
            ("rpm", "Red Hat/Linux 安装包", "安装包"),
            ("msi", "Windows 安装包", "安装包"),
            ("exe", "Windows 可执行文件", "可执行"),
            ("run", "Linux 可执行安装包", "安装包"),

            // 动态库/框架
            ("dylib", "macOS 动态链接库", "系统库"),
            ("so", "Linux 共享库", "系统库"),
            ("dll", "Windows 动态链接库", "系统库"),
            ("framework", "macOS 框架包", "系统库"),
            ("kext", "内核扩展驱动", "系统库"),
            ("driver", "系统驱动文件", "系统库"),

            // 文档
            ("pdf", "PDF 文档", "文档"),
            ("doc", "Word 文档", "文档"),
            ("docx", "Word 文档", "文档"),
            ("xls", "Excel 表格", "文档"),
            ("xlsx", "Excel 表格", "文档"),
            ("ppt", "PowerPoint 演示文稿", "文档"),
            ("pptx", "PowerPoint 演示文稿", "文档"),
            ("rtf", "富文本文档", "文档"),
            ("txt", "纯文本文档", "文档"),
            ("md", "Markdown 文档", "文档"),
            ("pages", "Pages 文稿", "文档"),
            ("numbers", "Numbers 表格", "文档"),
            ("odt", "OpenDocument 文档", "文档"),
            ("ods", "OpenDocument 表格", "文档"),
            ("odp", "OpenDocument 演示", "文档"),
            ("csv", "CSV 数据表格", "文档"),
            ("tsv", "TSV 数据表格", "文档"),

            // 图片
            ("jpg", "JPEG 图片", "图片"),
            ("jpeg", "JPEG 图片", "图片"),
            ("png", "PNG 图片", "图片"),
            ("gif", "GIF 动图", "图片"),
            ("bmp", "BMP 位图", "图片"),
            ("tiff", "TIFF 图片", "图片"),
            ("tif", "TIFF 图片", "图片"),
            ("webp", "WebP 图片", "图片"),
            ("svg", "SVG 矢量图", "图片"),
            ("ico", "图标文件", "图片"),
            ("icns", "macOS 图标文件", "图片"),
            ("heic", "HEIC 高效图片", "图片"),
            ("heif", "HEIF 高效图片", "图片"),
            ("psd", "Photoshop 设计文件", "图片"),
            ("ai", "Illustrator 矢量文件", "图片"),
            ("sketch", "Sketch 设计文件", "图片"),
            ("fig", "Figma 设计文件", "图片"),
            ("xd", "Adobe XD 设计文件", "图片"),
            ("pxd", "Pixelmator 设计文件", "图片"),
            ("raw", "RAW 原始图片", "图片"),
            ("cr2", "Canon RAW 图片", "图片"),
            ("nef", "Nikon RAW 图片", "图片"),
            ("arw", "Sony RAW 图片", "图片"),
            ("dng", "Adobe DNG 图片", "图片"),

            // 视频
            ("mp4", "MP4 视频", "视频"),
            ("mov", "QuickTime 视频", "视频"),
            ("avi", "AVI 视频", "视频"),
            ("mkv", "MKV 视频", "视频"),
            ("wmv", "WMV 视频", "视频"),
            ("flv", "FLV 视频", "视频"),
            ("webm", "WebM 视频", "视频"),
            ("m4v", "M4V 视频", "视频"),
            ("3gp", "3GP 视频", "视频"),
            ("mpg", "MPEG 视频", "视频"),
            ("mpeg", "MPEG 视频", "视频"),
            ("mts", "AVCHD 视频", "视频"),
            ("mxf", "MXF 专业视频", "视频"),
            ("prores", "Apple ProRes 视频", "视频"),

            // 音频
            ("mp3", "MP3 音频", "音频"),
            ("wav", "WAV 无损音频", "音频"),
            ("aac", "AAC 音频", "音频"),
            ("flac", "FLAC 无损音频", "音频"),
            ("ogg", "OGG 音频", "音频"),
            ("wma", "WMA 音频", "音频"),
            ("m4a", "M4A 音频", "音频"),
            ("opus", "Opus 音频", "音频"),
            ("aiff", "AIFF 无损音频", "音频"),
            ("alac", "Apple 无损音频", "音频"),
            ("mid", "MIDI 音乐文件", "音频"),
            ("midi", "MIDI 音乐文件", "音频"),

            // 压缩/归档
            ("zip", "ZIP 压缩包", "压缩包"),
            ("rar", "RAR 压缩包", "压缩包"),
            ("7z", "7-Zip 压缩包", "压缩包"),
            ("tar", "TAR 归档文件", "压缩包"),
            ("gz", "Gzip 压缩文件", "压缩包"),
            ("bz2", "Bzip2 压缩文件", "压缩包"),
            ("xz", "XZ 压缩文件", "压缩包"),
            ("tgz", "Tar+Gzip 压缩包", "压缩包"),
            ("tbz2", "Tar+Bzip2 压缩包", "压缩包"),
            ("zst", "Zstandard 压缩文件", "压缩包"),
            ("lz4", "LZ4 压缩文件", "压缩包"),
            ("cab", "Windows Cabinet 压缩包", "压缩包"),

            // 代码/开发
            ("swift", "Swift 源代码", "代码"),
            ("py", "Python 脚本", "代码"),
            ("js", "JavaScript 源代码", "代码"),
            ("ts", "TypeScript 源代码", "代码"),
            ("jsx", "React JSX 组件", "代码"),
            ("tsx", "React TSX 组件", "代码"),
            ("java", "Java 源代码", "代码"),
            ("kt", "Kotlin 源代码", "代码"),
            ("c", "C 源代码", "代码"),
            ("cpp", "C++ 源代码", "代码"),
            ("h", "C/C++ 头文件", "代码"),
            ("hpp", "C++ 头文件", "代码"),
            ("m", "Objective-C 源代码", "代码"),
            ("mm", "Objective-C++ 源代码", "代码"),
            ("rb", "Ruby 脚本", "代码"),
            ("go", "Go 源代码", "代码"),
            ("rs", "Rust 源代码", "代码"),
            ("sh", "Shell 脚本", "代码"),
            ("zsh", "Zsh 脚本", "代码"),
            ("bash", "Bash 脚本", "代码"),
            ("fish", "Fish 脚本", "代码"),
            ("php", "PHP 源代码", "代码"),
            ("pl", "Perl 脚本", "代码"),
            ("lua", "Lua 脚本", "代码"),
            ("r", "R 统计脚本", "代码"),
            ("scala", "Scala 源代码", "代码"),
            ("clj", "Clojure 源代码", "代码"),
            ("ex", "Elixir 源代码", "代码"),
            ("erl", "Erlang 源代码", "代码"),
            ("hs", "Haskell 源代码", "代码"),
            ("dart", "Dart 源代码", "代码"),
            ("vue", "Vue.js 组件", "代码"),
            ("svelte", "Svelte 组件", "代码"),

            // 配置/数据
            ("json", "JSON 数据文件", "配置"),
            ("xml", "XML 数据文件", "配置"),
            ("yaml", "YAML 配置文件", "配置"),
            ("yml", "YAML 配置文件", "配置"),
            ("toml", "TOML 配置文件", "配置"),
            ("ini", "INI 配置文件", "配置"),
            ("plist", "macOS 偏好设置文件", "配置"),
            ("env", "环境变量配置文件", "配置"),
            ("conf", "配置文件", "配置"),
            ("cfg", "配置文件", "配置"),
            ("properties", "Java 属性文件", "配置"),
            ("gradle", "Gradle 构建脚本", "配置"),
            ("cmake", "CMake 构建脚本", "配置"),
            ("makefile", "Makefile 构建脚本", "配置"),

            // 网页
            ("html", "HTML 网页", "网页"),
            ("htm", "HTML 网页", "网页"),
            ("css", "CSS 样式表", "网页"),
            ("scss", "SCSS 样式表", "网页"),
            ("sass", "Sass 样式表", "网页"),
            ("less", "Less 样式表", "网页"),
            ("wasm", "WebAssembly 模块", "网页"),

            // 数据库
            ("db", "数据库文件", "数据库"),
            ("sqlite", "SQLite 数据库", "数据库"),
            ("sqlite3", "SQLite3 数据库", "数据库"),
            ("sql", "SQL 脚本", "数据库"),
            ("mdb", "Access 数据库", "数据库"),

            // 字体
            ("ttf", "TrueType 字体", "字体"),
            ("otf", "OpenType 字体", "字体"),
            ("woff", "Web 字体", "字体"),
            ("woff2", "Web 字体", "字体"),
            ("eot", "EOT 字体", "字体"),

            // 3D/CAD
            ("blend", "Blender 3D 工程文件", "3D"),
            ("obj", "3D OBJ 模型", "3D"),
            ("fbx", "3D FBX 模型", "3D"),
            ("stl", "3D STL 模型（3D打印）", "3D"),
            ("gltf", "glTF 3D 模型", "3D"),
            ("glb", "glTF 二进制 3D 模型", "3D"),
            ("3ds", "3ds Max 模型", "3D"),
            ("dwg", "AutoCAD 图纸", "3D"),
            ("dxf", "DXF CAD 图纸", "3D"),

            // 虚拟机/容器
            ("vmdk", "VMware 虚拟磁盘", "虚拟机"),
            ("vdi", "VirtualBox 虚拟磁盘", "虚拟机"),
            ("qcow2", "QEMU 虚拟磁盘", "虚拟机"),
            ("iso", "光盘映像文件", "映像"),
            ("img", "磁盘映像文件", "映像"),
            ("vhd", "虚拟硬盘文件", "虚拟机"),
            ("vhdx", "虚拟硬盘文件", "虚拟机"),

            // 证书/安全
            ("pem", "PEM 证书/密钥", "安全"),
            ("crt", "SSL 证书", "安全"),
            ("cer", "SSL 证书", "安全"),
            ("key", "密钥文件", "安全"),
            ("p12", "PKCS#12 证书包", "安全"),
            ("pfx", "PFX 证书包", "安全"),
            ("jks", "Java 密钥库", "安全"),

            // 日志/临时
            ("log", "日志文件", "日志"),
            ("tmp", "临时文件", "临时"),
            ("temp", "临时文件", "临时"),
            ("cache", "缓存文件", "缓存"),
            ("bak", "备份文件", "备份"),
            ("swp", "Vim 交换文件", "临时"),
            ("lock", "锁文件", "临时"),

            // 种子/下载
            ("torrent", "BitTorrent 种子文件", "下载"),
            ("metalink", "Metalink 下载链接", "下载"),
            ("aria2", "Aria2 下载控制文件", "下载"),

            // 其他
            ("lnk", "Windows 快捷方式", "快捷方式"),
            ("alias", "macOS 别名文件", "快捷方式"),
            ("sym", "符号链接", "快捷方式"),
            ("desktop", "Linux 桌面快捷方式", "快捷方式"),
            ("gitignore", "Git 忽略配置", "配置"),
            ("gitattributes", "Git 属性配置", "配置"),
            ("editorconfig", "编辑器配置", "配置"),
            ("prettierrc", "Prettier 格式化配置", "配置"),
            ("eslintrc", "ESLint 代码检查配置", "配置"),
            ("babelrc", "Babel 转译配置", "配置"),
            ("dockerfile", "Docker 构建文件", "配置"),
            ("docker-compose", "Docker Compose 配置", "配置"),
        ]
        for (ext, desc, category) in extensions {
            rules.append(IdentificationRule(
                id: "ext-\(ext)", matchType: .fileExtension,
                pattern: ext, description: desc, category: category
            ))
        }

        return rules
    }
}

// MARK: - FileItem 扩展

extension FileItem {
    /// 创建一个仅更新了 description 的新实例
    func withDescription(_ desc: String) -> FileItem {
        FileItem(
            id: id,
            name: name,
            path: path,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            accessedAt: accessedAt,
            fileExtension: fileExtension,
            safetyLevel: safetyLevel,
            fileType: fileType,
            description: desc,
            isDirectory: isDirectory
        )
    }
}
