<div align="center">
  <img src="Sources/Picmerge/Resources/Assets.xcassets/AppIcon.appiconset/picmerge-icon.png" width="108" alt="Picmerge 图标" />
  <h1>Picmerge</h1>
  <p><strong>一款用 Swift 从零写成的 macOS 原生图片拼接工具</strong></p>
  <p>网页整页长图 · 本地多图拼接 · 单图拆分重组</p>
  <p><a href="https://github.com/stevenbug-km/Picmerge">GitHub 仓库</a> · macOS 13+ · MIT License</p>
</div>

## 简介

Picmerge 是一个基于 **SwiftUI + AppKit + WebKit** 的 macOS 桌面应用，把日常最常遇到的三类图片处理需求收进一个简洁的三栏窗口：

- **网页长图**：给一个网址，自动把整个页面截成一张长图，可调输出比例、裁剪、按 100% 核对细节，再导出成常用格式。
- **本地拼接**：把多张图片按纵向 / 横向 / 模板合成一张，可调间距、留白、圆角、缩放与位移，并支持 Photoshop 风格裁剪框。
- **单图拆分**：把一张图按任意列数、行数切开后重新合成预览；保存时每一块分别导出成独立文件。

这个项目同时也是一份**面向初学者的 Swift 学习材料**：没有把所有逻辑堆在一个文件里，而是按职责拆成若干小文件，关键算法抽成可以脱离界面单独运行自检的纯函数，注释全部使用中文，方便一层一层读下去。

> 本仓库只包含源码，不包含编译好的 `.app`。请按下面的步骤自行构建。

---

## 功能一览

| 工作区 | 能做什么 |
| --- | --- |
| 网页长图 | 输入网址自动截取整页；固定 1280 CSS px 视口；输出比例 100%–30%（每 10% 一档）；8 手柄裁剪框（四角 + 四条边分别拖动，确认后才生效）；「适合窗口」与「实际 100%」两种查看方式；100% 时可按住图片拖动或用右上角导航缩略图快速定位 |
| 本地拼接 | 导入 / 拖入多张图片；缩略图条支持删除与拖动排序；纵向 / 横向 / 模板三种布局；模板样式为带版面缩略图的下拉面板；间距、画布留白、留白颜色、圆角、缩放、水平 / 垂直位移均可拖动滑块或直接输入数字；圆角拉到最大时正方形图变圆形；与网页长图共用同款裁剪 |
| 单图拆分 | 四个预设模板（二等分 / 三等分 / 四宫格 / 九宫格）保持不动，右侧可直接输入 **1–16 的列数和行数**，程序按原图尺寸自动等分；预览始终是合成的一张图；保存时每个切块分别导出，文件名自动追加 `_1`、`_2`… 后缀 |
| 通用 | PNG / JPEG / BMP / TIFF 四种导出格式（默认 PNG）；保存时可自选路径与文件名；macOS 原生分享菜单；底部状态栏实时反馈操作结果 |

### 裁剪框交互

裁剪在两个工作区里共用同一套逻辑，且**拖动过程中不会改动结果图**，只有点击「确定裁剪」才生效：

- 拖框内：整体移动；
- 拖四角：同时调整相邻两条边；
- 拖四条边：只调整被抓住的那一条边，对面边保持不动；
- 拖框外：重新拉一个新框；
- 「取消」放弃本次框选，「清除裁剪」恢复到未裁剪的整张图，连续裁剪会自动做坐标复合。

---

## 快速开始

### 环境要求

- macOS 13.0 或更高版本
- 完整安装的 **Xcode**（构建脚本会调用 `xcrun swiftc`，只有 Command Line Tools 不够）
- 当前一键脚本的目标架构是 Apple Silicon（`arm64`）

### 方式一：用 Xcode 打开（推荐用来读代码、调试）

1. 用 Xcode 打开项目根目录或 `Package.swift`；
2. 选择 **Picmerge** scheme，按 `⌘R` 运行；
3. 想单独验证某个算法，可以直接看 `Model/CropMath.swift`、`Model/NavigatorMath.swift` 这类纯计算文件。

### 方式二：一键构建成可双击运行的 .app

```bash
git clone https://github.com/stevenbug-km/Picmerge.git
cd Picmerge
bash Scripts/build-app.sh
```

脚本会依次完成 7 件事：收集所有 `.swift` 文件 → `xcrun swiftc` 编译 → 用 `iconutil` 生成真正的 macOS 图标 → 写入 `Info.plist` → ad-hoc 签名 → 结束旧进程并安装到 `~/Applications/Picmerge.app` → 刷新图标缓存并启动。

构建完成后终端会打印版本号、图标大小、可执行文件类型和启动状态。应用使用 ad-hoc 签名，仅用于本机运行；如需分发，请自行配置开发者签名与公证。

> 为什么不用 `swift build`？当前命令行环境下 Swift Package Manager 的沙盒会阻止解析依赖，且 SwiftUI 的宏插件在沙盒中加载不稳定，所以日常构建统一走脚本直接调用 `swiftc`。`Package.swift` 保留下来是为了方便在 Xcode 里学习和调试。

---

## 使用说明（简版）

1. **网页长图**：输入网址 → 「开始拼接」→ 用下拉菜单选输出比例 → 需要时点「裁剪」调整 → 切到「实际 100%」核对细节 → 「保存」。
2. **本地拼接**：导入图片 → 在上方缩略图条里拖动排序 / 删除 → 选纵向、横向或模板 → 右侧调间距、留白、圆角、缩放和位移 → 需要时裁剪 → 「保存」。
3. **单图拆分**：选一张图 → 可选用一个预设模板 → 在右侧输入列数、行数 → 预览按新网格自动重算 → 「保存」得到一组 `_1`、`_2`… 编号的切片。

「适合窗口」始终按预览区高度等比显示整图，因此调整输出比例时画面大小看起来不变；右侧检查器与状态栏里的「最终尺寸」才是输出像素，可用于确认比例已生效。

---

## 工程结构

```
Picmerge/
├── Package.swift                    # SwiftPM 描述，方便用 Xcode 打开学习
├── README.md                        # 本文件
├── LICENSE                          # MIT 许可证
├── Scripts/
│   └── build-app.sh                 # 一键编译 / 打包 / 安装 / 启动
└── Sources/Picmerge/
    ├── PicmergeApp.swift             # @main 入口、窗口与菜单
    ├── Model/                       # 数据模型与状态
    │   ├── ProjectTypes.swift       #   枚举、数据结构（先读这个）
    │   ├── AppState.swift           #   ObservableObject 全局状态与流程编排
    │   ├── CropMath.swift           #   裁剪框 8 手柄几何（纯函数，可自检）
    │   └── NavigatorMath.swift      #   100% 导航缩略图坐标换算（纯函数）
    ├── Services/                    # 具体算法，不依赖界面
    │   ├── ImageComposer.swift      #   拼接画布、模板槽位、圆角绘制
    │   ├── ImageProcessor.swift     #   缩放、裁剪、四种格式编码
    │   ├── SplitEngine.swift        #   任意行列拆分与独立切片
    │   └── WebpageCapturer.swift    #   WKWebView 整页截图
    ├── Views/                       # 界面，只负责显示与把手势交回状态
    │   ├── RootView.swift           #   三栏骨架、侧边栏、状态栏
    │   ├── ImageCanvas.swift        #   预览、平移、裁剪框、导航缩略图
    │   ├── LocalWorkspace.swift / WebpageWorkspace.swift / SplitWorkspace.swift
    │   ├── InspectorView.swift      #   右侧参数检查器
    │   ├── ThumbnailStrip.swift     #   缩略图排序与删除
    │   ├── TemplateGallery.swift / SplitTemplateGallery.swift
    │   └── CropToolbar.swift
    └── Resources/Assets.xcassets/   # 应用图标源文件
```

---

## 实现要点

- **像素尺寸可控**：所有输出画布都用 `NSBitmapImageRep` 明确指定尺寸，避免 Retina 屏幕把长图放大成两倍宽。
- **网页整页截图**：`WKWebView` 固定逻辑宽度 1280 CSS px，配合 `WKSnapshotConfiguration.snapshotWidth`，等待图片与字体排版完成后再截取；捕获服务由状态对象强引用，避免异步加载期间被释放。
- **裁剪坐标统一**：草稿框用 SwiftUI 左上原点的归一化坐标，确认时翻转成 AppKit 左下原点，并与上一次裁剪做复合映射，因此连续裁剪不会错位；`ImageProcessor.crop(_:normalizedRect:)` 是唯一的裁剪实现。
- **纯函数便于验证**：裁剪命中判定、导航缩略图坐标换算都抽成不依赖界面的纯函数，可在命令行里直接跑断言，不用靠肉眼点界面。
- **裁剪框贴边也能点中**：8 个手柄统一向框内缩进，装饰图形全部关闭命中测试，命中判定只由父层手势负责，避免框拖到全画面时四角失灵。
- **状态管理**：所有临时交互状态集中在 `AppState` 的 `@Published` 属性里，视图层保持无状态；`rebuildResult()` 是唯一的「重新生成结果图」入口。
- **平移不打断调参**：「实际 100%」下调整右侧参数不会把浏览位置重置回居中，只在切换工作区 / 查看方式 / 清空图片时归零。
- **拆分任意网格**：预设模板只写入初始列数、行数，真正的切图按用户输入的行列数等分；除不尽的像素由相邻块共用取整边界吸收，不丢像素也不重叠。

---

## 已知限制

- 仅支持 macOS，且一键脚本目前只产出 `arm64` 可执行文件。
- 应用为 ad-hoc 签名，未经 Apple 公证，只适合本机构建使用。
- `WKWebView` 对部分需要复杂登录态或有反爬策略的页面可能加载超时（内置约 45 秒超时与失败提示）。
- 单图拆分工作区不提供裁剪（它的交付物是一组切片）。
- 网页长图的输出比例改变的是**输出像素**，不改变「适合窗口」下的预览显示大小。

---

## 参与贡献

欢迎提 Issue 或 Pull Request。这个项目刻意保持「一个文件一件事 + 中文注释」的风格，新增功能时建议：

1. 算法放进 `Services/` 或 `Model/` 里的纯函数；
2. 视图只做显示与事件转发；
3. 改动后运行 `bash Scripts/build-app.sh` 在本机验证。

---

## 许可证

本项目采用 [MIT License](LICENSE)，可自由使用、修改与商用。

---

## English (short)

Picmerge is a native macOS (SwiftUI + AppKit + WebKit) image tool with three workspaces: full-page webpage screenshots, local multi-image stitching, and grid-based single-image splitting. It is written as readable, well-commented Swift for learners: small single-purpose files, pure geometry helpers, and a one-command build script.

```bash
bash Scripts/build-app.sh
```

Requires macOS 13+, a full Xcode installation, and an Apple Silicon Mac. Licensed under MIT.
