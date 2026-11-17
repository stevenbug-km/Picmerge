import Foundation
import AppKit
import WebKit

// MARK: - 网页整页截图
//
// 目标：给出网址后，按网页「正常显示尺寸」截出一张完整长图。
// 关键点（也是之前版本容易出错的地方）：
//   1. 这个对象必须由 AppState 强引用持有，否则异步加载时会被 ARC 释放；
//   2. 固定视口宽度为 1280 CSS 像素，让网页按桌面版正常排版；
//   3. 用 WKSnapshotConfiguration.snapshotWidth 固定输出宽度，
//      避免 Retina 屏幕把截图变成 2 倍像素导致长图异常放大；
//   4. 截图前等待图片、字体和懒加载内容，避免只截到半页或白块。

final class WebpageCapturer: NSObject, WKNavigationDelegate {

    /// 网页渲染的视口宽度，单位是网页的 CSS 像素。
    private let viewportWidth: CGFloat = 1280
    /// 允许的最大页面高度，防止极端页面把内存耗尽。
    private let maxPageHeight: CGFloat = 30000

    private let webView: WKWebView
    private var completion: ((NSImage?, String?) -> Void)?
    private var timeoutItem: DispatchWorkItem?

    override init() {
        let configuration = WKWebViewConfiguration()
        // 用不持久化的数据存储，避免留下缓存和 Cookie。
        configuration.websiteDataStore = .nonPersistent()
        // 让网页认为自己是一个普通的桌面 Safari，减少移动端布局。
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900),
                            configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// 开始加载网页。completion 一定会且只会调用一次。
    func capture(url: URL, completion: @escaping (NSImage?, String?) -> Void) {
        self.completion = completion

        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        webView.load(request)

        // 超时保护：即使网页永远不回调，界面也不会一直转圈。
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.webView.stopLoading()
            self.finish(nil, "网页加载超时，请确认网址可访问或稍后重试。")
        }
        timeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil, "网页加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil, "网页无法打开：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        prepareAndSnapshot()
    }

    // MARK: 截图流程

    private func prepareAndSnapshot() {
        // 先滚动到底部再回到顶部，触发常见的「滚动到才加载」图片。
        let warmUp = """
        (function () {
            var h = Math.max(document.body ? document.body.scrollHeight : 0,
                             document.documentElement ? document.documentElement.scrollHeight : 0);
            window.scrollTo(0, h);
            window.scrollTo(0, 0);
            return h;
        })()
        """
        webView.evaluateJavaScript(warmUp) { [weak self] _, _ in
            guard let self else { return }
            // 给懒加载图片和 Web 字体一点时间完成排版。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.measureAndCapture()
            }
        }
    }

    private func measureAndCapture() {
        let script = """
        (function () {
            var body = document.body, html = document.documentElement;
            var height = Math.max(body ? body.scrollHeight : 0,
                                  body ? body.offsetHeight : 0,
                                  html ? html.scrollHeight : 0,
                                  html ? html.offsetHeight : 0,
                                  html ? html.clientHeight : 0);
            var width = Math.max(body ? body.scrollWidth : 0,
                                 html ? html.scrollWidth : 0,
                                 window.innerWidth || 0);
            return {height: height, width: width};
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.finish(nil, "读取网页尺寸失败：\(error.localizedDescription)")
                return
            }

            let info = result as? [String: Any]
            let reportedHeight = (info?["height"] as? NSNumber)?.doubleValue ?? 900
            let height = min(max(CGFloat(reportedHeight), 900), self.maxPageHeight)

            // 把 WKWebView 自身撑到整页高度，这样 takeSnapshot 才能一次截到全部内容。
            let fullRect = NSRect(x: 0, y: 0, width: self.viewportWidth, height: height)
            self.webView.frame = fullRect
            self.webView.layoutSubtreeIfNeeded()

            // 等 WebKit 按新尺寸重排一帧。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = fullRect
                // 关键：固定输出宽度，截图尺寸就与网页 CSS 尺寸一致。
                configuration.snapshotWidth = NSNumber(value: Double(self.viewportWidth))
                configuration.afterScreenUpdates = true

                self.webView.takeSnapshot(with: configuration) { [weak self] image, error in
                    guard let self else { return }
                    if let error {
                        self.finish(nil, "截图失败：\(error.localizedDescription)")
                    } else if let image {
                        self.finish(self.normalize(image), nil)
                    } else {
                        self.finish(nil, "截图没有返回图片，请重试。")
                    }
                }
            }
        }
    }

    /// 把 WKWebView 返回的 NSImage 重新绘制成「点数 = 像素」的标准图像，
    /// 后续缩放、裁剪、编码才能按确定尺寸工作。
    private func normalize(_ image: NSImage) -> NSImage? {
        CanvasRenderer.render(size: image.size, background: .clear) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func finish(_ image: NSImage?, _ message: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timeoutItem?.cancel()
            self.timeoutItem = nil
            let callback = self.completion
            self.completion = nil
            callback?(image, message)
        }
    }
}
