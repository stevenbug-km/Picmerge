import SwiftUI
import AppKit

// MARK: - 已导入图片缩略图条
//
// 放在本地拼接预览画布的上方：
//   * 缩略图从左到右顺排，一行放不下自动折到第二行（超过两行可上下滚动）；
//   * 每张右上角有删除按钮，左下角有序号，与右侧图层列表顺序一致；
//   * 按住缩略图拖动到另一张上，就能改变下方预览里的拼接顺序。
//
// 为什么不用系统 Drag&Drop：这里自己算每个格子的位置，
// 用「命名坐标系」把拖动位置换算成格子序号，逻辑集中、容易读懂，
// 也不会出现拖拽 Payload 类型匹配不到的问题。

struct ThumbnailStrip: View {
    @EnvironmentObject private var state: AppState

    /// 单个缩略图边长与格间距。
    private let cell: CGFloat = 68
    private let spacing: CGFloat = 9
    /// 最多露出两排，更多图片通过滚动查看，避免把预览区挤没了。
    private let maxVisibleRows = 2

    /// 可用宽度、拖拽索引都放在 AppState（本项目避免使用 @State 宏）。
    /// 命名坐标系的名字，拖动手势和格子位置都用它。
    private let coordinateSpace = "PicmergeThumbnailGrid"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：数量 + 操作提示 + 清空按钮。
            HStack(spacing: 8) {
                Text("已导入 \(state.localImages.count) 张")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                Text("拖动缩略图可调整拼接顺序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(role: .destructive) {
                    state.clearLocalImages()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    ForEach(state.localImages.indices, id: \.self) { index in
                        let item = state.localImages[index]
                        ThumbnailCell(item: item,
                                      index: index,
                                      size: cell,
                                      isSelected: state.selectedImageID == item.id,
                                      isSource: state.thumbnailDragSource == index,
                                      isTarget: state.thumbnailDragTarget == index) {
                            state.removeImage(id: item.id)
                        }
                        .frame(width: cell, height: cell)
                        .position(cellCenter(for: index))
                        .onTapGesture { state.selectImage(item.id) }
                        .gesture(reorderGesture(for: index))
                    }
                }
                // 显式撑满内容区，命名坐标系才有稳定原点。
                .frame(width: max(1, state.thumbnailStripWidth),
                       height: contentHeight,
                       alignment: .topLeading)
                .coordinateSpace(name: coordinateSpace)
            }
            .frame(height: visibleHeight)
        }
        // 背景里的 GeometryReader 只负责量宽度，不参与布局、不会撑大父容器。
        .background(widthMeasurer)
    }

    /// 量宽度的辅助视图：宽度变化时更新状态，列数会跟着重算。
    private var widthMeasurer: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { state.thumbnailStripWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { newValue in
                    state.thumbnailStripWidth = newValue
                }
        }
    }

    // MARK: 网格计算

    private var columns: Int {
        max(1, Int((state.thumbnailStripWidth + spacing) / (cell + spacing)))
    }

    private var rows: Int {
        max(1, (state.localImages.count + columns - 1) / columns)
    }

    private var visibleRows: Int {
        min(rows, maxVisibleRows)
    }

    /// 所有行的总高度（ScrollView 内容高度）。
    private var contentHeight: CGFloat {
        CGFloat(rows) * cell + CGFloat(max(0, rows - 1)) * spacing
    }

    /// 只露出一行或两行的高度。
    private var visibleHeight: CGFloat {
        CGFloat(visibleRows) * cell + CGFloat(max(0, visibleRows - 1)) * spacing
    }

    private func cellCenter(for index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns
        return CGPoint(x: CGFloat(column) * (cell + spacing) + cell / 2,
                       y: CGFloat(row) * (cell + spacing) + cell / 2)
    }

    /// 把一个点换算成格子序号；落在间隙里时归到最近的格子。
    private func cellIndex(at point: CGPoint) -> Int? {
        guard !state.localImages.isEmpty else { return nil }
        let column = Int(point.x / (cell + spacing))
        let row = Int(point.y / (cell + spacing))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        let index = row * columns + column
        return index < state.localImages.count ? index : nil
    }

    /// 每格自己的拖动手势：用命名坐标系，所以拖出格子后仍能算出落点。
    private func reorderGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if state.thumbnailDragSource == nil {
                    state.thumbnailDragSource = index
                }
                state.thumbnailDragTarget = cellIndex(at: value.location)
            }
            .onEnded { _ in
                if let source = state.thumbnailDragSource,
                   let target = state.thumbnailDragTarget,
                   source != target {
                    state.moveImage(from: source, to: target)
                }
                state.thumbnailDragSource = nil
                state.thumbnailDragTarget = nil
            }
    }
}

// MARK: - 单张缩略图

private struct ThumbnailCell: View {
    let item: ImageItem
    let index: Int
    let size: CGFloat
    let isSelected: Bool
    let isSource: Bool
    let isTarget: Bool
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isSelected || isTarget ? 2.5 : 1)
                )
                .opacity(isSource ? 0.55 : 1)
                // 左下角序号，方便和右侧图层列表对照。
                .overlay(alignment: .bottomLeading) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(4)
                }

            // 删除按钮：白叉 + 红底圆，点击只删这一张。
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.red)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .padding(3)
            .help("删除这张图片")
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }

    private var borderColor: Color {
        if isTarget { return Color.green }
        if isSelected { return Color.accentColor }
        return Color.secondary.opacity(0.25)
    }
}
