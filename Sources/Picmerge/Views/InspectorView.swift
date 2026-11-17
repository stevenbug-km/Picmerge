import SwiftUI
import AppKit

// MARK: - 右侧参数检查器
//
// 根据当前工作区显示不同的可调参数。
// 这样中间画布始终尽量大，参数集中在右侧，界面也更接近专业 macOS 应用。

struct InspectorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch state.mode {
                case .local: localInspector
                case .webpage: webpageInspector
                case .split: splitInspector
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: 本地拼接参数

    @ViewBuilder
    private var localInspector: some View {
        SectionHeader("留白与样式")
        HintText("以下参数在纵向、横向、模板三种拼接方式下都生效；既能拖动滑块，也能在右侧数字框直接输入。圆角拉到最大时，正方形图片会变成圆形，长方形会变成胶囊形。")

        LabeledSlider(title: "图片间距", value: $state.stitchGap,
                      range: 0...state.maxSpacing, unit: "pt")
        LabeledSlider(title: "画布留白", value: $state.stitchPadding,
                      range: 0...state.maxSpacing, unit: "pt")
        LabeledSlider(title: "图片圆角", value: $state.cornerRadius,
                      range: 0...state.maxCornerRadius, unit: "pt")
        ColorPicker("留白颜色", selection: $state.canvasColor)
            .font(.callout)
        InfoRow(label: "裁剪", value: state.hasCrop ? "自定义区域" : "整张图")

        Divider()

        SectionHeader("图片图层")
        if state.localImages.isEmpty {
            HintText("导入图片后，这里会按顺序显示每一张。")
        } else {
            ForEach(state.localImages) { item in
                HStack(spacing: 9) {
                    Image(nsImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.caption).lineLimit(1)
                        Text("\(Int(item.image.size.width)) × \(Int(item.image.size.height))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.selectedImageID == item.id
                              ? Color.accentColor.opacity(0.14)
                              : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { state.selectImage(item.id) }
            }

            Divider()
            SectionHeader("选中图片")
            if state.selectedImage != nil {
                LabeledSlider(title: "缩放",
                              value: Binding(
                                get: { state.selectedImage?.scale ?? 1 },
                                set: { state.updateSelectedImage(scale: $0) }
                              ),
                              range: 0.3...2,
                              unit: "×")

                LabeledSlider(title: "水平位移",
                              value: Binding(
                                get: { state.selectedImage?.offsetX ?? 0 },
                                set: { state.updateSelectedImage(x: $0) }
                              ),
                              range: -300...300,
                              unit: "pt")

                LabeledSlider(title: "垂直位移",
                              value: Binding(
                                get: { state.selectedImage?.offsetY ?? 0 },
                                set: { state.updateSelectedImage(y: $0) }
                              ),
                              range: -300...300,
                              unit: "pt")

                HintText("缩放与位移在纵向、横向、模板三种拼接方式下都生效，以每张图片自身位置为中心调整。缩放放大后超出画布的部分会被裁掉，缩小则露出留白颜色。")

                HStack(spacing: 8) {
                    Button("上移") { state.moveSelectedImage(by: -1) }
                    Button("下移") { state.moveSelectedImage(by: 1) }
                    Button("删除", role: .destructive) { state.removeSelectedImage() }
                }
                .buttonStyle(.bordered)
            } else {
                HintText("点击上方任意一张图片即可调整。")
            }
        }
    }

    // MARK: 网页长图参数

    @ViewBuilder
    private var webpageInspector: some View {
        SectionHeader("截图信息")
        InfoRow(label: "原始尺寸",
                value: state.capturedImage == nil
                    ? "尚未截取"
                    : "\(Int(state.capturedImage!.size.width)) × \(Int(state.capturedImage!.size.height)) px")
        InfoRow(label: "输出比例", value: "\(Int(state.webScale * 100))%")
        InfoRow(label: "最终尺寸", value: state.resultSizeDescription)
        InfoRow(label: "裁剪", value: state.webCrop == nil ? "整页" : "自定义区域")

        HintText("「适合窗口」预览会按预览区高度等比缩放，所以画面大小不随比例改变；看这里的「最终尺寸」即可确认输出像素。")

        Divider()

        SectionHeader("输出")
        HintText("保存时可以选择路径、输入文件名，并指定 PNG / JPEG / BMP / TIFF，默认 PNG。")

        Divider()

        SectionHeader("使用提示")
        VStack(alignment: .leading, spacing: 8) {
            HintText("1. 输入地址并点击「开始拼接」。")
            HintText("2. 用下拉菜单选 100%–30% 输出比例。")
            HintText("3. 点「裁剪」后出现裁剪框，拖框内移动、拖四角或四条边缩放，点「确定裁剪」生效。")
            HintText("4. 切到「实际 100%」，按住图片拖动或用右上角导航缩略图快速定位，核对细节。")
            HintText("5. 点右上角「保存」或「分享」。")
        }
    }

    // MARK: 单图拆分参数

    @ViewBuilder
    private var splitInspector: some View {
        SectionHeader("拆分设置")
        LabeledSlider(title: "块间间隔", value: $state.splitGap, range: 0...48, unit: "pt")
        ColorPicker("画布背景", selection: $state.canvasColor)
            .font(.callout)

        Divider()

        SectionHeader("切分行列")
        HintText("拆分样式只提供预设。这里的列数、行数可以直接输入或用加减按钮调整，程序按原图尺寸自动等分；预览和「分别保存」都立即按新网格重算。")
        GridNumberRow(title: "列数", value: gridColumnsBinding, range: state.splitGridRange)
        GridNumberRow(title: "行数", value: gridRowsBinding, range: state.splitGridRange)
        if !state.splitGridMatchesTemplate {
            HStack(spacing: 8) {
                Label("自定义网格", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Button("恢复模板行列") { state.applySplitTemplateGrid() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }

        Divider()

        SectionHeader("模板说明")
        InfoRow(label: "当前样式", value: state.splitTemplate.rawValue)
        InfoRow(label: "切块数", value: "\(state.splitPieceCount) 张")
        InfoRow(label: "每块约", value: state.splitPieceSizeDescription)
        HintText(state.splitGridDescription)

        Divider()
        SectionHeader("输出")
        InfoRow(label: "预览尺寸", value: state.resultSizeDescription)
        HintText("预览始终是合成的一张图。点击「保存」时，\(state.splitPieceCount) 个切块会分别导出，文件名自动追加 _1、_2… 后缀。")
        HintText("系统「分享」仍然分享这一张合成图。")
    }

    /// 列 / 行的 Binding 都走 AppState.setSplitGrid，输入越界时自动收敛到 1...16。
    /// 用计算属性返回 Binding，视图里依然不需要任何 @State。
    private var gridColumnsBinding: Binding<Int> {
        Binding(get: { state.splitColumns },
                set: { state.setSplitGrid(columns: $0) })
    }

    private var gridRowsBinding: Binding<Int> {
        Binding(get: { state.splitRows },
                set: { state.setSplitGrid(rows: $0) })
    }
}

// MARK: - 小组件

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct HintText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            // fixedSize 保证数值不会被 Spacer 挤到零宽度而消失。
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 既能拖动、又能直接输入数字的滑块，三个工作区共用。
///
/// SwiftUI 的 TextField(value:format:) 对 CGFloat 的类型推断不稳定，
/// 所以用一个 Double 绑定做中转：读取时转 Double，写入时 clamp 回滑块范围再转 CGFloat。
/// 这样输入框和滑块永远保持一致，也不会出现「输入 500 但滑块只到 60」的割裂感。
private struct LabeledSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let unit: String

    private var numberBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(value) },
            set: { input in
                let lower = Double(range.lowerBound)
                let upper = Double(range.upperBound)
                value = CGFloat(min(max(input, lower), upper))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.callout).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                TextField("", value: numberBinding,
                          format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.caption.monospacedDigit())
                    .frame(width: 56)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Slider(value: $value, in: range)
        }
    }
}

/// 整数输入行：数字框 + 加减按钮，两者共用一个 clamp 过的 Binding。
/// 单图拆分的行数、列数用它，输入 0 或 999 都会自动收敛到允许范围。
private struct GridNumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    private var clampedValue: Binding<Int> {
        Binding(get: { value },
                set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            TextField("", value: clampedValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.caption.monospacedDigit())
                .frame(width: 52)
            Stepper("", value: clampedValue, in: range)
                .labelsHidden()
                .fixedSize()
        }
    }
}
