import Foundation
import CoreGraphics

// MARK: - 裁剪框几何计算（纯函数，可以脱离界面单独自检）
//
// 为什么单独一个文件：
//   * 视图只负责「画」，点哪里算哪个手柄、拖完框变成什么样，全部集中在这里；
//   * 8 个手柄（四角 + 四条边）的命中范围统一调整，不会某个角落特别难点；
//   * 和 NavigatorMath 一样是纯计算，命令行可以直接跑断言，不必靠肉眼去点。
//
// 坐标系约定：
//   * cropDraft / 返回的矩形：归一化 0...1，SwiftUI 左上原点；
//   * anchors / 命中判定 / 手势坐标：显示坐标（pt），同样是 SwiftUI 左上原点。
//
// 「贴边」问题的根因：
//   以前手柄画在裁剪框的正角上。当框被拖到和图片一样大时，四角手柄有一半
//   落在图片外面（既被裁掉看不见，也收不到点击），命中区域只剩四分之一，
//   于是感觉「角点不灵敏」。现在 8 个手柄统一向框内缩进几 pt，永远留在图片里。

enum CropMath {

    /// 手柄锚点相对框边界向内缩进的点数。
    static let handleInset: CGFloat = 7
    /// 角手柄命中区域的半径（可见方块只有 11pt，命中范围放大更好点中）。
    static let cornerHitRadius: CGFloat = 20
    /// 边手柄命中带的半厚度；沿整条边都能拖，不只是中间那一个小竖条。
    static let edgeHitHalfThickness: CGFloat = 12
    /// 归一化最小边长，避免拖出 0 宽高导致生成空图片。
    static let minSize: CGFloat = 0.03

    static let cornerHandles: [CropHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    static let edgeHandles: [CropHandle] = [.top, .bottom, .left, .right]

    // MARK: 手柄锚点

    /// 返回 8 个手柄在预览图上的绘制位置。
    /// 绘制与命中判定共用这一组点，保证「看得到的」和「点得到的」完全一致。
    static func anchors(for box: CGRect, in size: CGSize) -> [CropHandle: CGPoint] {
        // 框很小时缩进量也要跟着变小，否则左右两个手柄会跑到对面去。
        let ix = min(handleInset, max(0, box.width) / 3)
        let iy = min(handleInset, max(0, box.height) / 3)

        func clampX(_ value: CGFloat) -> CGFloat { min(max(0, value), max(0, size.width)) }
        func clampY(_ value: CGFloat) -> CGFloat { min(max(0, value), max(0, size.height)) }

        return [
            .topLeft:     CGPoint(x: clampX(box.minX + ix), y: clampY(box.minY + iy)),
            .topRight:    CGPoint(x: clampX(box.maxX - ix), y: clampY(box.minY + iy)),
            .bottomLeft:  CGPoint(x: clampX(box.minX + ix), y: clampY(box.maxY - iy)),
            .bottomRight: CGPoint(x: clampX(box.maxX - ix), y: clampY(box.maxY - iy)),
            .top:         CGPoint(x: clampX(box.midX),      y: clampY(box.minY + iy)),
            .bottom:      CGPoint(x: clampX(box.midX),      y: clampY(box.maxY - iy)),
            .left:        CGPoint(x: clampX(box.minX + ix), y: clampY(box.midY)),
            .right:       CGPoint(x: clampX(box.maxX - ix), y: clampY(box.midY))
        ]
    }

    // MARK: 命中判定

    /// 手势起点落在哪个控制部位上。
    /// 判定优先级：四角 → 四条边 → 框内移动 → 框外重新拉框。
    /// 四角优先很重要：角落同时靠近两条边，用户在这里的意图几乎一定是「等比缩放角」。
    static func handle(at point: CGPoint, for box: CGRect, in size: CGSize) -> CropHandle {
        let points = anchors(for: box, in: size)

        // 1. 四角：以「内缩后的锚点」为中心的正方形区域。
        //    锚点内缩后，框贴着图片边缘时命中区域仍完整落在图片内。
        for handle in cornerHandles {
            guard let anchor = points[handle] else { continue }
            if abs(point.x - anchor.x) <= cornerHitRadius,
               abs(point.y - anchor.y) <= cornerHitRadius {
                return handle
            }
        }

        // 2. 四条边：沿边方向预留两端给角，垂直方向是一条 24pt 宽的命中带。
        //    预留量随框变小而缩小，小框上也点得到边中点。
        let reserveX = min(cornerHitRadius, box.width / 3)
        let reserveY = min(cornerHitRadius, box.height / 3)
        for handle in edgeHandles {
            guard let anchor = points[handle] else { continue }
            switch handle {
            case .top, .bottom:
                if point.x >= box.minX + reserveX,
                   point.x <= box.maxX - reserveX,
                   abs(point.y - anchor.y) <= edgeHitHalfThickness {
                    return handle
                }
            case .left, .right:
                if point.y >= box.minY + reserveY,
                   point.y <= box.maxY - reserveY,
                   abs(point.x - anchor.x) <= edgeHitHalfThickness {
                    return handle
                }
            default:
                break
            }
        }

        // 3. 框内拖动 = 整体移动；框外拖动 = 重新拉一个新框。
        return box.contains(point) ? .move : .newBox
    }

    // MARK: 拖拽计算

    /// 根据手柄类型算出新的裁剪框。
    /// - Parameters:
    ///   - base: 手势开始时的归一化框（已经 clamp 过）
    ///   - handle: beginCropGesture 判定出的手柄
    ///   - start / point: 手势起点与当前点，显示坐标 pt
    ///   - size: 预览图的显示尺寸，用于把位移换算回归一化值
    ///
    /// 关键规则：只移动「被抓住的那一条 / 两条边」，对面的边保持不动。
    /// 这样四条边才能真正分别调整，而不会一拖就把整个框一起缩放。
    static func updatedRect(base: CGRect,
                            handle: CropHandle,
                            start: CGPoint,
                            point: CGPoint,
                            in size: CGSize) -> CGRect {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let dx = (point.x - start.x) / width
        let dy = (point.y - start.y) / height

        switch handle {
        case .newBox:
            // 从起点到当前点拉一个矩形，方向随意（往左上拖也正确）。
            let sx = min(max(0, start.x / width), 1)
            let sy = min(max(0, start.y / height), 1)
            let ex = min(max(0, point.x / width), 1)
            let ey = min(max(0, point.y / height), 1)
            return clamped(CGRect(x: min(sx, ex), y: min(sy, ey),
                                  width: abs(ex - sx), height: abs(ey - sy)))

        case .move:
            // 整体平移：尺寸不变，只是被图片边界挡住，不会拖出去。
            let x = min(max(0, base.minX + dx), max(0, 1 - base.width))
            let y = min(max(0, base.minY + dy), max(0, 1 - base.height))
            return CGRect(x: x, y: y, width: base.width, height: base.height)

        default:
            break
        }

        var left = base.minX
        var right = base.maxX
        var top = base.minY
        var bottom = base.maxY
        var touchesLeft = false, touchesRight = false
        var touchesTop = false, touchesBottom = false

        switch handle {
        case .topLeft:
            left += dx; top += dy
            touchesLeft = true; touchesTop = true
        case .topRight:
            right += dx; top += dy
            touchesRight = true; touchesTop = true
        case .bottomLeft:
            left += dx; bottom += dy
            touchesLeft = true; touchesBottom = true
        case .bottomRight:
            right += dx; bottom += dy
            touchesRight = true; touchesBottom = true
        case .top:
            top += dy
            touchesTop = true
        case .bottom:
            bottom += dy
            touchesBottom = true
        case .left:
            left += dx
            touchesLeft = true
        case .right:
            right += dx
            touchesRight = true
        case .newBox, .move:
            break
        }

        // 只约束被抓住的边，另一条边保持原值；顺带保证最小尺寸和 0...1 范围。
        if touchesLeft   { left   = min(max(0, left), right - minSize) }
        if touchesRight  { right  = max(min(1, right), left + minSize) }
        if touchesTop    { top    = min(max(0, top), bottom - minSize) }
        if touchesBottom { bottom = max(min(1, bottom), top + minSize) }

        return clamped(CGRect(x: left, y: top,
                              width: right - left, height: bottom - top))
    }

    // MARK: 范围钳制

    /// 把任意矩形收敛到 0...1 内，并保证不小于最小边长。
    /// 界面绘制、确认裁剪、手势计算三处共用，避免各写一份导致行为不一致。
    static func clamped(_ rect: CGRect) -> CGRect {
        let x = min(max(0, rect.minX), 1 - minSize)
        let y = min(max(0, rect.minY), 1 - minSize)
        let width = min(max(minSize, rect.width), 1 - x)
        let height = min(max(minSize, rect.height), 1 - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
