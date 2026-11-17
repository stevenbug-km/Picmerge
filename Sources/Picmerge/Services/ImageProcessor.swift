import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 图像处理与导出
//
// 这个文件的职责：把「网页截到的原图」按输出比例缩放、按裁剪框裁切，
// 以及把最终 NSImage 编码成 PNG / JPEG / BMP / TIFF 写到磁盘。

enum ImageProcessor {
    /// 生成网页长图的最终结果。
    /// - Parameters:
    ///   - source: WebKit 截到的整页原图
    ///   - scale: 输出比例，1.0 = 100%
    ///   - crop: 归一化裁剪框（原点左下，取值 0...1）；nil 表示不裁剪
    static func process(source: NSImage?, scale: Double, crop cropRect: CGRect?) -> NSImage? {
        guard let source, source.size.width > 0, source.size.height > 0 else { return nil }

        let factor = CGFloat(min(max(scale, 0.1), 1.0))
        let width = max(1, Int((source.size.width * factor).rounded()))
        let height = max(1, Int((source.size.height * factor).rounded()))
        let scaledSize = NSSize(width: width, height: height)

        // 用 CanvasRenderer 保证「点数 = 像素」，不会因 Retina 屏幕再放大一倍。
        // 注意：guard 里不能直接跟尾随闭包，所以先算出结果再解包。
        let scaledResult = CanvasRenderer.render(size: scaledSize, background: .clear) { canvas in
            source.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)
        }
        guard let scaled = scaledResult else { return nil }

        return crop(scaled, normalizedRect: cropRect)
    }

    /// 按归一化矩形裁一张图片。网页长图和本地拼接共用这个函数。
    /// - rect: 原点在左下角、取值 0...1 的裁剪框；nil 表示原样返回。
    ///
    /// 用「把指定区域画进一张新画布」的方式裁剪，而不是 CGImage.cropping(to:)，
    /// 这样不用操心 CGImage 与 AppKit 的 Y 轴方向差异。
    static func crop(_ image: NSImage?, normalizedRect rect: CGRect?) -> NSImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        guard let rect else { return image }

        let fromRect = NSRect(x: rect.minX * image.size.width,
                              y: rect.minY * image.size.height,
                              width: rect.width * image.size.width,
                              height: rect.height * image.size.height)
        let croppedWidth = max(1, Int(fromRect.width.rounded()))
        let croppedHeight = max(1, Int(fromRect.height.rounded()))

        return CanvasRenderer.render(
            size: NSSize(width: croppedWidth, height: croppedHeight),
            background: .clear,
            draw: { canvas in
                image.draw(in: canvas, from: fromRect, operation: .sourceOver, fraction: 1)
            }
        )
    }
}

// MARK: - 导出

/// 自定义错误类型，让保存失败时的提示更具体，也是 Swift 错误处理的常见写法。
enum ExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "无法把图片编码成所选格式。"
        }
    }
}

enum ImageExporter {
    static func write(image: NSImage, to url: URL, format: ExportFormat) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: format.bitmapType,
                                               properties: [.compressionFactor: 0.9]) else {
            throw ExportError.encodingFailed
        }
        // .atomic 会先写临时文件再替换，避免保存中途失败留下损坏文件。
        try data.write(to: url, options: .atomic)
    }
}
