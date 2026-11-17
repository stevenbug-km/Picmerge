import SwiftUI
import AppKit

// MARK: - 工作区二：网页长图
//
// 完整流程：输入地址 → 自动整页截图 → 选输出比例 → 裁剪 → 实际 100% 核对 → 保存。
// 所有状态都在 AppState 里，这里只负责「把状态显示出来、把点击传回去」。
//
// 布局说明：输出比例改成下拉菜单后，功能按钮可以全部放进同一排，
// 不会像 8 档分段控件那样把 HStack 撑爆、反过来挤窄左右两栏。

struct WebpageWorkspace: View {
    @EnvironmentObject private var state: AppState

    /// 输入框占位文字，同时也用来识别「这是网址输入框」。
    private let urlPlaceholder = "输入网页地址，例如 https://example.com"

    var body: some View {
        VStack(spacing: 14) {
            ToolbarCard {
                VStack(alignment: .leading, spacing: 10) {
                    // 第一行：网址 + 开始拼接
                    HStack(spacing: 10) {
                        TextField(urlPlaceholder, text: $state.urlString)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { state.startWebpageCapture() }
                            // macOS 上 SwiftUI 的 TextField 底层是 NSTextField。
                            // 监听「开始编辑」通知：只要焦点落到网址框，就自动全选旧地址，
                            // 这样直接敲新网址即可整段覆盖，不用先手动 Cmd+A。
                            .onReceive(NotificationCenter.default.publisher(
                                for: NSControl.textDidBeginEditingNotification)) { notification in
                                guard let field = notification.object as? NSTextField else { return }
                                // 只处理本工作区的网址框，不误伤其它输入框。
                                let isURLField =
                                    field.placeholderString?.contains("网页地址") == true
                                    || field.stringValue == state.urlString
                                guard isURLField else { return }

                                if let editor = field.currentEditor() {
                                    editor.selectAll(nil)
                                } else {
                                    field.selectText(nil)
                                }
                            }

                        Button {
                            state.startWebpageCapture()
                        } label: {
                            if state.capturePhase.isLoading {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("正在截取…")
                                }
                            } else {
                                Label("开始拼接", systemImage: "globe")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.capturePhase.isLoading)
                    }

                    // 第二行：所有功能按钮放一排。
                    // Picker 用 .menu（下拉）而不是 .segmented（分段），
                    // 8 档比例只占一个下拉的宽度，按钮才排得下。
                    HStack(spacing: 9) {
                        Text("输出比例")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()

                        Picker("输出比例", selection: $state.webScale) {
                            ForEach(state.scaleOptions, id: \.self) { value in
                                Text("\(Int(value * 100))%").tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 88)
                        .disabled(state.capturedImage == nil)

                        // 裁剪模式会强制切到「适合窗口」，查看方式此时没有意义，
                        // 隐藏它可以把宽度让给「确定裁剪 / 取消」两个按钮。
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
                            .frame(width: 112)
                            .disabled(state.capturedImage == nil)
                        }

                        CropToolbar()

                        Spacer(minLength: 0)
                    }
                }
            }

            // 失败提示单独成一条，避免用户不知道为什么没有结果。
            if case .failed(let message) = state.capturePhase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message).font(.callout)
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            ImageCanvas(image: state.resultImage)

            HStack(spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.tertiary)
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
    }

    private var hintText: String {
        if state.capturePhase.isLoading { return "正在等待网页图片和字体排版完成…" }
        guard state.capturedImage != nil else {
            return "输入网址后会自动截取整页；截图按网页正常显示尺寸生成，可再按比例缩小。"
        }
        if state.isCropping {
            return "拖动框内可移动；四角同时改两条边，四条边可分别拖动改单边；框外拖可重新拉框。调整好后点「确定裁剪」生效，点「取消」回到裁剪前。"
        }
        if state.previewMode == .actual {
            return "实际 100%：按最终输出像素显示，按住图片拖动即可查看不同区域、检查每一处细节。"
        }
        return "适合窗口：长图按预览区可用高度完整显示；右侧「最终尺寸」会随输出比例实时变化。"
    }
}
