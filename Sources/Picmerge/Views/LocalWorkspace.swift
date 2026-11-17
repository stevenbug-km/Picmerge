import SwiftUI

// MARK: - 通用工具条卡片
//
// 三个工作区共用同一种圆角卡片，保证界面风格一致。
struct ToolbarCard<Content: View>: View {
    private let content: Content

    /// @ViewBuilder 让调用处可以像写普通 View 一样直接写多行内容。
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

// MARK: - 工作区一：本地多图拼接
//
// 从上到下的顺序：
//   1. 工具条（导入 / 拼接方式 / 模板样式 / 查看方式）
//   2. 已导入缩略图条（可删除、可拖动排序）
//   3. 预览画布（适合窗口 / 实际 100%，只负责查看与拖动浏览）
//   4. 一行操作提示

struct LocalWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            ToolbarCard {
                VStack(alignment: .leading, spacing: 10) {
                    // 第一行：导入 + 拼接方式。
                    HStack(spacing: 12) {
                        Button {
                            state.showImporter = true
                        } label: {
                            Label("导入图片", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)

                        Picker("拼接方式", selection: $state.stitchLayout) {
                            ForEach(StitchLayout.allCases) { layout in
                                Text(layout.rawValue).tag(layout)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 240)

                        Spacer(minLength: 8)
                    }

                    // 第二行：模板样式（仅模板模式显示）+ 查看方式下拉。
                    HStack(spacing: 10) {
                        if state.stitchLayout == .template {
                            Button {
                                state.showTemplateGallery.toggle()
                            } label: {
                                HStack(spacing: 7) {
                                    Text("模板样式").font(.callout)
                                    Text(state.stitchTemplate.rawValue)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $state.showTemplateGallery,
                                     arrowEdge: .bottom) {
                                TemplateGallery { state.showTemplateGallery = false }
                            }
                        } else {
                            Text("选择「模板」拼接后可挑选模板样式")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        // 预览查看方式：默认「适合窗口」，可下拉切到「实际 100%」。
                        // 纵向、横向、模板三种拼接方式共用同一个设置。
                        // 裁剪模式强制「适合窗口」，此时把下拉隐藏，避免产生无效操作。
                        if !state.isCropping {
                            Text("查看")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()

                            Picker("查看方式", selection: $state.previewMode) {
                                ForEach(PreviewMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 118)
                        }
                    }

                    // 第三行：与网页长图完全相同的裁剪按钮组。
                    // 有图片时才出现，空工作区不占用高度。
                    if !state.localImages.isEmpty {
                        HStack(spacing: 10) {
                            CropToolbar()
                            Spacer(minLength: 8)
                            Text(state.isCropping
                                 ? "拖框内移动、拖四角或四条边缩放（边可分别调整）；点「确定裁剪」生效。"
                                 : "裁剪后可继续裁剪，点「清除裁剪」还原整张拼接图。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !state.localImages.isEmpty {
                ThumbnailStrip()
            }

            ImageCanvas(image: state.resultImage)

            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.tertiary)
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
    }

    private var hintText: String {
        if state.isCropping {
            return "拖框内移动、四角改两条边、四条边分别改单边，点「确定裁剪」生效；「取消」放弃本次，「清除裁剪」还原整图。"
        }
        if state.previewMode == .actual {
            return "实际 100%：按住图片拖动浏览，右上角导航缩略图可点击 / 拖动快速定位；右侧调参数仍停在当前位置。"
        }
        return "适合窗口：整张拼接图按预览区高度完整显示；拖动上方缩略图可调整顺序，切到「实际 100%」可拖动查看细节。"
    }
}
