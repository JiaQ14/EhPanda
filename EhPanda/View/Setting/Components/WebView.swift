//
//  WebView.swift
//  EhPanda
//

import WebKit
import SwiftUI

struct WebView: UIViewControllerRepresentable {
    private let url: URL
    private let loginDoneAction: (() -> Void)?

    init(url: URL, loginDoneAction: (() -> Void)? = nil) {
        self.url = url
        self.loginDoneAction = loginDoneAction
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var parent: WebView
        private var didCompleteLogin = false

        init(parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard parent.loginDoneAction != nil, !didCompleteLogin else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }

                DispatchQueue.main.async { [weak self] in
                    guard let self, !didCompleteLogin, CookieUtil.didLogin else { return }
                    didCompleteLogin = true
                    parent.loginDoneAction?()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.error(error)
        }
    }

    func makeCoordinator() -> WebView.Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> EmbeddedWebviewController {
        let webViewController = EmbeddedWebviewController(coordinator: context.coordinator)
        webViewController.loadUrl(url)

        return webViewController
    }

    func updateUIViewController(
        _ uiViewController: EmbeddedWebviewController,
        context: UIViewControllerRepresentableContext<WebView>
    ) {}
}

final class EmbeddedWebviewController: UIViewController {
    private var webview: WKWebView

    init(coordinator: WebView.Coordinator) {
        webview = WKWebView()
        super.init(nibName: nil, bundle: nil)
        webview.navigationDelegate = coordinator
        webview.uiDelegate = coordinator
    }

    required init?(coder: NSCoder) {
        webview = WKWebView()
        super.init(coder: coder)
    }

    func loadUrl(_ url: URL) {
        let request = URLRequest(url: url)
        webview.load(request)
    }

    override func loadView() {
        view = webview
    }
}
