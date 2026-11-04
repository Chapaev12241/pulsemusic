import SwiftUI
import WebKit

@main
struct PulseApp: App {
    var body: some Scene {
        WindowGroup { PulseWebView().ignoresSafeArea(.container, edges: .bottom).preferredColorScheme(.dark) }
    }
}

struct PulseWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        if let url = Bundle.main.url(forResource: "native-bridge", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        config.userContentController.add(context.coordinator, name: "pulse")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.load(URLRequest(url: URL(string: "https://chapaev12241.github.io/pulsemusic/?native=1")!))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var web: WKWebView?
        let player = NativePlayer()
        override init() {
            super.init()
            player.onState = { [weak self] state in
                guard let data = try? JSONSerialization.data(withJSONObject: state),
                      let json = String(data: data, encoding: .utf8) else { return }
                self?.web?.evaluateJavaScript("window.PulseNativeReceive?.(\(json))", completionHandler: nil)
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host == "chapaev12241.github.io",
                  let body = message.body as? [String: Any] else { return }
            player.command(body)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "https", url.host == "chapaev12241.github.io", url.path.hasPrefix("/pulsemusic/") {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if url.scheme == "https" { UIApplication.shared.open(url) }
            }
        }
    }
}
