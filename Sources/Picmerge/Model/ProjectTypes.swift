import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 数据模型
//
// 这里只放「数据是什么」，不放任何界面和业务逻辑。
// 初学者可以先从这个文件读起：它定义了整个 app 用到的所有名词。

/// 左侧三个工作区。
enum WorkspaceMode: String, CaseIterable, Identifiable {
    case local = "本地拼接"
    case webpage = "网页长图"
    case split = "单图拆分"

    var id: String { rawValue }

    /// SF Symbols 图标名，SwiftUI 里用 Image(systemName:) 显示。
    var symbol: String {
        switch self {
        case .local: return "photo.on.rectangle.angled"
        case .webpage: return "globe.americas"
        case .split: return "square.split.2x2"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "把多张图片拼成一张"
        case .webpage: return "输入网址，自动截取整页"
        case .split: return "按模板切开再重新合成"
        }
    }
}

/// 本地拼接的三种方式。
enum StitchLayout: String, CaseIterable, Identifiable {
    case vertical = "纵向"
    case horizontal = "横向"
    case template = "模板"

    var id: String { rawValue }
}

/// 预设拼接模板。每个模板都给出「画布里有哪些位置」。
enum StitchTemplate: String, CaseIterable, Identifiable {
    case filmStrip = "胶片长条"
    case twoColumns = "双列网格"
    case collage = "自由拼贴"
    case triptych = "三联画"

    var id: String { rawValue }

    /// 模板说明，直接显示在右侧面板，方便理解每个模板的用途。
    var hint: String {
        switch self {
        case .filmStrip: return "图片自上而下等宽排列，适合截图串讲。"
        case .twoColumns: return "两列交错排布，适合数量较多的图片。"
        case .collage: return "一大四小的杂志式版面。"
        case .triptych: return "中间大、两侧小的三联构图。"
        }
    }
}

/// 单图拆分后重新排布的模板。
enum SplitTemplate: String, CaseIterable, Identifiable {
    case verticalHalves = "左右二等分"
    case horizontalThirds = "上下三等分"
    case fourGrid = "四宫格"
    case nineGrid = "九宫格"

    var id: String { rawValue }

    /// 预设的行列数。选中模板时会写入 AppState.splitColumns / splitRows，
    /// 之后用户可以自由改，模板本身保持不变。
    var columns: Int {
        switch self {
        case .verticalHalves: return 2
        case .horizontalThirds: return 1
        case .fourGrid: return 2
        case .nineGrid: return 3
        }
    }

    var rows: Int {
        switch self {
        case .verticalHalves: return 1
        case .horizontalThirds: return 3
        case .fourGrid: return 2
        case .nineGrid: return 3
        }
    }

    var hint: String {
        switch self {
        case .verticalHalves: return "把原图切成左右两块，并排重新合成。"
        case .horizontalThirds: return "把原图切成上中下三条，纵向重新合成。"
        case .fourGrid: return "切成 2×2 四块，留出间隔后拼成一张。"
        case .nineGrid: return "切成 3×3 九块，留出间隔后拼成一张。"
        }
    }
}

/// 预览的两种显示方式。
enum PreviewMode: String, CaseIterable, Identifiable {
    case fit = "适合窗口"
    case actual = "实际 100%"
    var id: String { rawValue }
}

/// 裁剪框上可以操作的部位。
/// Photoshop 风格裁剪框有 8 个控制点：四角（同时改两条边）、四条边中点
/// （只改一条边），另外还有「框内整体移动」和「框外重新拉框」两种意图。
/// Hashable 让 CropMath 可以用字典保存 8 个手柄的锚点。
enum CropHandle: Hashable {
    case newBox
    case move
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case bottom
    case left
    case right
}

/// 支持的导出格式。把「格式名 / UTType / 编码器 / 扩展名」放在一起，避免散落各处。
enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case bmp = "BMP"
    case tiff = "TIFF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .bmp: return "bmp"
        case .tiff: return "tiff"
        }
    }

    /// NSSavePanel 用它限制可选文件类型。
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .bmp: return UTType(filenameExtension: "bmp") ?? .data
        case .tiff: return .tiff
        }
    }

    /// NSBitmapImageRep 用它真正把像素编码成对应格式。
    var bitmapType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .bmp: return .bmp
        case .tiff: return .tiff
        }
    }

    /// 从保存面板返回的文件扩展名反查格式。
    static func from(pathExtension: String) -> ExportFormat? {
        let ext = pathExtension.lowercased()
        return allCases.first { $0.fileExtension == ext || ($0 == .jpeg && ext == "jpeg") }
    }
}

/// 一张待处理的图片。
///
/// Identifiable 让 SwiftUI 的 ForEach 能稳定识别每一行；
/// offset / scale 在纵向、横向、模板三种拼接方式下都会生效。
struct ImageItem: Identifiable {
    let id = UUID()
    let name: String
    let image: NSImage
    /// 缩放系数，1.0 表示按图片原始位置（或模板槽位）自动适配。
    var scale: CGFloat = 1
    /// 相对自身位置中心的偏移，单位是点（points）。
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    init(image: NSImage, name: String? = nil) {
        self.image = image
        self.name = name ?? "图片"
    }
}

/// 网页截图的阶段。用枚举而不是一堆 Bool，状态就不会互相矛盾。
enum CapturePhase {
    case idle
    case loading
    case success
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
