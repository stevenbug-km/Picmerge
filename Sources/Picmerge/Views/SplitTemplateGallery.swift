import SwiftUI
import AppKit

// MARK: - 拆分样式下拉面板
//
// 与本地拼接的 TemplateGallery 是同一套交互：Popover + 缩略图网格。
// 缩略图按 SplitTemplate 的 columns / rows 画格子，表示这个「预设」的版面；
// 选完之后右侧仍可自由输入行列数，实际切图以 AppState.splitColumns/splitRows 为准。
// 格子里的数字对应分别保存时的 _1、_2… 文件名后缀（预设状态下完全一致）。

/// 单个拆分模板的版面示意缩略图。
struct SplitTemplateThumbnail: View {
    let template: SplitTemplate

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let columns = template.columns
            let rows = template.rows
            let gap: CGFloat = 3
            let cellWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

            ForEach(0..<(columns * rows), id: \.self) { index in
                let column = index % columns
                let row = index / columns
                let x = CGFloat(column) * (cellWidth + gap)
                let y = CGFloat(row) * (cellHeight + gap)

                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.22 + 0.08 * Double(index % 4)))
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: max(1, cellWidth), height: max(1, cellHeight))
                .position(x: x + cellWidth / 2, y: y + cellHeight / 2)
            }
        }
    }
}

/// 从「拆分样式」按钮弹出的下拉面板。
struct SplitTemplateGallery: View {
    @EnvironmentObject private var state: AppState
    /// 选中后由外层收起 Popover。
    let onSelect: () -> Void

    private let columns = [
        GridItem(.fixed(124), spacing: 12),
        GridItem(.fixed(124), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拆分样式").font(.headline)
            Text("点击即可把这个版面作为预设；右侧还能自己输入列数、行数，自由组合任意网格。保存时会分别导出 _1、_2… 编号的切片。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SplitTemplate.allCases) { template in
                    Button {
                        state.splitTemplate = template
                        state.statusMessage = "已选择拆分样式：\(template.rawValue)。"
                        onSelect()
                    } label: {
                        VStack(spacing: 7) {
                            SplitTemplateThumbnail(template: template)
                                .frame(width: 112, height: 72)
                                .padding(5)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(state.splitTemplate == template
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.2),
                                                lineWidth: state.splitTemplate == template ? 2 : 1)
                                )
                            Text(template.rawValue)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 292)
    }
}
