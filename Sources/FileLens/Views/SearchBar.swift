import SwiftUI

/// 搜索栏组件
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索文件名、类型、路径…"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FL.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FL.bodyFont)
                .focused($isFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(FL.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(FL.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: FL.smallRadius))
        .overlay(
            RoundedRectangle(cornerRadius: FL.smallRadius)
                .stroke(isFocused ? FL.accent : FL.separator, lineWidth: 1)
        )
    }
}
