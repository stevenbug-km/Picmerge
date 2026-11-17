import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 主界面骨架
//
// 采用 macOS 上常见的三栏结构：
//   左侧导航（选工作区） | 中间工作区（工具条 + 画布） | 右侧检查器（调参数）
// 三栏都用 HStack + Divider，尺寸由各自 frame 明确控制，
// 不会像嵌套 GeometryReader 那样把预览区挤窄。

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // 左右两栏用 min=ideal=max 锁死宽度。
            // 之前只用 frame(width:) 时，HStack 在空间不足会压缩它们，
            // 结果文字被挤成竖排、检查器数值被挤没，这就是「界面变形」的原因。
            SidebarView()
                .frame(minWidth: 190, idealWidth: 190, maxWidth: 190)

            Divider()

            VStack(spacing: 0) {
                HeaderView()
                Divider()
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBarView()
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            InspectorView()
                .frame(minWidth: 254, idealWidth: 254, maxWidth: 254)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // 文件选择器：本地拼接和单图拆分共用同一个入口。
        .fileImporter(isPresented: $state.showImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                state.importImages(from: urls)
            }
        }
        // 顶部菜单发出的通知在这里落地。
        .onReceive(NotificationCenter.default.publisher(for: .picmergeImportImages)) { _ in
            state.showImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .picmergeExport)) { _ in
            state.exportCurrentImage()
        }
        // 整个窗口都支持把图片文件拖进来。
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    if let url = object as? URL {
                        Task { @MainActor in state.importImages(from: [url]) }
                    }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch state.mode {
        case .local: LocalWorkspace()
        case .webpage: WebpageWorkspace()
        case .split: SplitWorkspace()
        }
    }
}

// MARK: - 左侧导航

private struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 品牌区
            HStack(spacing: 11) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Picmerge").font(.system(size: 18, weight: .bold))
                    Text("图片拼接工作台").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 28)

            Text("工作区")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    state.mode = mode
                    state.statusMessage = mode.subtitle
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.symbol)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(mode.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(state.mode == mode
                                  ? Color.accentColor.opacity(0.14)
                                  : Color.clear)
                    )
                    .foregroundStyle(state.mode == mode ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("快捷键").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("⌘O 导入图片\n⌘S 导出结果")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - 顶部标题栏

private struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.mode.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                Text(state.mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                state.shareCurrentImage()
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .disabled(state.resultImage == nil)

            Button {
                state.exportCurrentImage()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.resultImage == nil)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }
}

// MARK: - 底部状态栏

private struct StatusBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.resultImage == nil ? Color.secondary.opacity(0.5) : Color.green)
                .frame(width: 7, height: 7)
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(state.resultSizeDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
