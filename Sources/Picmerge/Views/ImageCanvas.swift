import SwiftUI
import AppKit

// MARK: - 统一预览画布
//
// 三个工作区共用同一块画布，规则固定：
//   * GeometryReader 只在外层出现一次，用来量出父容器给的可用空间；
//   * 「适合窗口」优先用满可用高度等比缩放，整张图完整可见；
//   * 「实际 100%」按原图像素尺寸显示，图片比预览区大时按住图片即可拖动浏览；
//   * 网页裁剪框是贴在「图片显示矩形」上的覆盖层，
//     因此坐标始终相对图片本身，不受窗口大小影响。
//
// 手势分工（很重要，避免互相抢事件）：
//   * 适合窗口：图片完整可见，不需要平移；调整顺序请用上方缩略图条。
//   * 实际 100%：图片可能超出预览区，拖动 = 平移浏览。
//   * 网页裁剪模式：强制适合窗口，裁剪框覆盖层独占拖动。

struct ImageCanvas: View {
    @EnvironmentObject private var state: AppState
    let image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size

            ZStack {
                if let image {
                    CanvasImageView(image: image, viewport: viewport)
                } else {
                    emptyView
                }
            }
            // 内部内容使用量到的尺寸，不再向外索要额外宽高。
            .frame(width: viewport.width, height: viewport.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: 空状态

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: state.mode.symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.title3.weight(.medium))
            Text(emptyHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if state.mode != .webpage {
                Button {
                    state.showImporter = true
                } label: {
                    Label("选择图片", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyTitle: String {
        switch state.mode {
        case .local: return "从图片开始拼接"
        case .webpage: return "把网页变成长图"
        case .split: return "拆分一张图片"
        }
    }

    private var emptyHint: String {
        switch state.mode {
        case .local: return "导入或拖入多张图片，选择横向、纵向或模板即可预览。"
        case .webpage: return "在上方输入网址并点击「开始拼接」，整页内容会自动生成一张长图。"
        case .split: return "导入一张图片，选择拆分模板，保存时会把每一块分别导出。"
        }
    }
}

// MARK: - 图片本体（负责显示尺寸、平移、覆盖层）
//
// 单独抽成一个 View，让「算尺寸」「画覆盖层」「处理手势」各归各的函数。
// 平移量这类临时状态都放在 AppState 里（见该文件注释），
// 视图本身不持有 @State，重建或换图时由 AppState.rebuildResult() 统一重置。

private struct CanvasImageView: View {
    @EnvironmentObject private var state: AppState
    let image: NSImage
    let viewport: CGSize

    var body: some View {
        // 图片 + 裁剪覆盖层组成一个整体，平移时一起移动。
        // 调整图片顺序统一交给上方的缩略图条，预览画布只负责「看」。
        let picture = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: displaySize.width, height: displaySize.height)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .overlay {
                // 网页长图与本地拼接共用同一个裁剪框，只在适合窗口 + 裁剪模式下出现。
                if state.supportsCrop, state.isCropping, state.previewMode == .fit {
                    cropOverlay
                }
            }
            .offset(effectivePanOffset)

        let content = ZStack(alignment: .center) { picture }
            .frame(width: viewport.width, height: viewport.height)
            .contentShape(Rectangle())

        // 只有「图片确实比预览区大」时才挂平移手势，
        // 否则它会在适合窗口下抢走裁剪框的拖动事件。
        return Group {
            if canPan {
                content.gesture(panGesture)
            } else {
                content
            }
        }
        // 实际 100% 时右上角浮出一个导航缩略图，可点可拖，快速定位到长图任意位置。
        .overlay(alignment: .topTrailing) {
            if state.previewMode == .actual, !state.isCropping {
                NavigatorView(image: image,
                              displaySize: displaySize,
                              viewport: viewport,
                              panOffset: effectivePanOffset,
                              limit: panLimit) { newOffset in
                    state.panOffset = newOffset
                    state.panBase = nil
                }
                .padding(12)
            }
        }
    }

    // MARK: 显示尺寸与平移范围

    /// 适合窗口：先假设高度填满，宽度超了再收敛；实际 100%：直接用原图像素尺寸。
    private var displaySize: CGSize {
        if state.previewMode == .actual { return image.size }

        let available = CGSize(width: max(1, viewport.width - 32),
                               height: max(1, viewport.height - 32))
        let aspect = image.size.width / max(1, image.size.height)
        var height = available.height
        var width = height * aspect
        if width > available.width {
            width = available.width
            height = width / aspect
        }
        return CGSize(width: width, height: height)
    }

    /// 每个方向允许的最大平移量。图片比预览区小的方向为 0，即不动。
    /// 换算集中在 NavigatorMath，导航缩略图和这里用的是同一套公式。
    private var panLimit: CGSize {
        NavigatorMath.panLimit(displaySize: displaySize, viewport: viewport)
    }

    private var canPan: Bool {
        panLimit.width > 0.5 || panLimit.height > 0.5
    }

    /// 把平移量限制在当前图片允许的范围内。
    /// 右侧参数一改，结果图尺寸可能变化，旧偏移就会越界；
    /// 这里统一 clamp，既保证显示正确，也让下一次拖动从看得见的位置继续。
    /// 关键是**不把偏移清零**——用户要求 100% 下调参数后仍停在原来的查看位置。
    private var effectivePanOffset: CGSize {
        let limit = panLimit
        return CGSize(width: min(max(state.panOffset.width, -limit.width), limit.width),
                      height: min(max(state.panOffset.height, -limit.height), limit.height))
    }

    /// 按住图片拖动 = 平移浏览。用 clamp 限制范围，图片不会被拖出视野之外。
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if state.panBase == nil { state.panBase = effectivePanOffset }
                let base = state.panBase ?? effectivePanOffset
                let limit = panLimit
                state.panOffset = CGSize(
                    width: min(max(base.width + value.translation.width, -limit.width), limit.width),
                    height: min(max(base.height + value.translation.height, -limit.height), limit.height)
                )
            }
            .onEnded { _ in state.panBase = nil }
    }

    // MARK: - Photoshop 风格裁剪框
    //
    // 这是一个「待确认」的裁剪框：框外压暗、框内透明，配三分线和 8 个手柄
    // （四角 + 四条边中点）。拖动只修改 AppState.cropDraft，完全不动结果图；
    // 只有点击「确定裁剪」才会真正应用到图片。
    //
    // 两个容易踩的坑，这里一次解决：
    //   1. 手柄锚点由 CropMath 向框内缩进，框贴着图片边缘时也不会有一半落在图外；
    //   2. 所有装饰图形都关掉命中测试，命中判定统一交给父层手势 + CropMath，
    //      否则点击落在某个图形上会绕开父层手势，表现为「角点不灵敏」。

    private var cropOverlay: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let box = state.displayCropRect(in: size)
            // 绘制位置 = 命中位置，都来自同一组锚点。
            let anchors = CropMath.anchors(for: box, in: size)

            ZStack(alignment: .topLeading) {
                // 框外四块半透明遮罩，营造「聚焦选区」效果。
                cropMask(x: 0, y: 0, w: size.width, h: box.minY)
                cropMask(x: 0, y: box.maxY, w: size.width, h: size.height - box.maxY)
                cropMask(x: 0, y: box.minY, w: box.minX, h: box.height)
                cropMask(x: box.maxX, y: box.minY, w: size.width - box.maxX, h: box.height)

                // 三分线：两条竖线 + 两条横线，方便构图。
                ForEach(1..<3, id: \.self) { step in
                    let fraction = CGFloat(step) / 3
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 1, height: box.height)
                        .position(x: box.minX + box.width * fraction, y: box.midY)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: box.width, height: 1)
                        .position(x: box.midX, y: box.minY + box.height * fraction)
                        .allowsHitTesting(false)
                }

                // 描边用「深色外圈 + 白色内圈」，在任何底色上都看得清。
                Rectangle()
                    .stroke(Color.black.opacity(0.45), lineWidth: 3)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)

                // 四条边中点的短条手柄：横边画横条、竖边画竖条。
                // 命中范围其实覆盖整条边（CropMath.edgeHitHalfThickness），不只是这个小条。
                ForEach(CropMath.edgeHandles, id: \.self) { handle in
                    if let point = anchors[handle] {
                        let horizontal = handle == .top || handle == .bottom
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                            )
                            .frame(width: horizontal ? 24 : 7,
                                   height: horizontal ? 7 : 24)
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }

                // 四角手柄最后画，压在边手柄之上；命中半径在 CropMath 里放大到 20pt。
                ForEach(CropMath.cornerHandles, id: \.self) { handle in
                    if let point = anchors[handle] {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                            )
                            .frame(width: 11, height: 11)
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if state.cropGestureStart == nil {
                            state.beginCropGesture(at: value.startLocation, in: size)
                        }
                        state.updateCropDraft(to: value.location, in: size)
                    }
                    .onEnded { _ in state.endCropGesture() }
            )
        }
        .allowsHitTesting(state.isCropping)
    }

    /// 在 SwiftUI 左上原点坐标系里画一块遮罩；宽高为 0 或负数时不画。
    @ViewBuilder
    private func cropMask(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        if w > 0, h > 0 {
            Rectangle()
                .fill(Color.black.opacity(0.48))
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: y + h / 2)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 实际 100% 导航缩略图
//
// 图片比预览区大时，右上角显示一张整图缩小版，上面盖一个「当前视口」方框。
// 点一下或拖着方框走，就能快速跳到长图任意位置，不必一下下拖大图。
// 换算只用到两个量：整图显示尺寸 displaySize、预览区尺寸 viewport。

private struct NavigatorView: View {
    let image: NSImage
    let displaySize: CGSize
    let viewport: CGSize
    let panOffset: CGSize
    let limit: CGSize
    /// 把算好的新平移量交回 AppState。
    let onChange: (CGSize) -> Void

    private let panelWidth: CGFloat = 178
    private let mapHeight: CGFloat = 100
    private let inset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "map").font(.caption2)
                Text("导航 · 点击或拖动定位").font(.caption2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { geometry in
                let area = geometry.size
                // 所有换算都交给 NavigatorMath 这个纯计算工具，视图只负责画。
                let layout = NavigatorMath.fit(displaySize: displaySize, into: area)
                let scale = layout.scale
                let fitted = layout.fittedSize
                let origin = layout.origin
                let visible = NavigatorMath.visibleRect(displaySize: displaySize,
                                                        viewport: viewport,
                                                        panOffset: panOffset)

                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: max(1, fitted.width), height: max(1, fitted.height))
                        .position(x: area.width / 2, y: area.height / 2)

                    Rectangle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                        .frame(width: max(1, fitted.width), height: max(1, fitted.height))
                        .position(x: area.width / 2, y: area.height / 2)

                    // 当前预览窗口看到的区域：白色边框 + 淡色填充。
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                        .frame(width: max(2, visible.width * scale),
                               height: max(2, visible.height * scale))
                        .position(x: origin.x + visible.midX * scale,
                                  y: origin.y + visible.midY * scale)
                }
                .contentShape(Rectangle())
                .gesture(
                    // minimumDistance: 0 让用户点一下也能跳转，拖动时连续跟随。
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onChange(NavigatorMath.panOffset(
                                for: value.location, scale: scale, origin: origin,
                                visible: visible, displaySize: displaySize,
                                viewport: viewport, limit: limit))
                        }
                        .onEnded { value in
                            onChange(NavigatorMath.panOffset(
                                for: value.location, scale: scale, origin: origin,
                                visible: visible, displaySize: displaySize,
                                viewport: viewport, limit: limit))
                        }
                )
            }
            .frame(height: mapHeight)
        }
        .padding(9)
        .frame(width: panelWidth)
        .background(Color.black.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}
