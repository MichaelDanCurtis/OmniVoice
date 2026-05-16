import SwiftUI
import WebKit
import OmniVoiceCore

struct EngineFrameView: View {
    let theme: OmniVoiceTheme
    let side: EngineFrameSide
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 0) {
            if side == .left {
                collapseHandle
                frameContent
            } else {
                frameContent
                collapseHandle
            }
        }
        .frame(width: isExpanded ? 430 : 38)
        .clipped()
        .animation(.snappy(duration: 0.18), value: isExpanded)
    }

    @ViewBuilder
    private var frameContent: some View {
        if isExpanded {
            EngineDashboardWebView(theme: theme)
                .frame(width: 392)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .themeSurface(theme, cornerRadius: 8, strong: true)
                .padding(.vertical, 12)
        }
    }

    private var collapseHandle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: side == .left ? "sidebar.left" : "sidebar.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(themeColor: theme.accentColor))
                .frame(width: 38)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .themeSurface(theme, cornerRadius: 0, strong: false)
        .help(isExpanded ? "Collapse engine dashboard" : "Expand engine dashboard")
    }
}

struct EngineDashboardWebView: NSViewRepresentable {
    let theme: OmniVoiceTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "http://127.0.0.1:8765/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyTheme(theme, to: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var payload = "{}"

        func applyTheme(_ theme: OmniVoiceTheme, to webView: WKWebView) {
            payload = Self.themePayload(for: theme)
            applyPayload(to: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyPayload(to: webView)
        }

        private func applyPayload(to webView: WKWebView) {
            let script = """
            window.__OMNIVOICE_THEME__ = \(payload);
            window.omniVoiceApplyTheme && window.omniVoiceApplyTheme(window.__OMNIVOICE_THEME__);
            """

            webView.evaluateJavaScript(script)
        }

        private static func themePayload(for theme: OmniVoiceTheme) -> String {
            let payload: [String: Any] = [
                "id": theme.id.rawValue,
                "name": theme.name,
                "css_variables": theme.cssVariables
            ]

            guard
                JSONSerialization.isValidJSONObject(payload),
                let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                let json = String(data: data, encoding: .utf8)
            else {
                return "{}"
            }

            return json
        }
    }
}
