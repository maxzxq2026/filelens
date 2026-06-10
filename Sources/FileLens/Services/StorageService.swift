import Foundation

// MARK: - 数据模型

/// 持久化文件模型
struct StoredFile: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let accessedAt: Date?
    let fileExtension: String
    let safetyLevel: String    // "critical" "caution" "cleanable" "safe"
    let fileType: String
    let description: String
    let scannedAt: Date
    var isDeleted: Bool
}

/// 扫描记录
struct ScanRecord: Codable {
    let scanTime: Date
    let filesCount: Int
    let duration: Double
}

/// 应用配置
struct AppConfig: Codable {
    var scanPaths: [String]
    var autoScan: Bool
    var lastScanTime: Date?

    static let `default` = AppConfig(
        scanPaths: ["~/Downloads", "~/Desktop"],
        autoScan: false,
        lastScanTime: nil
    )
}

// MARK: - StorageService

/// JSON 文件存储服务（单例，零依赖）
/// 数据存储在 ~/Library/Application Support/FileLens/
final class StorageService: @unchecked Sendable {

    static let shared = StorageService()

    private let fileManager = FileManager.default
    private let baseDir: URL
    private var filesCache: [StoredFile] = []
    private var configCache: AppConfig?
    private let cacheLock = NSLock()
    private let queue = DispatchQueue(label: "com.filelens.storage", qos: .utility)

    private init() {
        baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("FileLens")
        createDirectoryIfNeeded()
        loadCache()
    }

    // MARK: - 文件操作

    /// 获取所有文件（内存缓存）
    func loadFiles() -> [StoredFile] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return filesCache
    }

    /// 保存全部文件（覆盖写入）
    func saveFiles(_ files: [StoredFile]) {
        cacheLock.lock()
        filesCache = files
        cacheLock.unlock()
        writeToJSON(files, filename: "files.json")
    }

    /// 添加单个文件（延迟写入）
    func addFile(_ file: StoredFile) {
        cacheLock.lock()
        filesCache.append(file)
        cacheLock.unlock()
        scheduleWrite()
    }

    /// 批量添加文件（立即写入）
    func addFiles(_ files: [StoredFile]) {
        cacheLock.lock()
        filesCache.append(contentsOf: files)
        let snapshot = filesCache
        cacheLock.unlock()
        writeToJSON(snapshot, filename: "files.json")
    }

    /// 更新文件
    func updateFile(_ file: StoredFile) {
        cacheLock.lock()
        if let index = filesCache.firstIndex(where: { $0.id == file.id }) {
            filesCache[index] = file
            cacheLock.unlock()
            scheduleWrite()
        } else {
            cacheLock.unlock()
        }
    }

    /// 删除文件（物理删除）
    func deleteFile(id: String) {
        cacheLock.lock()
        filesCache.removeAll { $0.id == id }
        cacheLock.unlock()
        scheduleWrite()
    }

    /// 标记文件为已删除（软删除）
    func markAsDeleted(id: String) {
        cacheLock.lock()
        if let index = filesCache.firstIndex(where: { $0.id == id }) {
            filesCache[index].isDeleted = true
            cacheLock.unlock()
            scheduleWrite()
        } else {
            cacheLock.unlock()
        }
    }

    /// 标记不在当前扫描结果中的文件为已删除
    func markDeletedFiles(notIn currentPaths: Set<String>) {
        cacheLock.lock()
        var changed = false
        for i in filesCache.indices {
            if !filesCache[i].isDeleted && !currentPaths.contains(filesCache[i].path) {
                filesCache[i].isDeleted = true
                changed = true
            }
        }
        cacheLock.unlock()
        if changed {
            scheduleWrite()
        }
    }

    // MARK: - 查询

    /// 搜索文件（按名称、路径、描述）
    func search(keyword: String) -> [StoredFile] {
        let lower = keyword.lowercased()
        cacheLock.lock()
        let result = filesCache.filter {
            !$0.isDeleted &&
            ($0.name.lowercased().contains(lower) ||
             $0.description.lowercased().contains(lower) ||
             $0.path.lowercased().contains(lower))
        }
        cacheLock.unlock()
        return result
    }

    /// 按安全等级过滤
    func filter(bySafetyLevel level: String) -> [StoredFile] {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted && $0.safetyLevel == level }
        cacheLock.unlock()
        return result
    }

    /// 按文件类型过滤
    func filter(byFileType type: String) -> [StoredFile] {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted && $0.fileType == type }
        cacheLock.unlock()
        return result
    }

    /// 获取超过 N 天未访问的文件
    func getOldFiles(days: Int) -> [StoredFile] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        cacheLock.lock()
        let result = filesCache.filter {
            !$0.isDeleted &&
            ($0.accessedAt ?? $0.createdAt ?? .distantPast) < cutoff
        }
        cacheLock.unlock()
        return result
    }

    // MARK: - 统计

    /// 按安全等级统计数量
    func countBySafetyLevel() -> [String: Int] {
        cacheLock.lock()
        var counts = ["critical": 0, "caution": 0, "cleanable": 0, "safe": 0]
        for file in filesCache where !file.isDeleted {
            counts[file.safetyLevel, default: 0] += 1
        }
        cacheLock.unlock()
        return counts
    }

    /// 文件总大小
    func totalSize() -> Int64 {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }
        cacheLock.unlock()
        return result
    }

    /// 可清理文件总大小
    func cleanableSize() -> Int64 {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted && $0.safetyLevel == "cleanable" }
            .reduce(0) { $0 + $1.size }
        cacheLock.unlock()
        return result
    }

    /// 可整理文件总大小
    func safeSize() -> Int64 {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted && $0.safetyLevel == "safe" }
            .reduce(0) { $0 + $1.size }
        cacheLock.unlock()
        return result
    }

    /// 活跃文件数量（未删除）
    func activeCount() -> Int {
        cacheLock.lock()
        let result = filesCache.filter { !$0.isDeleted }.count
        cacheLock.unlock()
        return result
    }

    // MARK: - 扫描历史

    /// 添加扫描记录
    func addScanRecord(_ record: ScanRecord) {
        var history = getScanHistory()
        history.append(record)
        // 只保留最近 50 条
        if history.count > 50 {
            history = Array(history.suffix(50))
        }
        writeToJSON(history, filename: "history.json")
    }

    /// 获取扫描历史
    func getScanHistory() -> [ScanRecord] {
        readFromJSON(filename: "history.json") ?? []
    }

    /// 获取最后一次扫描
    func getLastScan() -> ScanRecord? {
        getScanHistory().last
    }

    // MARK: - 配置

    /// 加载配置
    func loadConfig() -> AppConfig {
        if let config = configCache {
            return config
        }
        let config: AppConfig = readFromJSON(filename: "config.json") ?? .default
        configCache = config
        return config
    }

    /// 保存配置
    func saveConfig(_ config: AppConfig) {
        configCache = config
        writeToJSON(config, filename: "config.json")
    }

    /// 更新最后扫描时间
    func updateLastScanTime() {
        var config = loadConfig()
        config.lastScanTime = Date()
        saveConfig(config)
    }

    // MARK: - 数据维护

    /// 清除所有已删除文件的记录
    func purgeDeleted() -> Int {
        cacheLock.lock()
        let before = filesCache.count
        filesCache.removeAll { $0.isDeleted }
        let purged = before - filesCache.count
        let snapshot = filesCache
        cacheLock.unlock()
        if purged > 0 {
            writeToJSON(snapshot, filename: "files.json")
        }
        return purged
    }

    /// 清空所有数据
    func clearAll() {
        cacheLock.lock()
        filesCache.removeAll()
        let empty = filesCache
        cacheLock.unlock()
        configCache = nil
        writeToJSON(empty, filename: "files.json")
        writeToJSON([ScanRecord](), filename: "history.json")
        writeToJSON(AppConfig.default, filename: "config.json")
    }

    /// 存储目录大小
    func storageSize() -> Int64 {
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: baseDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let url = enumerator.nextObject() as? URL {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    // MARK: - 私有方法

    private func createDirectoryIfNeeded() {
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private func loadCache() {
        filesCache = readFromJSON(filename: "files.json") ?? []
    }

    /// JSON 编码器（静态常量，避免重复创建）
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// JSON 解码器（静态常量，避免重复创建）
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 写入 JSON 文件
    private func writeToJSON<T: Encodable>(_ data: T, filename: String) {
        let url = baseDir.appendingPathComponent(filename)
        do {
            let jsonData = try Self.encoder.encode(data)
            try jsonData.write(to: url, options: .atomic)
        } catch {
            print("[StorageService] 写入 \(filename) 失败: \(error)")
        }
    }

    /// 读取 JSON 文件
    private func readFromJSON<T: Decodable>(filename: String) -> T? {
        let url = baseDir.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            print("[StorageService] 读取 \(filename) 失败: \(error)")
            return nil
        }
    }

    // MARK: - 延迟写入（防抖）

    private var writeWorkItem: DispatchWorkItem?

    /// 延迟 0.5 秒写入，避免频繁磁盘 IO
    private func scheduleWrite() {
        writeWorkItem?.cancel()
        // 使用强引用捕获，因为 StorageService 是单例，生命周期等同于 App
        let work = DispatchWorkItem {
            self.cacheLock.lock()
            let snapshot = self.filesCache
            self.cacheLock.unlock()
            self.writeToJSON(snapshot, filename: "files.json")
        }
        writeWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

// MARK: - FileItem ↔ StoredFile 转换

extension StoredFile {
    /// 从 FileItem 创建
    init(from file: FileItem, scannedAt: Date = Date()) {
        self.id = file.id.uuidString
        self.name = file.name
        self.path = file.path
        self.size = file.size
        self.createdAt = file.createdAt
        self.modifiedAt = file.modifiedAt
        self.accessedAt = file.accessedAt
        self.fileExtension = file.fileExtension
        self.safetyLevel = file.safetyLevel.rawValue
        self.fileType = file.fileType.rawValue
        self.description = file.description
        self.scannedAt = scannedAt
        self.isDeleted = false
    }

    /// 转换为 FileItem
    func toFileItem() -> FileItem? {
        guard let safety = SafetyLevel(rawValue: safetyLevel),
              let fileType = FileType(rawValue: fileType) else { return nil }
        return FileItem(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            path: path,
            size: size,
            createdAt: createdAt ?? Date(),
            modifiedAt: modifiedAt ?? Date(),
            accessedAt: accessedAt ?? Date(),
            fileExtension: fileExtension,
            safetyLevel: safety,
            fileType: fileType,
            description: description,
            isDirectory: false
        )
    }
}
