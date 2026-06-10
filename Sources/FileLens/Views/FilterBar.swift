import SwiftUI

enum FilterType: String, CaseIterable {
    case all = "全部"
    case document = "文档"
    case image = "图片"
    case video = "视频"
    case audio = "音频"
    case code = "代码"
    case archive = "压缩包"
    case installer = "安装包"
    case unknown = "未知文件"

    var icon: String {
        switch self {
        case .all:       return "tray.full"
        case .document:  return "doc.text"
        case .image:     return "photo"
        case .video:     return "film"
        case .audio:     return "music.note"
        case .archive:   return "doc.zipper"
        case .installer: return "arrow.down.app"
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .unknown:   return "questionmark.folder"
        }
    }

    /// 对应的 FileType 列表
    var fileTypes: [FileType] {
        switch self {
        case .all:       return FileType.allCases
        case .document:  return [.document]
        case .image:     return [.image]
        case .video:     return [.video]
        case .audio:     return [.audio]
        case .archive:   return [.archive]
        case .installer: return [.installer]
        case .code:      return [.code]
        case .unknown:   return [.other]
        }
    }
}

struct FilterBar: View {
    @Binding var selected: FilterType

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(FilterType.allCases, id: \.self) { type in
                FilterChip(
                    title: type.rawValue,
                    icon: type.icon,
                    isSelected: selected == type,
                    action: { selected = type }
                )
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
