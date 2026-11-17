import SwiftUI
import AppKit

// MARK: - 模板样式下拉面板
//
// macOS 原生 Picker 的下拉里只能放文字，看不到版面长什么样。
// 这里用 Popover 自己画一个下拉面板，每个模板配一张版面缩略图。
// 缩略图直接复用 TemplateLayout.slots —— 真实拼接用的就是同一套槽位算法，
// 所以示意图和实际输出永远一致，不会出现「选的和看到的不一样」。

/// 单个模板的版面缩略图。
struct TemplateThumbnail: View {
    let template: StitchTemplate

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let canvas = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            // 固定用 4 张图来示意，四种模板都能画出完整的版面结构。
            let slots = TemplateLayout.slots(template: template,
                                             count: 4,
                                             canvas: canvas,
                                             gap: 3)

            ForEach(slots.indices, id: \.self) { index in
                let slot = slots[index]
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.28 + 0.09 * Double(index % 3)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)
                    )
                    .frame(width: max(1, slot.width), height: max(1, slot.height))
                    // TemplateLayout 用 AppKit 左下原点，SwiftUI 是左上原点，这里翻转 Y。
                    .position(x: slot.midX, y: size.height - slot.midY)
            }
        }
    }
}

/// 从「模板样式」按钮弹出的下拉面板。
struct TemplateGallery: View {
    @EnvironmentObject private var state: AppState
    /// 选中后由外层收起面板（Popover 的显示由 isPresented 控制）。
    let onSelect: () -> Void

    private let columns = [
        GridItem(.fixed(124), spacing: 12),
        GridItem(.fixed(124), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模板样式").font(.headline)
            Text("点击即可把当前拼接切换成这个版面。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(StitchTemplate.allCases) { template in
                    Button {
                        state.stitchTemplate = template
                        state.stitchLayout = .template
                        state.statusMessage = "已选择模板：\(template.rawValue)。"
                        onSelect()
                    } label: {
                        VStack(spacing: 7) {
                            TemplateThumbnail(template: template)
                                .frame(width: 112, height: 72)
                                .padding(5)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(state.stitchTemplate == template
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.2),
                                                lineWidth: state.stitchTemplate == template ? 2 : 1)
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
