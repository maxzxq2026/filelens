import SwiftUI

/// FileLens 主视图
struct MainView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: FilterType = .all
    @State private var selectedLevel: SafetyLevel? = nil
    @State private var selectedFile: FileItem? = nil
    @State private var showDetail = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            if showDetail, let file = selectedFile {
                fileDetailOverlay(file: file)
            } else {
                mainListView
            }
        }
        .frame(width: FL.windowWidth)
        .background(FL.background)
        .alert("操作失败", isPresented: $showError) {
            Button("好的") { showError = false }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - 主列表视图

    private var mainListView: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, FL.paddingL)
                .padding(.top, FL.paddingM)
                .padding(.bottom, FL.paddingS)

            SearchBar(text: $searchText)
                .padding(.horizontal, FL.paddingL)
                .padding(.bottom, FL.paddingS)

            if hasResults {
                StatsCardGroup(
                    counts: safetyCounts,
                    selectedLevel: selectedLevel,
                    onSelect: { selectedLevel = $0 }
                )
                .padding(.horizontal, FL.paddingL)
                .padding(.bottom, FL.paddingS)

                FilterBar(selected: $selectedFilter)
                    .padding(.horizontal, FL.paddingL)
                    .padding(.bottom, FL.paddingS)
            }

            Divider()

            if viewModel.isScanning {
                scanningView
            } else if hasResults {
                fileList
            } else {
                emptyState
            }

            Divider()

            bottomBar
                .padding(.horizontal, FL.paddingL)
                .padding(.vertical, FL.paddingS)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.organizePreview != nil },
            set: { if !$0 { viewModel.organizePreview = nil } }
        )) {
            if let preview = viewModel.organizePreview {
                OrganizePreviewView(
                    preview: preview,
                    onConfirm: {
                        Task { await viewModel.executeOrganize() }
                    },
                    onCancel: { viewModel.organizePreview = nil }
                )
            }
        }
        .alert("整理结果", isPresented: Binding(
            get: { viewModel.organizeResult != nil },
            set: { if !$0 { viewModel.organizeResult = nil } }
        )) {
            Button("好的") { viewModel.organizeResult = nil }
            if viewModel.organizer.canUndo {
                Button("撤销", role: .cancel) { Task { await viewModel.undoOrganize() } }
            }
        } message: {
            Text(viewModel.organizeResult ?? "")
        }
    }

    // MARK: - 文件详情覆盖层

    private func fileDetailOverlay(file: FileItem) -> some View {
        FileDetailView(item: file)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetail = false
                    selectedFile = nil
                }
            }
            .transition(.move(edge: .trailing))
    }

    // MARK: - 顶部标题栏

    private var headerBar: some View {
        HStack {
            // Logo + 标题
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(FL.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("FileLens")
                        .font(FL.titleFont)
                        .foregroundColor(FL.text)
                    Text("文件透视镜")
                        .font(FL.microFont)
                        .foregroundColor(FL.textSecondary)
                }
            }

            Spacer()

            // 操作按钮组
            HStack(spacing: 8) {
                // 更多菜单（设置 / 监控 / 整理）
                Menu {
                    Section("规则") {
                        Button("导入分类规则…") { viewModel.loadClassificationRules() }
                        Button("导入识别规则…") { viewModel.loadIdentificationRules() }
                    }
                    Section {
                        Button {
                            toggleMonitoring()
                        } label: {
                            Label(
                                viewModel.isMonitoring ? "停止监控" : "开启实时监控",
                                systemImage: viewModel.isMonitoring ? "bolt.slash" : "bolt"
                            )
                        }
                        Button {
                            viewModel.generateOrganizePlan()
                        } label: {
                            Label("一键整理", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(viewModel.isScanning || viewModel.scanResult == nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(FL.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("更多操作")

                // 扫描按钮（主操作）
                Button(action: { viewModel.startScan() }) {
                    HStack(spacing: 4) {
                        if viewModel.isScanning {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(viewModel.isScanning ? "扫描中" : "扫描")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(FL.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)
            }
        }
    }

    // MARK: - 文件列表

    /// 过滤后的文件列表（仅在依赖变化时重新计算）
    private var filteredFiles: [FileItem] {
        applyFilters()
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredFiles) { item in
                    FileListItem(
                        item: item,
                        onDelete: { moveToTrash(item) },
                        onReveal: { revealInFinder(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFile = item
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDetail = true
                        }
                    }
                    .contextMenu {
                        contextMenu(for: item)
                    }
                }
            }
            .padding(.horizontal, FL.paddingS)
            .padding(.vertical, FL.paddingXS)
        }
    }

    // MARK: - 扫描中

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()

            // 骨架屏
            VStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 4, height: 36)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: CGFloat.random(in: 80...160), height: 12)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: CGFloat.random(in: 60...100), height: 10)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            VStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)

                Text("正在扫描文件…")
                    .font(.system(size: 13, weight: .medium))

                if viewModel.scannedCount > 0 {
                    Text("已发现 \(viewModel.scannedCount) 个文件")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Button("取消") { viewModel.cancelScan() }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

            Spacer()
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(FL.textSecondary.opacity(0.3))

            VStack(spacing: 4) {
                Text("点击「扫描」开始")
                    .font(FL.headlineFont)
                    .foregroundColor(FL.text)
                Text("默认扫描 Downloads 和 Desktop 目录")
                    .font(FL.captionFont)
                    .foregroundColor(FL.textSecondary)
            }

            Button("选择目录…") { viewModel.browseFolder() }
                .font(FL.captionFont)
                .foregroundColor(FL.accent)

            Spacer()
        }
    }

    // MARK: - 底部状态栏

    private var bottomBar: some View {
        HStack {
            if let result = viewModel.scanResult {
                Text("\(result.files.count) 个文件 · \(String(format: "%.1f", result.scanDuration))s")
                    .font(FL.microFont)
                    .foregroundColor(FL.textSecondary)
            } else {
                Text(viewModel.classifier.rules.count + viewModel.identifier.rules.count > 0
                     ? "就绪"
                     : "无规则")
                    .font(FL.microFont)
                    .foregroundColor(FL.textSecondary)
            }

            Spacer()

            if viewModel.isMonitoring {
                HStack(spacing: 4) {
                    Circle()
                        .fill(FL.safeColor)
                        .frame(width: 5, height: 5)
                    Text("实时监控")
                        .font(FL.microFont)
                        .foregroundColor(FL.safeColor)
                }
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(FL.textSecondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("退出 FileLens")
        }
    }

    // MARK: - 右键菜单

    private func contextMenu(for item: FileItem) -> some View {
        Group {
            Button {
                selectedFile = item
                showDetail = true
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }

            Divider()

            Button {
                revealInFinder(item)
            } label: {
                Label("在 Finder 显示", systemImage: "folder")
            }

            Button {
                copyPath(item)
            } label: {
                Label("拷贝路径", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                moveToTrash(item)
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
        }
    }

    // MARK: - 过滤逻辑

    private var hasResults: Bool {
        viewModel.scanResult != nil
    }

    private var safetyCounts: [SafetyLevel: Int] {
        guard let result = viewModel.scanResult else {
            return [.critical: 0, .caution: 0, .cleanable: 0, .safe: 0]
        }
        return result.groupedBySafety.mapValues { $0.count }
    }

    private func applyFilters() -> [FileItem] {
        guard let result = viewModel.scanResult else { return [] }

        var files = result.files

        // 安全等级过滤
        if let level = selectedLevel {
            files = files.filter { $0.safetyLevel == level }
        }

        // 文件类型过滤
        if selectedFilter != .all {
            let types = selectedFilter.fileTypes
            files = files.filter { types.contains($0.fileType) }
        }

        // 搜索过滤
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            files = files.filter {
                $0.name.lowercased().contains(lower) ||
                $0.description.lowercased().contains(lower) ||
                $0.path.lowercased().contains(lower) ||
                $0.fileExtension.lowercased().contains(lower)
            }
        }

        return files.sorted { $0.size > $1.size }
    }

    // MARK: - 操作

    private func revealInFinder(_ item: FileItem) {
        let success = NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
        if !success {
            errorMessage = "无法在 Finder 中定位文件：\(item.name)"
            showError = true
        }
    }

    private func moveToTrash(_ item: FileItem) {
        let url = URL(fileURLWithPath: item.path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            errorMessage = "移到废纸篓失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func copyPath(_ item: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    private func toggleMonitoring() {
        if viewModel.isMonitoring {
            viewModel.stopMonitoring()
        } else {
            viewModel.startMonitoring()
        }
    }
}
