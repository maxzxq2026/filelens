import SwiftUI

/// 文件列表行视图
struct FileItemRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            // 文件图标
            Image(systemName: item.fileType.iconName)
                .font(.system(size: 18))
                .foregroundColor(item.safetyLevel.color)
                .frame(width: 28, height: 28)

            // 文件信息
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 右侧信息
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedSize)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Image(systemName: item.safetyLevel.iconName)
                        .font(.system(size: 9))
                        .foregroundColor(item.safetyLevel.color)
                    Text(item.safetyLevel.label)
                        .font(.system(size: 10))
                        .foregroundColor(item.safetyLevel.color)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
