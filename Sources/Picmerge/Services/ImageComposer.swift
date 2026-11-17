import Foundation
import AppKit

// MARK: - 画布渲染工具
//
// 这里用 NSBitmapImageRep 明确指定像素尺寸，而不是 NSImage.lockFocus()。
// 好处：输出的像素宽高一定等于我们计算的点数，不会被 Retina 的 2 倍缩放弄乱。
// 这是之前「长图变超宽」问题的根本修复点。

enum CanvasRenderer {
    /// 创建一张确定尺寸的画布，执行 draw 闭包，返回 NSImage。
    /// - Parameters:
    ///   - size: 画布尺寸（点 = 像素，1:1）
    ///   - background: 背景色
    ///   - draw: 在这张画布上绘图，参数是画布矩形（原点在左下角）
    static func render(size: NSSize,
                       background: NSColor,
                       draw: (NSRect) -> Void) -> NSImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        // 明确告诉 rep：一个点对应一个像素。
        rep.size = NSSize(width: width, height: height)
        let canvas = NSRect(x: 0, y: 0, width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high

        // 透明背景时不做填充，网页截图和裁剪结果才能保留正确的透明/底色。
        if background.alphaComponent > 0 {
            let fill = background.usingColorSpace(.deviceRGB) ?? .white
            fill.setFill()
            canvas.fill()
        }

        draw(canvas)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    /// 三种拼接方式共用的「画一张图」入口。
    ///
    /// 以前纵向/横向走 drawExact（完全忽略缩放和位移）、模板走 drawAspectFit，
    /// 结果就是「缩放、水平位移、垂直位移只有模板里有用」。现在统一到这里：
    ///   1. 先把图片等比适配进 slot（纵向/横向的 slot 恰好等于图片原始尺寸，
    ///      所以 scale = 1 时画面和以前完全一样，不会改变画布尺寸）；
    ///   2. 乘以每张图自己的 scale，以 slot 中心为锚点缩放；
    ///   3. 叠加 offsetX / offsetY 做水平、垂直位移；
    ///   4. 按 cornerRadius 裁出圆角后绘制。
    ///
    /// 圆角为什么改用 CGContext：之前用 NSBezierPath.addClip() 搭配
    /// NSGraphicsContext.saveGraphicsState()，在「手工创建的位图上下文」里
    /// 与 render() 外层那一次 save/restore 嵌套，裁剪状态并不稳定。
    /// CGContext 的 saveGState / clip / restoreGState 只作用于当前位图上下文，
    /// 边界明确，三种拼接方式都能稳定生效。
    static func drawItem(_ image: NSImage,
                         in slot: NSRect,
                         scale: CGFloat = 1,
                         offsetX: CGFloat = 0,
                         offsetY: CGFloat = 0,
                         cornerRadius: CGFloat = 0) {
        let source = image.size
        guard source.width > 0, source.height > 0,
              slot.width > 0, slot.height > 0 else { return }

        let fit = min(slot.width / source.width, slot.height / source.height)
        let width = source.width * fit * scale
        let height = source.height * fit * scale
        let rect = NSRect(
            x: slot.midX - width / 2 + offsetX,
            y: slot.midY - height / 2 + offsetY,
            width: width,
            height: height
        )
        guard rect.width > 0, rect.height > 0 else { return }

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if cornerRadius > 0 {
            // 半径不能超过短边的一半，否则圆角会互相重叠画出奇怪的形状。
            let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
            let path = CGPath(roundedRect: rect,
                              cornerWidth: radius,
                              cornerHeight: radius,
                              transform: nil)
            context.addPath(path)
            context.clip()
        }
        // from: .zero 表示绘制整张原图；operation .sourceOver 是正常叠加。
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }
}

// MARK: - 本地多图拼接引擎

enum ImageComposer {
    /// 根据拼接方式计算最终画布尺寸。
    private static func canvasSize(for items: [ImageItem],
                                   layout: StitchLayout,
                                   template: StitchTemplate,
                                   gap: CGFloat) -> NSSize {
        guard !items.isEmpty else { return .zero }
        let sizes = items.map { $0.image.size }

        switch layout {
        case .vertical:
            let width = sizes.map { $0.width }.max() ?? 1
            let height = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, items.count - 1))
            return NSSize(width: width, height: height)

        case .horizontal:
            let width = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, items.count - 1))
            let height = sizes.map { $0.height }.max() ?? 1
            return NSSize(width: width, height: height)

        case .template:
            return TemplateLayout.canvasSize(template: template, count: items.count, gap: gap)
        }
    }

    /// 生成拼接结果。
    /// - gap: 图片之间的间隔（内留白）
    /// - padding: 画布四周的外留白，三种拼接方式统一生效
    /// - cornerRadius: 每张图片的圆角
    /// - background: 所有留白区域的颜色
    static func compose(items: [ImageItem],
                        layout: StitchLayout,
                        template: StitchTemplate,
                        gap: CGFloat,
                        padding: CGFloat,
                        cornerRadius: CGFloat,
                        background: NSColor) -> NSImage? {
        guard !items.isEmpty else { return nil }
        let contentSize = canvasSize(for: items, layout: layout, template: template, gap: gap)
        // 外留白直接加在画布四周：宽高各加 2 倍 padding。
        let outerSize = NSSize(width: contentSize.width + padding * 2,
                               height: contentSize.height + padding * 2)

        return CanvasRenderer.render(size: outerSize, background: background) { canvas in
            // insetBy 得到扣除四周留白后的内部区域。
            // 后面所有布局都用 inner 而不是 canvas，三种方式就都自动支持留白了。
            let inner = canvas.insetBy(dx: padding, dy: padding)

            switch layout {
            case .vertical:
                // AppKit 坐标原点在左下角，所以「从上往下排」要从 inner.maxY 开始减。
                // 这里的 slot 就是每张图按原始尺寸占的位置；缩放 / 位移交给 drawItem 统一处理。
                var top = inner.maxY
                for item in items {
                    let imageSize = item.image.size
                    let slot = NSRect(x: inner.minX + (inner.width - imageSize.width) / 2,
                                      y: top - imageSize.height,
                                      width: imageSize.width,
                                      height: imageSize.height)
                    CanvasRenderer.drawItem(item.image,
                                            in: slot,
                                            scale: item.scale,
                                            offsetX: item.offsetX,
                                            offsetY: item.offsetY,
                                            cornerRadius: cornerRadius)
                    top -= imageSize.height + gap
                }

            case .horizontal:
                var left = inner.minX
                for item in items {
                    let imageSize = item.image.size
                    let slot = NSRect(x: left,
                                      y: inner.minY + (inner.height - imageSize.height) / 2,
                                      width: imageSize.width,
                                      height: imageSize.height)
                    CanvasRenderer.drawItem(item.image,
                                            in: slot,
                                            scale: item.scale,
                                            offsetX: item.offsetX,
                                            offsetY: item.offsetY,
                                            cornerRadius: cornerRadius)
                    left += imageSize.width + gap
                }

            case .template:
                // 模板的 slot 是预设版面里的矩形，同样走 drawItem，
                // 于是「缩放 / 位移 / 圆角」三种拼接方式的语义完全一致。
                let slots = TemplateLayout.slots(template: template,
                                                 count: items.count,
                                                 canvas: inner,
                                                 gap: gap)
                for (index, item) in items.enumerated() {
                    guard index < slots.count else { break }
                    CanvasRenderer.drawItem(item.image,
                                            in: slots[index],
                                            scale: item.scale,
                                            offsetX: item.offsetX,
                                            offsetY: item.offsetY,
                                            cornerRadius: cornerRadius)
                }
            }
        }
    }
}

// MARK: - 模板布局
//
// 模板的本质就是「一组矩形槽位」。把槽位计算独立出来，
// 以后加新模板只要在这里加一个 case，不用改绘图代码。

enum TemplateLayout {
    static func canvasSize(template: StitchTemplate, count: Int, gap: CGFloat) -> NSSize {
        switch template {
        case .filmStrip:
            let slotHeight: CGFloat = 520
            return NSSize(width: 1000,
                          height: CGFloat(count) * slotHeight + CGFloat(max(0, count - 1)) * gap)
        case .twoColumns:
            let rows = max(1, (count + 1) / 2)
            return NSSize(width: 1200, height: CGFloat(rows) * 460 + CGFloat(max(0, rows - 1)) * gap)
        case .collage, .triptych:
            return NSSize(width: 1200, height: 820)
        }
    }

    /// 返回 AppKit 坐标系（左下原点）的槽位数组，顺序对应图片顺序。
    static func slots(template: StitchTemplate,
                      count: Int,
                      canvas: NSRect,
                      gap: CGFloat) -> [NSRect] {
        switch template {
        case .filmStrip:
            let slotHeight = (canvas.height - CGFloat(max(0, count - 1)) * gap) / CGFloat(max(1, count))
            return (0..<count).map { index in
                // 第 0 张放最上面。
                let y = canvas.maxY - CGFloat(index + 1) * slotHeight - CGFloat(index) * gap
                return NSRect(x: canvas.minX, y: y, width: canvas.width, height: slotHeight)
            }

        case .twoColumns:
            let rows = max(1, (count + 1) / 2)
            let slotWidth = (canvas.width - gap) / 2
            let slotHeight = (canvas.height - CGFloat(max(0, rows - 1)) * gap) / CGFloat(rows)
            return (0..<count).map { index in
                let column = index % 2
                let row = index / 2
                let x = canvas.minX + CGFloat(column) * (slotWidth + gap)
                let y = canvas.maxY - CGFloat(row + 1) * slotHeight - CGFloat(row) * gap
                return NSRect(x: x, y: y, width: slotWidth, height: slotHeight)
            }

        case .collage:
            // 左侧一张大图，右侧 2×2 四张小图，共 5 个不重叠的槽位。
            // 注意：所有坐标都要加上 canvas.minX / canvas.minY。
            // 因为外层画布可能有四周留白，传进来的 canvas 是 insetBy 之后的 inner，
            // 若不偏移，设了「画布留白」后这两个模板的图片会跑到画布左上角。
            let g = gap
            let w = canvas.width
            let h = canvas.height
            let bigWidth = (w - g) * 0.58
            let rightWidth = w - g - bigWidth
            let smallWidth = (rightWidth - g) / 2
            let smallHeight = (h - g) / 2
            let left = canvas.minX
            let bottom = canvas.minY
            let rightX = left + bigWidth + g
            return [
                NSRect(x: left, y: bottom, width: bigWidth, height: h),
                NSRect(x: rightX, y: bottom + smallHeight + g, width: smallWidth, height: smallHeight),
                NSRect(x: rightX + smallWidth + g, y: bottom + smallHeight + g,
                       width: smallWidth, height: smallHeight),
                NSRect(x: rightX, y: bottom, width: smallWidth, height: smallHeight),
                NSRect(x: rightX + smallWidth + g, y: bottom, width: smallWidth, height: smallHeight)
            ]

        case .triptych:
            let g = gap
            let side = (canvas.width - 2 * g) * 0.25
            let center = canvas.width - 2 * side - 2 * g
            let left = canvas.minX
            let bottom = canvas.minY
            return [
                NSRect(x: left, y: bottom, width: side, height: canvas.height),
                NSRect(x: left + side + g, y: bottom, width: center, height: canvas.height),
                NSRect(x: left + side + center + 2 * g, y: bottom, width: side, height: canvas.height)
            ]
        }
    }
}
