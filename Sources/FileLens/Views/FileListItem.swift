import SwiftUI

struct FileListItem: View {
    let item: FileItem
    let onDelete: () -> Void
    let onReveal: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // 文件类型图标（安全等级色）
            Image(systemName: item.fileType.iconName)
                .font(.system(size: 14))
                .foregroundColor(item.safetyLevel.color)
                .frame(width: 20)

            // 文件信息
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    // 所属文件夹（点击打开）
                    Button(action: { onReveal() }) {
                        HStack(spacing: 2) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(((item.path as NSString).deletingLastPathComponent as NSString).lastPathComponent)
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(FL.accent)
                    .lineLimit(1)
                    .help("在 Finder 中显示")

                    // 安全等级标签
                    HStack(spacing: 3) {
                        Image(systemName: item.safetyLevel.iconName)
                            .font(.system(size: 9))
                        Text(item.safetyLevel.description)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(item.safetyLevel.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.safetyLevel.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(item.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(FL.textTertiary)
                }
            }

            Spacer()

            // 悬停时显示删除按钮
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FL.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // 右侧箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(FL.textQuaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
