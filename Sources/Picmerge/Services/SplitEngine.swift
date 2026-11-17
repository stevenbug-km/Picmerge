import Foundation
import AppKit

// MARK: - 单图拆分引擎
//
// 需求原文：「将一张图按照模板拆分成几个部分后，最终还是生成一张图」。
// 所以这里的做法是：
//   1. 按「列数 / 行数」把原图等分成若干块；
//   2. 保持每块的原始尺寸，在块与块之间插入间隔；
//   3. 重新拼成一张完整的新图输出。
//
// 行列数不再写死在四个预设模板里：模板只提供初始值，用户在右侧输入任意
// 行列数后，compose 与 pieces 都会按新值自动等分，模板本身不用改。
// 「保存」另有要求：把每个切块分别导出成独立文件，见 pieces(_:_:_:)。

enum SplitEngine {

    /// 行列数的安全上限，防止误输入 999 这种值生成上万张图片。
    static let maxGridLines = 16

    /// 把任意输入收敛成合法的正整数行列数。
    /// 界面已经做过一次 clamp，这里再兜底一次，引擎单独被调用也不会崩。
    static func normalizedGrid(columns: Int, rows: Int) -> (Int, Int) {
        (min(max(columns, 1), maxGridLines), min(max(rows, 1), maxGridLines))
    }

    // MARK: 合成预览图

    /// 按指定行列数切开并重新合成一张图（块与块之间留出 gap）。
    static func compose(source: NSImage?,
                        columns: Int,
                        rows: Int,
                        gap: CGFloat,
                        background: NSColor) -> NSImage? {
        guard let source else { return nil }

        let (columns, rows) = normalizedGrid(columns: columns, rows: rows)
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        // 每一块的尺寸（最后一块吸收除不尽的余数，避免丢像素）。
        let cellWidth = sourceSize.width / CGFloat(columns)
        let cellHeight = sourceSize.height / CGFloat(rows)

        // 输出画布 = 原图尺寸 + 块之间新增的间隔。
        let outputSize = NSSize(
            width: sourceSize.width + gap * CGFloat(columns - 1),
            height: sourceSize.height + gap * CGFloat(rows - 1)
        )

        return CanvasRenderer.render(size: outputSize, background: background) { canvas in
            for row in 0..<rows {
                for column in 0..<columns {
                    // 把 row = 0 定义为最上面一行，符合日常阅读顺序。
                    let sourceY = sourceSize.height - CGFloat(row + 1) * cellHeight
                    let from = NSRect(x: CGFloat(column) * cellWidth,
                                      y: sourceY,
                                      width: cellWidth,
                                      height: cellHeight)

                    let destinationX = CGFloat(column) * (cellWidth + gap)
                    let destinationY = canvas.maxY - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap
                    let to = NSRect(x: destinationX,
                                    y: destinationY,
                                    width: cellWidth,
                                    height: cellHeight)

                    // draw(in:from:) 的 from 用原图自身坐标系，正好用来「取其中一块」。
                    source.draw(in: to, from: from, operation: .sourceOver, fraction: 1)
                }
            }
        }
    }

    // MARK: 分别保存用的独立切片

    /// 按指定行列数把原图切成若干块，供「分别保存」使用。
    /// 与 compose 不同：这里不加间隔、不加背景，每块就是原图对应区域的原始像素。
    /// 返回顺序与阅读顺序一致：从上到下、从左到右，方便用 _1、_2… 编号。
    static func pieces(source: NSImage?, columns: Int, rows: Int) -> [NSImage] {
        guard let source,
              source.size.width > 0, source.size.height > 0 else { return [] }

        let (columns, rows) = normalizedGrid(columns: columns, rows: rows)
        let width = source.size.width
        let height = source.size.height
        let cellWidth = width / CGFloat(columns)
        let cellHeight = height / CGFloat(rows)

        var result: [NSImage] = []
        result.reserveCapacity(columns * rows)

        for row in 0..<rows {
            for column in 0..<columns {
                // 用「累加边界再取整」的方式算每块范围：
                // 相邻块共用同一个边界值，除不尽时由最后一块吸收余数，
                // 既不会丢像素，也不会出现重叠。
                let x0 = Int((CGFloat(column) * cellWidth).rounded())
                let x1 = Int((CGFloat(column + 1) * cellWidth).rounded())
                let y0 = Int((CGFloat(row) * cellHeight).rounded())
                let y1 = Int((CGFloat(row + 1) * cellHeight).rounded())
                let pieceWidth = max(1, x1 - x0)
                let pieceHeight = max(1, y1 - y0)

                // row = 0 是最上面一行；AppKit 的 from 矩形原点在左下角，
                // 所以 Y 要用原图高度减去这一块在上边缘坐标系里的位置。
                let from = NSRect(x: CGFloat(x0),
                                  y: height - CGFloat(y1),
                                  width: CGFloat(pieceWidth),
                                  height: CGFloat(pieceHeight))

                let piece = CanvasRenderer.render(
                    size: NSSize(width: pieceWidth, height: pieceHeight),
                    background: .clear,
                    draw: { canvas in
                        source.draw(in: canvas, from: from,
                                    operation: .sourceOver, fraction: 1)
                    }
                )
                if let piece { result.append(piece) }
            }
        }
        return result
    }
}
