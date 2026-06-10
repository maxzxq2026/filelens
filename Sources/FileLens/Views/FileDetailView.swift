import SwiftUI

/// 文件详情视图
struct FileDetailView: View {
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 图标 + 文件名
            HStack(spacing: 12) {
                Image(systemName: item.fileType.iconName)
                    .font(.system(size: 32))
                    .foregroundColor(item.safetyLevel.color)
                    .frame(width: 48, height: 48)
                    .background(item.safetyLevel.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)

                    Text(item.fileType.label)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 安全等级标签
            HStack {
                Image(systemName: item.safetyLevel.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(item.safetyLevel.color)
                Text(item.safetyLevel.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(item.safetyLevel.color)
                Spacer()
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(item.safetyLevel.color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // 详细信息
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: "大小", value: item.formattedSize)
                InfoRow(label: "类型", value: item.fileExtension.isEmpty ? "无扩展名" : ".\(item.fileExtension)")
                InfoRow(label: "创建时间", value: item.formattedCreated)
                InfoRow(label: "修改时间", value: item.formattedModified)
                InfoRow(label: "路径", value: item.path)
            }

            Spacer()

            // 底部操作
            HStack {
                Spacer()

                Button(action: { revealInFinder() }) {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: item.path)
        NSWorkspace.shared.selectFile(
            url.path,
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }
}

/// 信息行
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
