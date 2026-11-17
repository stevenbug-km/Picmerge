import Foundation
import CoreGraphics

// MARK: - 导航缩略图的坐标换算
//
// 这里全是纯数学，不依赖 SwiftUI / AppKit / 任何界面状态，
// 因此可以单独在命令行自检里验证「点缩略图某处 → 预览跳到哪」是否正确。
// 视图层（ImageCanvas.swift 的 NavigatorView）只负责把结果画出来。
//
// 涉及三个坐标系：
//   1. 图片显示坐标系：以图片左上角为 (0,0)，尺寸 = displaySize；
//   2. 预览视口：屏幕上那块可见区域，尺寸 = viewport；
//   3. 导航缩略图坐标系：整图按 scale 缩小后，居中放在缩略图区域里。

enum NavigatorMath {
    /// 图片比预览区大时，每个方向允许的最大平移量（图片中心相对预览区中心的偏移）。
    static func panLimit(displaySize: CGSize, viewport: CGSize) -> CGSize {
        CGSize(width: max(0, (displaySize.width - viewport.width) / 2),
               height: max(0, (displaySize.height - viewport.height) / 2))
    }

    /// 整图等比缩小到能放进缩略图区域：返回倍率、缩小后尺寸、居中原点。
    static func fit(displaySize: CGSize, into area: CGSize)
        -> (scale: CGFloat, fittedSize: CGSize, origin: CGPoint) {
        let scale = min(area.width / max(1, displaySize.width),
                        area.height / max(1, displaySize.height))
        let fitted = CGSize(width: displaySize.width * scale,
                            height: displaySize.height * scale)
        let origin = CGPoint(x: (area.width - fitted.width) / 2,
                             y: (area.height - fitted.height) / 2)
        return (scale, fitted, origin)
    }

    /// 预览窗口此刻在「图片显示坐标系」里对应哪一块。
    /// 图片比预览区小时，交集自然就是整张图。
    static func visibleRect(displaySize: CGSize,
                            viewport: CGSize,
                            panOffset: CGSize) -> CGRect {
        let raw = CGRect(
            x: (displaySize.width - viewport.width) / 2 - panOffset.width,
            y: (displaySize.height - viewport.height) / 2 - panOffset.height,
            width: viewport.width,
            height: viewport.height
        )
        let bounds = CGRect(x: 0, y: 0,
                            width: displaySize.width,
                            height: displaySize.height)
        let clipped = raw.intersection(bounds)
        return clipped.isNull ? bounds : clipped
    }

    /// 把缩略图上的落点换算成新的平移量：让「视口框的中心」跟着指针走。
    /// - point: 用户在导航缩略图里点 / 拖到的位置（缩略图坐标系）
    /// - scale / origin: fit() 的结果
    /// - visible: 当前视口框（图片显示坐标系），决定框有多大
    static func panOffset(for point: CGPoint,
                          scale: CGFloat,
                          origin: CGPoint,
                          visible: CGRect,
                          displaySize: CGSize,
                          viewport: CGSize,
                          limit: CGSize) -> CGSize {
        let safeScale = max(0.0001, scale)
        // 先把落点还原到「图片显示坐标系」。
        let imageX = (point.x - origin.x) / safeScale
        let imageY = (point.y - origin.y) / safeScale
        // 让视口框以落点为中心，再反推出需要的 panOffset。
        let targetMinX = imageX - visible.width / 2
        let targetMinY = imageY - visible.height / 2
        let newX = (displaySize.width - viewport.width) / 2 - targetMinX
        let newY = (displaySize.height - viewport.height) / 2 - targetMinY
        return CGSize(width: min(max(newX, -limit.width), limit.width),
                      height: min(max(newY, -limit.height), limit.height))
    }
}
