import Foundation
import AppKit
import SwiftUI

// MARK: - 全局状态
//
// ObservableObject + @Published 是 SwiftUI 最核心的状态管理方式：
// 属性一变，所有读到它的界面自动刷新。
// 这个类同时负责「协调」各个 Service，本身不写具体算法，方便单独理解每一层。

@MainActor
final class AppState: ObservableObject {

    // MARK: 当前工作区
    @Published var mode: WorkspaceMode = .local {
        didSet {
            // 切换工作区时回到「适合窗口」，避免把上一个工作区的 100% 视图带过来。
            // 同时退出可能还没确认的裁剪草稿，防止裁剪框跑到别的工作区。
            previewMode = .fit
            panOffset = .zero
            panBase = nil
            isCropping = false
            // 两个模板 Popover 都不该跨工作区残留，否则切回来会自己弹出来。
            showTemplateGallery = false
            showSplitGallery = false
            endCropGesture()
            rebuildResult()
        }
    }

    /// 底部状态栏文字，所有操作都会更新它，方便看到程序正在做什么。
    @Published var statusMessage = "准备就绪。选择左侧工作区开始。"

    /// 最终要预览 / 保存 / 分享的那张图。
    /// 用 private(set) 表示：只有状态自己能改，界面只读，数据来源清晰。
    @Published private(set) var resultImage: NSImage?

    // MARK: 工作区一：本地多图拼接
    @Published var localImages: [ImageItem] = [] { didSet { rebuildResult() } }
    @Published var stitchLayout: StitchLayout = .vertical {
        didSet {
            // 「模板样式」下拉只在模板拼接方式下出现，切走时顺手把面板收起来。
            if stitchLayout != .template { showTemplateGallery = false }
            rebuildResult()
        }
    }
    @Published var stitchTemplate: StitchTemplate = .filmStrip { didSet { rebuildResult() } }
    /// 图片之间的间隔（内留白）。
    @Published var stitchGap: CGFloat = 12 { didSet { rebuildResult() } }
    /// 画布四周的外留白，三种拼接方式都生效。
    @Published var stitchPadding: CGFloat = 0 { didSet { rebuildResult() } }
    @Published var cornerRadius: CGFloat = 12 { didSet { rebuildResult() } }
    @Published var canvasColor: Color = .white { didSet { rebuildResult() } }
    @Published var selectedImageID: UUID?
    /// 控制「模板样式」下拉面板是否展开。
    @Published var showTemplateGallery = false

    /// 已确认的本地拼接裁剪框，归一化坐标（原点左下），相对当前合成图。
    @Published var localCrop: CGRect? { didSet { rebuildResult() } }

    /// 间距 / 留白允许的上限。以前只有 60，长图里几乎看不出变化，这里放大到 300。
    let maxSpacing: CGFloat = 300

    /// 圆角上限按「当前图片里最大的短边」动态计算：拖到底时正方形图正好变成圆形，
    /// 长方形图变成胶囊形（几何上能达到的最大圆角）。
    /// 滑块上限就停在「刚好变圆」这个数，不会出现拖到后半段却毫无变化的区间。
    var maxCornerRadius: CGFloat {
        let largestShortSide = localImages
            .map { min($0.image.size.width, $0.image.size.height) }
            .max() ?? 64
        return max(32, largestShortSide / 2)
    }

    /// 控制「拆分样式」下拉面板是否展开。
    @Published var showSplitGallery = false

    // MARK: 预览画布与缩略图条的临时交互状态
    //
    // 说明：当前命令行工具链里 SwiftUI 的 @State 宏插件无法加载，
    // 所以把「只属于界面的临时状态」也统一放进 AppState。
    // 好处是视图层保持无状态，所有数据变化都能在一个类里追踪，学习起来更直观。

    /// 实际 100% 模式下，图片中心相对预览区中心的平移量。
    @Published var panOffset: CGSize = .zero
    /// 一次平移手势开始时的偏移，用来做增量计算，避免拖动时跳变。
    @Published var panBase: CGSize?
    /// 在缩略图条里拖动时的起点 / 落点索引。
    @Published var thumbnailDragSource: Int?
    @Published var thumbnailDragTarget: Int?
    /// 缩略图条量到的可用宽度，用来算一行能放几张。
    @Published var thumbnailStripWidth: CGFloat = 600

    /// 只清掉「一次手势期间」的临时索引。
    ///
    /// 注意：这里**故意不清 panOffset**。以前每次改右侧参数都会把实际 100% 的
    /// 浏览位置打回居中，看起来像「调了参数却回到默认状态」。
    /// 现在只有切换工作区、切换查看方式、清空图片才归零（见各自 didSet）。
    private func clearTransientDragState() {
        panBase = nil
        thumbnailDragSource = nil
        thumbnailDragTarget = nil
    }

    // MARK: 工作区二：网页长图
    @Published var urlString = "https://example.com"
    @Published var capturePhase: CapturePhase = .idle
    @Published var capturedImage: NSImage? { didSet { rebuildResult() } }

    /// 输出比例，1.0 = 100%，0.3 = 30%。
    /// didSet 除了重算图片，还会把「当前尺寸」写进状态栏：
    /// 「适合窗口」预览永远把图片填满预览区高度，光看画面看不出比例变化，
    /// 所以必须用文字明确告诉用户新比例确实已经生效。
    @Published var webScale: Double = 1.0 {
        didSet {
            rebuildResult()
            if mode == .webpage, capturedImage != nil {
                statusMessage = "输出比例 \(Int(webScale * 100))%，最终尺寸 \(resultSizeDescription)。"
            }
        }
    }

    /// 已确认的裁剪框，归一化坐标（原点左下，与 AppKit 一致），始终相对原始网页截图。
    @Published var webCrop: CGRect? { didSet { rebuildResult() } }
    @Published var previewMode: PreviewMode = .fit {
        didSet {
            // 切换查看方式后重新居中，避免把「实际 100%」的平移带进「适合窗口」。
            panOffset = .zero
            panBase = nil
        }
    }
    @Published var isCropping = false

    // MARK: 裁剪框（Photoshop 风格）
    //
    // cropDraft 是「还没点确定」的草稿框，用 SwiftUI 左上原点的归一化坐标，
    // 这样界面绘制和手势计算在同一个坐标系里，不必反复翻转。
    // 只有点击「确定裁剪」才会把它写进 webCrop，拖动过程中预览图完全不变。

    /// 进入裁剪模式时的默认框：四周各留 5%，让用户一眼就能看到框。
    private let defaultCropDraft = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)

    @Published var cropDraft: CGRect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    @Published var cropHandle: CropHandle = .move
    /// 一次拖拽手势的起点与起始框，手势结束后清空。
    @Published var cropGestureStart: CGPoint?
    @Published var cropGestureBase: CGRect?

    /// 可选档位：100% 到 30%，每 10% 一档。
    let scaleOptions: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]

    /// 网页捕获服务必须由状态强引用持有，否则异步加载时会被系统释放。
    private var webpageCapturer: WebpageCapturer?

    // MARK: 工作区三：单图拆分
    //
    // 预设模板保留不动，它只负责「一键套用一组行列数」。
    // 真正决定切几块的是 splitColumns / splitRows：右侧可以直接输入任意值，
    // 预览与「分别保存」都按这两个数自动重新等分，自由度比固定的四个模板更大。
    @Published var splitSourceImage: NSImage? { didSet { rebuildResult() } }
    @Published var splitTemplate: SplitTemplate = .fourGrid {
        didSet { applySplitTemplateGrid() }
    }
    @Published var splitColumns: Int = 2 {
        didSet { if !isApplyingTemplateGrid { rebuildResult() } }
    }
    @Published var splitRows: Int = 2 {
        didSet { if !isApplyingTemplateGrid { rebuildResult() } }
    }
    @Published var splitGap: CGFloat = 14 { didSet { rebuildResult() } }

    /// 行列数允许的范围，右侧输入框与步进器共用。
    let splitGridRange: ClosedRange<Int> = 1...16
    /// 选模板时同时改列和行，用这个标记避免中间态重复重绘整张长图。
    private var isApplyingTemplateGrid = false

    /// 把当前预设模板的行列数写回自定义网格。
    /// 用户改过行列后，也可以点「恢复模板行列」直接调用它。
    func applySplitTemplateGrid() {
        isApplyingTemplateGrid = true
        splitColumns = splitTemplate.columns
        splitRows = splitTemplate.rows
        isApplyingTemplateGrid = false
        rebuildResult()
    }

    /// 右侧数字输入框 / 步进器统一走这里：先收敛到允许范围再写入。
    func setSplitGrid(columns: Int? = nil, rows: Int? = nil) {
        if let columns {
            splitColumns = min(max(columns, splitGridRange.lowerBound), splitGridRange.upperBound)
        }
        if let rows {
            splitRows = min(max(rows, splitGridRange.lowerBound), splitGridRange.upperBound)
        }
    }

    /// 当前网格会切出多少块，界面提示和「分别保存」共用同一个数字。
    var splitPieceCount: Int { splitColumns * splitRows }

    /// 是否仍与所选模板一致；不一致时界面标明「自定义」并提供恢复按钮。
    var splitGridMatchesTemplate: Bool {
        splitColumns == splitTemplate.columns && splitRows == splitTemplate.rows
    }

    /// 右侧显示用的说明：自定义网格时说明程序会如何自动等分。
    var splitGridDescription: String {
        if splitGridMatchesTemplate { return splitTemplate.hint }
        return "自定义 \(splitColumns) 列 × \(splitRows) 行，共 \(splitPieceCount) 块；" +
               "按原图尺寸自动等分，保存时从上到下、从左到右分别导出。"
    }

    /// 每块大约多大（最后一块会吸收除不尽的余数，所以写「约」）。
    var splitPieceSizeDescription: String {
        guard let image = splitSourceImage,
              image.size.width > 0, image.size.height > 0 else { return "—" }
        let width = Int((image.size.width / CGFloat(max(1, splitColumns))).rounded())
        let height = Int((image.size.height / CGFloat(max(1, splitRows))).rounded())
        return "约 \(width) × \(height) px"
    }

    // MARK: 导出与分享
    @Published var exportFormat: ExportFormat = .png
    /// 控制文件选择器是否弹出。
    @Published var showImporter = false
    private var sharingPicker: NSSharingServicePicker?

    init() { rebuildResult() }

    // MARK: - 统一的「重新生成结果图」入口
    //
    // 任何会影响最终图片的参数改变时都调用它一次，
    // 而不是在每个 SwiftUI body 里重复做昂贵的绘图运算。

    func rebuildResult() {
        // 只清手势临时状态，保留「实际 100%」下的平移位置与查看方式。
        clearTransientDragState()

        switch mode {
        case .local:
            // 先合成整张拼接图，再套用本地裁剪（裁剪框相对当前合成图）。
            let composed = ImageComposer.compose(
                items: localImages,
                layout: stitchLayout,
                template: stitchTemplate,
                gap: stitchGap,
                padding: stitchPadding,
                cornerRadius: cornerRadius,
                background: NSColor(canvasColor)
            )
            resultImage = ImageProcessor.crop(composed, normalizedRect: localCrop)

        case .webpage:
            resultImage = ImageProcessor.process(
                source: capturedImage,
                scale: webScale,
                crop: webCrop
            )
        case .split:
            // 用自定义行列数切图，模板只在被选中时提供初始行列。
            resultImage = SplitEngine.compose(
                source: splitSourceImage,
                columns: splitColumns,
                rows: splitRows,
                gap: splitGap,
                background: NSColor(canvasColor)
            )
        }

        // 图片被清空时没有可浏览的内容，这时才把平移归零。
        if resultImage == nil {
            panOffset = .zero
            panBase = nil
        }
    }

    // MARK: - 图片导入

    /// 从文件 URL 导入图片。URL 可能来自文件选择器，也可能来自拖拽。
    func importImages(from urls: [URL]) {
        let loaded = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return ImageItem(image: image, name: url.lastPathComponent)
        }
        guard !loaded.isEmpty else {
            statusMessage = "没有读到可用图片，请确认文件格式。"
            return
        }

        if mode == .split {
            // 拆分工作区只接受一张图，单独处理更直观。
            splitSourceImage = loaded[0].image
            statusMessage = "已载入 \(loaded[0].name)，可选拆分样式，或在右侧直接输入列数、行数。"
        } else {
            localImages.append(contentsOf: loaded)
            selectedImageID = loaded.last?.id
            statusMessage = "已添加 \(loaded.count) 张图片。"
        }
    }

    func selectImage(_ id: UUID) { selectedImageID = id }

    func updateSelectedImage(scale: CGFloat? = nil, x: CGFloat? = nil, y: CGFloat? = nil) {
        guard let index = localImages.firstIndex(where: { $0.id == selectedImageID }) else { return }
        if let scale { localImages[index].scale = scale }
        if let x { localImages[index].offsetX = x }
        if let y { localImages[index].offsetY = y }
        rebuildResult()
    }

    func removeSelectedImage() {
        guard let index = localImages.firstIndex(where: { $0.id == selectedImageID }) else { return }
        localImages.remove(at: index)
        selectedImageID = localImages.last?.id
    }

    func moveSelectedImage(by offset: Int) {
        guard let index = localImages.firstIndex(where: { $0.id == selectedImageID }) else { return }
        let target = index + offset
        guard localImages.indices.contains(target) else { return }
        localImages.swapAt(index, target)
    }

    // MARK: 缩略图条的排序方法
    //
    // 调整顺序统一在预览上方的缩略图条里完成（预览画布只负责看图，
    // 避免拖动浏览和平移手势互相抢事件）。
    // localImages 的 didSet 会自动触发 rebuildResult()，画面立即跟着变。

    /// 按索引移动一张图片。destination 是「拖到哪一个槽位」。
    func moveImage(from source: Int, to destination: Int) {
        guard localImages.indices.contains(source),
              localImages.indices.contains(destination),
              source != destination else { return }

        // 先把源元素拿出来，再插到目标索引。
        // 往前拖、往后拖都用同一个 destination：移除源元素后，
        // 目标槽位之后的元素自动顺延，正好是「拖到哪就占哪个位置」的直觉结果。
        let item = localImages.remove(at: source)
        let finalIndex = min(destination, localImages.count)
        localImages.insert(item, at: finalIndex)
        statusMessage = "已把第 \(source + 1) 张图片移到第 \(finalIndex + 1) 位。"
    }

    /// 缩略图上的删除按钮调用它，删除后自动选中最后一张，右侧参数面板不会空掉。
    func removeImage(id: UUID) {
        guard let index = localImages.firstIndex(where: { $0.id == id }) else { return }
        localImages.remove(at: index)
        if selectedImageID == id { selectedImageID = localImages.last?.id }
        statusMessage = "已删除第 \(index + 1) 张图片。"
    }

    func clearLocalImages() {
        localImages.removeAll()
        selectedImageID = nil
        statusMessage = "已清空图片列表。"
    }

    var selectedImage: ImageItem? {
        localImages.first { $0.id == selectedImageID }
    }

    // MARK: - 网页长图

    func startWebpageCapture() {
        // 允许只输入域名，自动补上 https://。
        var address = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), let host = url.host, !host.isEmpty else {
            capturePhase = .failed("网址无效，例如 https://example.com")
            statusMessage = "请输入有效的网址。"
            return
        }

        capturePhase = .loading
        statusMessage = "正在加载网页并等待图片、字体排版完成…"
        webCrop = nil
        isCropping = false
        previewMode = .fit
        cropDraft = defaultCropDraft
        endCropGesture()

        let capturer = WebpageCapturer()
        webpageCapturer = capturer
        capturer.capture(url: url) { [weak self] image, errorMessage in
            // WKWebView 的回调不一定在主线程，统一切回主线程更新 UI。
            Task { @MainActor in
                guard let self else { return }
                self.webpageCapturer = nil
                if let image {
                    self.capturedImage = image
                    self.capturePhase = .success
                    self.statusMessage = "已生成整页长图，可调整比例、裁剪后保存。"
                } else {
                    let message = errorMessage ?? "网页截图失败，请检查网络。"
                    self.capturePhase = .failed(message)
                    self.statusMessage = message
                }
            }
        }
    }

    // MARK: - 裁剪交互（网页长图与本地拼接共用）
    //
    // 裁剪一律在「适合窗口」模式下进行：整张图完整可见，
    // 拖拽手势也不会被平移手势抢走。
    // 两个工作区各存一个「已确认裁剪框」：webCrop 相对原始网页截图，
    // localCrop 相对当前合成图，互不干扰。

    /// 这个工作区是否支持裁剪（单图拆分的交付物是一组切片，不提供裁剪）。
    var supportsCrop: Bool { mode != .split }

    /// 当前是否有图可裁。
    var canCrop: Bool {
        switch mode {
        case .local: return !localImages.isEmpty
        case .webpage: return capturedImage != nil
        case .split: return false
        }
    }

    /// 当前工作区是否已经裁剪过（按钮据此显示「裁剪」还是「继续裁剪」）。
    var hasCrop: Bool {
        switch mode {
        case .local: return localCrop != nil
        case .webpage: return webCrop != nil
        case .split: return false
        }
    }

    /// 进入 / 退出裁剪模式。进入时显示一个默认裁剪框，但不会改动结果图。
    func toggleCropping() {
        guard canCrop else { return }
        isCropping.toggle()
        endCropGesture()
        if isCropping {
            previewMode = .fit
            cropDraft = defaultCropDraft
            statusMessage = "拖动框内移动、拖四角或四条边缩放（边可分别调整），点「确定裁剪」后生效。"
        } else {
            statusMessage = "已退出裁剪模式。"
        }
    }

    /// 一次拖拽开始时，判断起点落在哪个手柄 / 区域内，决定后续怎么改框。
    /// 8 个手柄的命中规则全部在 CropMath，这里只负责记录状态。
    func beginCropGesture(at start: CGPoint, in size: CGSize) {
        cropGestureStart = start
        cropGestureBase = CropMath.clamped(cropDraft)
        cropHandle = CropMath.handle(at: start, for: displayCropRect(in: size), in: size)
    }

    /// 拖拽过程中更新草稿框。
    /// 四角、四条边、整体移动、重新拉框四种算法都交给 CropMath（纯函数，可自检）。
    func updateCropDraft(to point: CGPoint, in size: CGSize) {
        guard let start = cropGestureStart, let base = cropGestureBase else { return }
        cropDraft = CropMath.updatedRect(base: base,
                                         handle: cropHandle,
                                         start: start,
                                         point: point,
                                         in: size)
    }

    func endCropGesture() {
        cropGestureStart = nil
        cropGestureBase = nil
    }

    /// 草稿框从归一化坐标换算成当前预览图的显示矩形（SwiftUI 左上原点）。
    func displayCropRect(in size: CGSize) -> CGRect {
        CGRect(x: cropDraft.minX * size.width,
               y: cropDraft.minY * size.height,
               width: cropDraft.width * size.width,
               height: cropDraft.height * size.height)
    }

    /// 点击「确定裁剪」后才真正修改结果图。
    /// 草稿框是 SwiftUI 左上原点，先转成 AppKit 左下原点，
    /// 再与已有裁剪做坐标复合，这样连续裁剪也不会定位错误。
    func confirmCrop() {
        guard supportsCrop else { return }
        let draft = CropMath.clamped(cropDraft)
        // 草稿框是 SwiftUI 左上原点，先转成 AppKit 左下原点。
        let appkitRect = CGRect(x: draft.minX,
                                y: 1 - draft.maxY,
                                width: draft.width,
                                height: draft.height)

        switch mode {
        case .webpage:
            webCrop = combineCrop(appkitRect, with: webCrop)
        case .local:
            localCrop = combineCrop(appkitRect, with: localCrop)
        case .split:
            return
        }

        isCropping = false
        endCropGesture()
        statusMessage = "裁剪已生效，最终尺寸 \(resultSizeDescription)。"
    }

    /// 把新框映射回上一次裁剪后的坐标系，连续裁剪也不会定位错误。
    private func combineCrop(_ inner: CGRect, with base: CGRect?) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let parent = base ?? full
        return CGRect(
            x: parent.minX + inner.minX * parent.width,
            y: parent.minY + inner.minY * parent.height,
            width: inner.width * parent.width,
            height: inner.height * parent.height
        )
    }

    /// 放弃本次框选，画面回到裁剪前（之前已确认的裁剪保持不变）。
    func cancelCropping() {
        isCropping = false
        cropDraft = defaultCropDraft
        endCropGesture()
        statusMessage = "已取消本次裁剪，画面恢复到裁剪前。"
    }

    /// 清除当前工作区的所有裁剪，恢复到未裁剪的整张图。
    func clearCrop() {
        switch mode {
        case .webpage: webCrop = nil
        case .local: localCrop = nil
        case .split: return
        }
        isCropping = false
        cropDraft = defaultCropDraft
        endCropGesture()
        statusMessage = "已恢复到裁剪前的整张图片，尺寸 \(resultSizeDescription)。"
    }

    /// 提供给界面显示的尺寸说明。
    var resultSizeDescription: String {
        guard let image = resultImage else { return "暂无图片" }
        return "\(Int(image.size.width)) × \(Int(image.size.height)) px"
    }

    // MARK: - 导出

    func exportCurrentImage() {
        // 单图拆分的交付物是一组图片，走单独的保存流程。
        if mode == .split {
            exportSplitPieces()
            return
        }

        guard let image = resultImage else {
            statusMessage = "还没有可保存的图片。"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = ExportFormat.allCases.map { $0.contentType }
        panel.nameFieldStringValue = defaultFileName
        panel.message = "选择保存位置、输入文件名，并在下方选择图片格式。"
        let (accessory, popup) = makeFormatAccessoryView()
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // runModal 结束后读取下拉框的选择，避免依赖 Objective-C target/action。
        if let title = popup.titleOfSelectedItem,
           let picked = ExportFormat(rawValue: title) {
            exportFormat = picked
        }
        let chosen = exportFormat
        // 统一以面板里选中的格式决定扩展名，不会出现「选了 JPEG 却保存成 png」。
        let destination = url.deletingPathExtension().appendingPathExtension(chosen.fileExtension)

        do {
            try ImageExporter.write(image: image, to: destination, format: chosen)
            statusMessage = "已保存到 \(destination.path)"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 单图拆分：把每个切块分别保存成独立图片，文件名用 _1、_2… 标记。
    /// 用户在保存面板里输入的是「基础文件名」，程序自动追加序号和格式扩展名。
    /// 预览仍然是一张合成图，只有保存时才拆成多个文件。
    private func exportSplitPieces() {
        let pieces = SplitEngine.pieces(source: splitSourceImage,
                                        columns: splitColumns,
                                        rows: splitRows)
        guard !pieces.isEmpty else {
            statusMessage = "还没有可拆分的图片，请先导入一张。"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = ExportFormat.allCases.map { $0.contentType }
        panel.nameFieldStringValue = "Picmerge-拆分图.\(exportFormat.fileExtension)"
        panel.message = "当前 \(splitColumns) 列 × \(splitRows) 行，共 \(pieces.count) 个切块，" +
                        "会分别保存为「基础名_1」「基础名_2」…"
        let (accessory, popup) = makeFormatAccessoryView()
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let title = popup.titleOfSelectedItem,
           let picked = ExportFormat(rawValue: title) {
            exportFormat = picked
        }
        let format = exportFormat

        // 去掉扩展名后作为基础名；序号统一从 1 开始，按阅读顺序（从上到下、从左到右）。
        let baseURL = url.deletingPathExtension()
        let directory = baseURL.deletingLastPathComponent()
        let baseName = baseURL.lastPathComponent

        var savedCount = 0
        for (index, piece) in pieces.enumerated() {
            let fileURL = directory
                .appendingPathComponent("\(baseName)_\(index + 1)")
                .appendingPathExtension(format.fileExtension)
            do {
                try ImageExporter.write(image: piece, to: fileURL, format: format)
                savedCount += 1
            } catch {
                statusMessage = "保存第 \(index + 1) 张时失败：\(error.localizedDescription)"
                return
            }
        }
        statusMessage = "已保存 \(savedCount) 张切片到 \(directory.path)，文件名后缀 _1 至 _\(savedCount)。"
    }

    private var defaultFileName: String {
        let base: String
        switch mode {
        case .local: base = "Picmerge-拼接图"
        case .webpage: base = "Picmerge-网页长图"
        case .split: base = "Picmerge-拆分图"
        }
        return "\(base).\(exportFormat.fileExtension)"
    }

    /// 给 NSSavePanel 加一个格式下拉框。
    /// 这是 AppKit 与 SwiftUI 混合使用的典型例子：保存面板是 AppKit 控件。
    /// 返回值包含下拉框本身，保存面板关闭后可以直接读取用户选择。
    private func makeFormatAccessoryView() -> (NSView, NSPopUpButton) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 44))

        let label = NSTextField(labelWithString: "图片格式：")
        label.frame = NSRect(x: 12, y: 12, width: 76, height: 22)
        container.addSubview(label)

        let popup = NSPopUpButton(frame: NSRect(x: 94, y: 8, width: 220, height: 28))
        popup.addItems(withTitles: ExportFormat.allCases.map { $0.rawValue })
        popup.selectItem(withTitle: exportFormat.rawValue)
        container.addSubview(popup)
        return (container, popup)
    }

    // MARK: - 分享

    /// 调用 macOS 原生分享菜单（信息、邮件、隔空投送等都由系统提供）。
    func shareCurrentImage() {
        guard let image = resultImage else {
            statusMessage = "还没有可分享的图片。"
            return
        }
        guard let anchor = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [image])
        // 必须强引用，否则菜单弹出后 picker 立刻被释放。
        sharingPicker = picker
        picker.show(relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 40,
                                       width: 1, height: 1),
                    of: anchor, preferredEdge: .minY)
        statusMessage = "已打开系统分享菜单。"
    }
}
