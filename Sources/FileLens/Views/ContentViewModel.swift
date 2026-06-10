import SwiftUI
import AppKit

/// 主视图 ViewModel
@MainActor
class ContentViewModel: ObservableObject {
    @Published var scanPath: String = NSHomeDirectory()
    @Published var scanResult: ScanResult?
    @Published var isScanning = false
    @Published var scannedCount: Int = 0
    @Published var currentScanPath: String = ""
    @Published var scanProgress: Double = 0
    @Published var isMonitoring = false

    private let scanService = FileScanService()
    private var scanTask: Task<Void, Never>?

    /// 开始扫描（默认扫描必扫路径）
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scannedCount = 0
        scanResult = nil

        // 使用默认扫描路径配置
        let configs = ScanPathConfig.defaultConfigs()
        let urls = configs.filter { $0.scope != .forbidden }.map(\.url)

        scanTask = Task {
            for await progress in scanService.startScan(paths: urls) {
                switch progress {
                case .scanning(let path, let fileCount):
                    currentScanPath = (path as NSString).lastPathComponent
                    scannedCount = fileCount

                case .batch(_, let totalScanned):
                    scannedCount = totalScanned

                case .completed(let result):
                    scanResult = result
                    isScanning = false
                    currentScanPath = ""

                case .error(let path, let message):
                    print("[FileLens] 扫描错误 \(path): \(message)")

                case .cancelled:
                    isScanning = false
                    currentScanPath = ""
                }
            }
        }
    }

    /// 扫描指定路径
    func startScan(paths: [URL]) {
        guard !isScanning else { return }
        isScanning = true
        scannedCount = 0
        scanResult = nil

        scanTask = Task {
            for await progress in scanService.startScan(paths: paths) {
                switch progress {
                case .scanning(let path, let fileCount):
                    currentScanPath = (path as NSString).lastPathComponent
                    scannedCount = fileCount

                case .batch(_, let totalScanned):
                    scannedCount = totalScanned

                case .completed(let result):
                    scanResult = result
                    isScanning = false
                    currentScanPath = ""

                case .error(_, let message):
                    print("[FileLens] \(message)")

                case .cancelled:
                    isScanning = false
                    currentScanPath = ""
                }
            }
        }
    }

    /// 取消扫描
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanService.cancelScan()
    }

    /// 开始文件监控
    func startMonitoring() {
        isMonitoring = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let watchPaths = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop")
        ]

        scanService.startMonitoring(paths: watchPaths) { [weak self] events in
            // 合并事件后刷新扫描
            let hasChanges = events.contains { $0.isCreated || $0.isRemoved || $0.isModified }
            if hasChanges {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // 延迟 2 秒避免频繁刷新
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch is CancellationError {
                        return  // Task 被取消，不执行扫描
                    } catch {
                        return  // 其他错误也跳过
                    }
                    self.startScan()
                }
            }
        }
    }

    /// 停止文件监控
    func stopMonitoring() {
        isMonitoring = false
        scanService.stopMonitoring()
    }

    /// 浏览选择文件夹
    func browseFolder() {
        NotificationCenter.default.post(name: .init("FileLens.dismissPopover"), object: nil)
        let panel = NSOpenPanel()
        panel.title = "选择扫描目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: scanPath)

        if panel.runModal() == .OK, let url = panel.url {
            scanPath = url.path
            startScan(paths: [url])
        }
    }

    // MARK: - 整理

    @Published var organizePreview: OrganizePreview? = nil
    @Published var isOrganizing = false
    @Published var organizeResult: String? = nil

    let organizer = FileOrganizer.shared

    /// 生成整理方案并显示预览
    func generateOrganizePlan() {
        guard let result = scanResult else { return }
        let storedFiles = result.files.map { StoredFile(from: $0) }
        let plan = organizer.generatePlan(for: storedFiles)
        let preview = organizer.previewPlan(plan)

        if preview.moveCount > 0 {
            organizePreview = preview
        } else {
            organizeResult = "没有需要整理的文件（仅整理「可整理」的文件）"
        }
    }

    /// 执行整理
    func executeOrganize() async {
        guard let preview = organizePreview else { return }
        isOrganizing = true

        do {
            try await organizer.executePlan(preview.actions)
            organizeResult = "✅ 成功整理 \(preview.moveCount) 个文件"
            organizePreview = nil
            // 重新扫描
            startScan()
        } catch {
            organizeResult = "❌ 整理失败: \(error.localizedDescription)"
        }

        isOrganizing = false
    }

    /// 撤销整理
    func undoOrganize() async {
        do {
            try await Task.detached {
                try self.organizer.undoLastPlan()
            }.value
            organizeResult = "↩️ 已撤销整理"
            startScan()
        } catch {
            organizeResult = "❌ 撤销失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 分类器 & 识别器

    var classifier: SafetyClassifier { scanService.classifier }
    var identifier: FileIdentifier { scanService.identifier }

    /// 重新分类 + 重新识别当前结果
    func reclassify() {
        guard let result = scanResult else { return }
        let classified = scanService.classifier.classify(result: result)
        scanResult = scanService.identifier.identify(result: classified)
    }

    /// 加载自定义分类规则
    func loadClassificationRules() {
        guard let url = showJSONPicker(title: "选择分类规则文件") else { return }
        do {
            try scanService.reloadClassificationRules(from: url)
            reclassify()
        } catch {
            print("[FileLens] 加载分类规则失败: \(error)")
        }
    }

    /// 加载自定义识别规则
    func loadIdentificationRules() {
        guard let url = showJSONPicker(title: "选择识别规则文件") else { return }
        do {
            try scanService.reloadIdentificationRules(from: url)
            reclassify()
        } catch {
            print("[FileLens] 加载识别规则失败: \(error)")
        }
    }

    /// 通用 JSON 文件选择器
    private func showJSONPicker(title: String) -> URL? {
        NotificationCenter.default.post(name: .init("FileLens.dismissPopover"), object: nil)
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
