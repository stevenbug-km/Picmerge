import SwiftUI

// MARK: - 工作区三：单图拆分
//
// 导入一张图片 → 选拆分模板 → 自动切成若干块并重新合成一张图。
// 拆分算法在 SplitEngine.swift，这里只做界面。

struct SplitWorkspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            ToolbarCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            state.showImporter = true
                        } label: {
                            Label(state.splitSourceImage == nil ? "选择图片" : "更换图片",
                                  systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)

                        // 与本地拼接「模板样式」一致：点按钮弹出带版面缩略图的下拉面板，
                        // 选中的样式名始终显示在按钮上，比纯文字 Picker 更直观。
                        Button {
                            state.showSplitGallery.toggle()
                        } label: {
                            HStack(spacing: 7) {
                                Text("拆分样式").font(.callout)
                                Text(state.splitTemplate.rawValue)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $state.showSplitGallery,
                                 arrowEdge: .bottom) {
                            SplitTemplateGallery { state.showSplitGallery = false }
                        }

                        Spacer()

                        if state.splitSourceImage != nil {
                            Button(role: .destructive) {
                                state.splitSourceImage = nil
                                state.statusMessage = "已移除原图。"
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                    }

                    // 自定义行列时说明会自动换成「自定义 X 列 × Y 行」，模板缩略图面板不变。
                    Text(state.splitGridDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ImageCanvas(image: state.resultImage)

            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.tertiary)
                Text("预览仍是合成的一张图；点击「保存」会把每个切块分别导出，文件名自动追加 _1、_2… 后缀。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
    }
}
