import Foundation
import CoreServices

// MARK: - 线程安全计数器（用于批次回调）

/// 引用类型计数器，解决闭包捕获值类型导致的旧值问题
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int

    init(value: Int = 0) { _value = value }

    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }

    @discardableResult
    func add(_ delta: Int) -> Int {
        lock.lock()
        _value += delta
        let result = _value
        lock.unlock()
        return result
    }
}

// MARK: - 扫描范围配置

/// 目录扫描权限
enum ScanScope {
    case required    // 必扫：~/Downloads, ~/Desktop
    case optional    // 可选：~/Documents
    case readOnly    // 只读展示：~/Library
    case forbidden   // 禁止扫描：/System, /usr, /bin, /sbin, /Applications 内部
}

/// 扫描路径配置
struct ScanPathConfig {
    let url: URL
    let scope: ScanScope

    /// 预设的扫描路径
    static func defaultConfigs() -> [ScanPathConfig] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ScanPathConfig(url: home.appendingPathComponent("Downloads"),  scope: .required),
            ScanPathConfig(url: home.appendingPathComponent("Desktop"),    scope: .required),
            ScanPathConfig(url: home.appendingPathComponent("Documents"),  scope: .optional),
            ScanPathConfig(url: home.appendingPathComponent("Library"),    scope: .readOnly),
        ]
    }

    /// 禁止扫描的路径前缀
    static let forbiddenPrefixes = [
        "/System/", "/usr/", "/bin/", "/sbin/",
        "/Applications/"
    ]

    /// 判断路径是否被禁止
    static func isForbidden(_ path: String) -> Bool {
        forbiddenPrefixes.contains { path.hasPrefix($0) }
    }
}

// MARK: - 扫描进度

/// 扫描进度事件
enum ScanProgress {
    case scanning(path: String, fileCount: Int)           // 正在扫描某目录
    case batch(files: [FileItem], totalScanned: Int)      // 每 100 个文件批量推送
    case completed(result: ScanResult)                     // 扫描完成
    case error(path: String, message: String)              // 扫描出错
    case cancelled                                         // 被取消
}

// MARK: - 文件变更事件

/// FSEvents 文件变更事件
struct FileChangeEvent {
    let path: String
    let flags: FSEventStreamEventFlags
    let timestamp: Date

    /// 是否为创建事件
    var isCreated: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
    }

    /// 是否为删除事件
    var isRemoved: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }

    /// 是否为修改事件
    var isModified: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
        flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
    }

    /// 是否为目录事件
    var isDirectory: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
    }
}

// MARK: - 扫描结果

struct ScanResult {
    let files: [FileItem]
    let totalSize: Int64
    let scanPaths: [String]
    let scanDuration: TimeInterval
    let scannedCount: Int      // 实际扫描的文件总数
    let skippedCount: Int      // 跳过的文件数

    var groupedBySafety: [SafetyLevel: [FileItem]] {
        Dictionary(grouping: files, by: \.safetyLevel)
    }

    var groupedByType: [FileType: [FileItem]] {
        Dictionary(grouping: files, by: \.fileType)
    }

    func sizeBySafety(_ level: SafetyLevel) -> Int64 {
        groupedBySafety[level]?.reduce(0) { $0 + $1.size } ?? 0
    }

    var cleanableSize: Int64 {
        sizeBySafety(.cleanable)
    }
}

// MARK: - FileScanService

final class FileScanService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let scanQueue = DispatchQueue(label: "com.filelens.scan", qos: .userInitiated, attributes: .concurrent)

    // 批量大小（增大以减少回调开销）
    private let batchSize = 500

    // 最大递归深度
    private let maxDepth = 8

    // FSEvents 监控
    private var eventStreams: [String: FSEventStreamRef] = [:]
    private var onChangeHandler: (([FileChangeEvent]) -> Void)?
    private let monitorLock = NSLock()

    // 取消标记（用 NSLock 保护，解决数据竞争）
    private var _isCancelled = false
    private let cancelLock = NSLock()

    private var isCancelled: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return _isCancelled }
        set { cancelLock.lock(); _isCancelled = newValue; cancelLock.unlock() }
    }

    // 安全分级器
    private(set) var classifier: SafetyClassifier

    // 文件识别器
    private(set) var identifier: FileIdentifier

    // 存储服务
    let storage = StorageService.shared

    init(classifier: SafetyClassifier? = nil, identifier: FileIdentifier? = nil) {
        if let classifier = classifier {
            self.classifier = classifier
        } else if let url = Bundle.main.url(forResource: "classification_rules", withExtension: "json"),
                  let loaded = try? SafetyClassifier(configURL: url) {
            self.classifier = loaded
        } else {
            self.classifier = SafetyClassifier()
        }

        if let identifier = identifier {
            self.identifier = identifier
        } else if let url = Bundle.main.url(forResource: "identification_rules", withExtension: "json"),
                  let loaded = try? FileIdentifier(configURL: url) {
            self.identifier = loaded
        } else {
            self.identifier = FileIdentifier()
        }
    }

    // MARK: - 扫描

    /// 开始扫描，返回 AsyncStream 推送进度
    func startScan(paths: [URL]) -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            // 重置状态
            self.isCancelled = false

            // FileScanService 标记为 @unchecked Sendable，所有可变状态通过 NSLock 保护
            let task = Task.detached(priority: .userInitiated) {
                let startTime = Date()

                // 过滤合法路径
                let validPaths = paths.filter { url in
                    let path = url.path
                    if ScanPathConfig.isForbidden(path) {
                        continuation.yield(.error(path: path, message: "该路径禁止扫描"))
                        return false
                    }
                    guard self.fileManager.fileExists(atPath: path) else {
                        continuation.yield(.error(path: path, message: "目录不存在"))
                        return false
                    }
                    return true
                }

                // 用引用类型跟踪扫描计数，避免闭包捕获旧值
                let scannedCounter = Counter(value: 0)
                let skippedCounter = Counter(value: 0)

                // 并行扫描多个目录（TaskGroup）
                var allFiles: [FileItem] = []
                await withTaskGroup(of: (files: [FileItem], skipped: Int).self) { group in
                    for url in validPaths {
                        group.addTask { [self] in
                            guard !self.isCancelled else { return ([], 0) }
                            continuation.yield(.scanning(path: url.path, fileCount: scannedCounter.value))
                            return await self.scanDirectory(url: url, depth: 0) { newFiles in
                                let count = scannedCounter.add(newFiles.count)
                                continuation.yield(.batch(files: newFiles, totalScanned: count))
                            }
                        }
                    }
                    for await result in group {
                        skippedCounter.add(result.skipped)
                        allFiles.append(contentsOf: result.files)
                    }
                }

                let totalScanned = scannedCounter.value
                let totalSkipped = skippedCounter.value
                let duration = Date().timeIntervalSince(startTime)

                // 使用 SafetyClassifier 重新分类，使用 FileIdentifier 生成中文说明
                let classifiedFiles = self.classifier.classify(files: allFiles)
                let identifiedFiles = self.identifier.identify(files: classifiedFiles)
                let totalSize = identifiedFiles.reduce(0) { $0 + $1.size }

                let result = ScanResult(
                    files: identifiedFiles,
                    totalSize: totalSize,
                    scanPaths: validPaths.map(\.path),
                    scanDuration: duration,
                    scannedCount: totalScanned,
                    skippedCount: totalSkipped
                )

                // 保存到存储（后台队列，不阻塞扫描完成事件）
                let storedFiles = identifiedFiles.map { StoredFile(from: $0) }
                self.storage.saveFiles(storedFiles)
                self.storage.addScanRecord(ScanRecord(
                    scanTime: Date(),
                    filesCount: identifiedFiles.count,
                    duration: duration
                ))
                self.storage.updateLastScanTime()

                continuation.yield(.completed(result: result))
                continuation.finish()
            }

            // 处理取消
            continuation.onTermination = { @Sendable _ in
                self.isCancelled = true
                task.cancel()
            }
        }
    }

    /// 取消当前扫描
    func cancelScan() {
        isCancelled = true
    }

    // MARK: - 递归扫描

    /// 递归扫描目录，返回 (文件列表, 跳过数量)
    private func scanDirectory(
        url: URL,
        depth: Int,
        onBatch: @escaping ([FileItem]) -> Void
    ) async -> ([FileItem], Int) {
        guard depth <= maxDepth, !isCancelled else { return ([], 0) }

        let path = url.path

        // 禁止扫描检查
        if ScanPathConfig.isForbidden(path) {
            return ([], 0)
        }

        // 跳过无权限目录
        guard fileManager.isReadableFile(atPath: path) else {
            return ([], 0)
        }

        // 精简资源属性：只请求必要字段（减少 per-file syscall）
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isSymbolicLinkKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                print("[FileScanService] 目录遍历错误 \(url.path): \(error)")
                return true  // 继续遍历
            }
        ) else {
            return ([], 0)
        }

        // 预编译禁止路径前缀（避免每次遍历重新创建数组）
        let forbiddenPrefixes = ScanPathConfig.forbiddenPrefixes
        let now = Date()

        var results: [FileItem] = []
        var skipped = 0
        var batchBuffer: [FileItem] = []
        var checkCancelCounter = 0
        var lastUpdateTime = Date()

        while let fileURL = enumerator.nextObject() as? URL {
            // 每 256 个文件检查一次取消状态（减少锁争用）
            checkCancelCounter += 1
            if checkCancelCounter & 0xFF == 0, isCancelled { break }

            let filePath = fileURL.path

            // 跳过系统禁止路径（内联检查，避免函数调用开销）
            var isForbidden = false
            for prefix in forbiddenPrefixes {
                if filePath.hasPrefix(prefix) { isForbidden = true; break }
            }
            if isForbidden { skipped += 1; continue }

            // 获取资源属性
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                skipped += 1
                continue
            }

            // 跳过符号链接
            if resourceValues.isSymbolicLink == true {
                skipped += 1
                continue
            }

            let isDir = resourceValues.isDirectory ?? false
            let name = fileURL.lastPathComponent

            // 跳过常见无用目录
            if isDir && shouldSkipDirectory(name: name) {
                enumerator.skipDescendants()
                skipped += 1
                continue
            }

            // 跳过隐藏目录（保留少数有用的）
            if isDir && name.hasPrefix(".") {
                let allowedHidden: Set<String> = [".config", ".local", ".ssh"]
                if !allowedHidden.contains(name) {
                    enumerator.skipDescendants()
                    skipped += 1
                    continue
                }
            }

            // 获取文件大小
            let size: Int64
            if isDir {
                size = 0  // 目录不递归计算大小
                if name.hasSuffix(".app") {
                    enumerator.skipDescendants()
                }
            } else {
                size = Int64(resourceValues.fileSize ?? 0)
            }

            // 修改日期作为主要时间属性（减少请求的 key 数量）
            let modified = resourceValues.contentModificationDate ?? now

            let item = FileItem(
                name: name,
                path: filePath,
                size: size,
                createdAt: modified,
                modifiedAt: modified,
                accessedAt: modified,
                isDirectory: isDir
            )

            results.append(item)
            batchBuffer.append(item)

            // 批量推送：每 500 个文件或每 0.5 秒更新一次
            if batchBuffer.count >= batchSize || Date().timeIntervalSince(lastUpdateTime) >= 0.5 {
                onBatch(batchBuffer)
                batchBuffer.removeAll()
                lastUpdateTime = Date()
            }
        }

        // 推送剩余
        if !batchBuffer.isEmpty {
            onBatch(batchBuffer)
        }

        return (results, skipped)
    }

    /// 需要跳过的目录名集合（静态常量，避免每次调用重新创建）
    private static let skipDirectoryNames: Set<String> = [
        // 版本控制
        ".git", ".svn", ".hg",
        // 包管理器
        "node_modules", ".npm", ".yarn", "Pods", ".cocoapods", "Carthage",
        ".gradle", ".cargo", "vendor",
        // 构建产物
        "__pycache__", "DerivedData", "Build", ".build", "dist", "out", "target",
        // 虚拟环境
        "venv", ".venv", "env",
        // IDE
        ".idea", ".vscode",
        // macOS 系统缓存
        "Caches", "Logs", "Saved Application State", "WebKit",
        ".Trash", ".Spotlight-V100", ".fseventsd",
    ]

    /// 是否跳过该目录
    private func shouldSkipDirectory(name: String) -> Bool {
        Self.skipDirectoryNames.contains(name)
    }


    // MARK: - FSEvents 文件监控

    /// 开始监控目录变化
    func startMonitoring(paths: [URL], onChange: @escaping ([FileChangeEvent]) -> Void) {
        stopMonitoring()
        monitorLock.lock()
        onChangeHandler = onChange
        monitorLock.unlock()

        let pathsToWatch = paths.map(\.path) as CFArray
        let latency: CFTimeInterval = 1.0 // 1秒延迟合并事件

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            FileScanService.eventStreamCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        eventStreams["main"] = stream
        FSEventStreamSetDispatchQueue(stream, scanQueue)
        FSEventStreamStart(stream)
    }

    /// 停止所有监控
    func stopMonitoring() {
        monitorLock.lock()
        // 先置空 handler，防止回调继续执行
        onChangeHandler = nil
        monitorLock.unlock()

        for (_, stream) in eventStreams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        eventStreams.removeAll()
    }

    /// FSEvents 回调（通过 monitorLock 保护，防止在 stopMonitoring 期间/之后访问已释放资源）
    private static let eventStreamCallback: FSEventStreamCallback = {
        (stream, contextInfo, numEvents, eventPaths, eventFlags, eventIds) in

        guard let contextInfo = contextInfo else { return }
        let service = Unmanaged<FileScanService>.fromOpaque(contextInfo).takeUnretainedValue()

        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        var events: [FileChangeEvent] = []
        for i in 0..<numEvents {
            let event = FileChangeEvent(
                path: paths[i],
                flags: FSEventStreamEventFlags(eventFlags[i]),
                timestamp: Date()
            )
            events.append(event)
        }

        if !events.isEmpty {
            service.monitorLock.lock()
            let handler = service.onChangeHandler
            service.monitorLock.unlock()
            handler?(events)
        }
    }

    // MARK: - 配置管理

    /// 从 JSON 文件重新加载分类规则
    func reloadClassificationRules(from url: URL) throws {
        classifier = try SafetyClassifier(configURL: url)
    }

    /// 从 JSON 文件重新加载识别规则
    func reloadIdentificationRules(from url: URL) throws {
        identifier = try FileIdentifier(configURL: url)
    }

    // MARK: - 扫描范围辅助

    /// 获取路径的扫描范围
    static func scopeForPath(_ path: String) -> ScanScope {
        if ScanPathConfig.isForbidden(path) {
            return .forbidden
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homePrefix = home + "/"

        guard path.hasPrefix(homePrefix) else { return .forbidden }

        let relative = String(path.dropFirst(homePrefix.count))
        let topDir = relative.split(separator: "/").first.map(String.init) ?? relative

        switch topDir {
        case "Downloads", "Desktop":
            return .required
        case "Documents":
            return .optional
        case "Library":
            return .readOnly
        default:
            return .optional
        }
    }

    deinit {
        stopMonitoring()
    }
}
