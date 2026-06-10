import SwiftUI

/// 安全等级统计卡片
struct StatsCard: View {
    let level: SafetyLevel
    let count: Int
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: 4) {
                Image(systemName: level.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(level.flColor)

                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(FL.text)

                Text(level.label)
                    .font(FL.microFont)
                    .foregroundColor(FL.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(FL.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: FL.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FL.cardRadius)
                    .stroke(isSelected ? level.flColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: FL.cardShadow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// 统计卡片组
struct StatsCardGroup: View {
    let counts: [SafetyLevel: Int]
    var selectedLevel: SafetyLevel? = nil
    var onSelect: ((SafetyLevel?) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SafetyLevel.allCases) { level in
                StatsCard(
                    level: level,
                    count: counts[level] ?? 0,
                    isSelected: selectedLevel == level,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onSelect?(selectedLevel == level ? nil : level)
                        }
                    }
                )
            }
        }
    }
}
