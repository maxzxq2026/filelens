import SwiftUI

/// 整理预览界面
struct OrganizePreviewView: View {
    let preview: OrganizePreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isExecuting = false
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            header

            Divider()

            // 内容
            ScrollView {
                VStack(spacing: 12) {
                    // 统计摘要
                    summaryCards

                    // 按文件夹分组的文件列表
                    ForEach(preview.groupedByFolder.keys.sorted(by: <), id: \.self) { folder in
                        folderSection(folder: folder)
                    }
                }
                .padding(FL.paddingL)
            }

            Divider()

            // 底部按钮
            bottomBar
        }
        .frame(width: 460, height: 520)
        .background(FL.background)
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("整理方案预览")
                    .font(FL.titleFont)
                    .foregroundColor(FL.text)
                Text("以下文件将被移动到桌面对应文件夹")
                    .font(FL.captionFont)
                    .foregroundColor(FL.textSecondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(FL.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(FL.separator)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, FL.paddingL)
        .padding(.vertical, FL.paddingM)
    }

    // MARK: - 统计摘要

    private var summaryCards: some View {
        HStack(spacing: 8) {
            SummaryStatCard(
                icon: "arrow.right.circle.fill",
                color: FL.safeColor,
                count: preview.moveCount,
                label: "将移动"
            )
            SummaryStatCard(
                icon: "exclamationmark.triangle.fill",
                color: FL.cautionColor,
                count: preview.conflictCount,
                label: "有冲突"
            )
            SummaryStatCard(
                icon: "minus.circle.fill",
                color: FL.textSecondary,
                count: preview.skipCount,
                label: "将跳过"
            )
            SummaryStatCard(
                icon: "externaldrive.fill",
                color: FL.accent,
                count: nil,
                label: preview.formattedTotalSize,
                isText: true
            )
        }
    }

    // MARK: - 文件夹分组

    private func folderSection(folder: String) -> some View {
        let actions = preview.groupedByFolder[folder] ?? []
        let moveActions = actions.filter { $0.action == .move || $0.action == .conflict }
        let isExpanded = expandedFolders.contains(folder)

        return VStack(spacing: 0) {
            // 文件夹标题
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedFolders.contains(folder) {
                        expandedFolders.remove(folder)
                    } else {
                        expandedFolders.insert(folder)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FL.textSecondary)

                    Image(systemName: folderIcon(for: folder))
                        .font(.system(size: 14))
                        .foregroundColor(FL.accent)

                    Text("桌面/\(folder)/")
                        .font(FL.headlineFont)
                        .foregroundColor(FL.text)

                    Spacer()

                    Text("\(moveActions.count) 个文件")
                        .font(FL.captionFont)
                        .foregroundColor(FL.textSecondary)

                    Text(ByteCountFormatter.string(
                        fromByteCount: moveActions.reduce(0) { $0 + $1.file.size },
                        countStyle: .file
                    ))
                    .font(FL.monoFont)
                    .foregroundColor(FL.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FL.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: FL.smallRadius))
            }
            .buttonStyle(.plain)

            // 文件列表（展开时显示）
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(moveActions) { action in
                        HStack(spacing: 8) {
                            // 安全等级指示
                            Circle()
                                .fill(action.action == .conflict ? FL.cautionColor : FL.safeColor)
                                .frame(width: 4, height: 4)

                            // 文件名
                            Text(action.file.name)
                                .font(FL.bodyFont)
                                .foregroundColor(FL.text)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            // 冲突标记
                            if action.action == .conflict {
                                Text("重命名")
                                    .font(FL.microFont)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(FL.cautionColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }

                            // 大小
                            Text(ByteCountFormatter.string(
                                fromByteCount: action.file.size,
                                countStyle: .file
                            ))
                            .font(FL.monoFont)
                            .foregroundColor(FL.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(FL.cardBackground.opacity(0.5))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FL.cardRadius))
        .shadow(color: FL.cardShadow, radius: 2, y: 1)
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FL.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(FL.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: FL.smallRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: FL.smallRadius)
                            .stroke(FL.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: {
                isExecuting = true
                onConfirm()
            }) {
                HStack(spacing: 4) {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isExecuting ? "整理中…" : "确认整理 \(preview.moveCount) 个文件")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(preview.moveCount > 0 ? FL.accent : FL.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: FL.smallRadius))
            }
            .buttonStyle(.plain)
            .disabled(preview.moveCount == 0 || isExecuting)
        }
        .padding(.horizontal, FL.paddingL)
        .padding(.vertical, FL.paddingM)
    }

    // MARK: - Helper

    private func folderIcon(for folder: String) -> String {
        switch folder {
        case "文档":   return "doc.text.fill"
        case "图片":   return "photo.fill"
        case "视频":   return "film.fill"
        case "音频":   return "music.note"
        case "压缩包": return "doc.zipper"
        case "安装包": return "arrow.down.app.fill"
        default:       return "folder.fill"
        }
    }
}

// MARK: - 统计小卡片

private struct SummaryStatCard: View {
    let icon: String
    let color: Color
    let count: Int?
    let label: String
    var isText: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            if isText {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(FL.text)
            } else {
                Text("\(count ?? 0)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(FL.text)
                Text(label)
                    .font(FL.microFont)
                    .foregroundColor(FL.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(FL.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: FL.cardRadius))
        .shadow(color: FL.cardShadow, radius: 2, y: 1)
    }
}
