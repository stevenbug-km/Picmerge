import SwiftUI
import AppKit

// MARK: - 应用入口
//
// @main 告诉编译器：程序从这里启动。
// SwiftUI 的 App 协议用 body 描述「场景」，WindowGroup 会创建一个真正的 macOS 窗口。
// 整个 App 只在这里创建一个 AppState，其余视图都通过 @EnvironmentObject 共享同一份数据。

@main
struct PicmergeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Picmerge") {
            RootView()
                .environmentObject(state)
                // 给窗口一个合适的初始尺寸，但允许自由缩放。
                // 三栏最小宽度合计约 924，窗口最小宽度留一点余量即可，
                // 不要设太大，否则小屏幕上又会把布局压变形。
                .frame(minWidth: 1000, minHeight: 720)
        }
        .windowResizability(.contentSize)
        .commands {
            // 在「文件」菜单里加入常用快捷键，学习 CommandGroup 的用法。
            CommandGroup(after: .newItem) {
                Button("导入图片…") {
                    NotificationCenter.default.post(name: .picmergeImportImages, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("导出当前结果…") {
                    NotificationCenter.default.post(name: .picmergeExport, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

// 用通知把「菜单命令」传给视图层。
// 这是 SwiftUI 里跨层级通信的一种常见做法：菜单在 Scene 上，按钮在深层 View 里。
extension Notification.Name {
    static let picmergeImportImages = Notification.Name("Picmerge.importImages")
    static let picmergeExport = Notification.Name("Picmerge.export")
}
