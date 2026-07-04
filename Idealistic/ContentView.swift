import SwiftUI
import WebKit
import SafariServices
import AVFoundation

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct CustomWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var showError: Bool
    @Binding var activeExternalURL: IdentifiableURL?
    @Binding var triggerRefresh: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.allowsBackForwardNavigationGestures = true
        
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        webView.load(request)
        
        context.coordinator.webView = webView
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if triggerRefresh {
            DispatchQueue.main.async {
                if showError {
                    let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
                    uiView.load(request)
                } else {
                    uiView.reload()
                }
                triggerRefresh = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: CustomWebView
        weak var webView: WKWebView?
        let allowedDomain = "idealistic.ai"
        
        init(_ parent: CustomWebView) {
            self.parent = parent
        }
        
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            if parent.showError {
                let request = URLRequest(url: parent.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
                webView?.load(request)
            } else {
                webView?.reload()
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.showError = false
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.showError = true
            webView.scrollView.refreshControl?.endRefreshing()
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            
            if urlString.contains("action=external_checkout") {
                let cleanUrlString = urlString.replacingOccurrences(of: "?action=external_checkout", with: "")
                if let cleanUrl = URL(string: cleanUrlString) {
                    UIApplication.shared.open(cleanUrl)
                }
                decisionHandler(.cancel)
                return
            }
            
            if let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            
            if let host = url.host, host.hasSuffix(allowedDomain) {
                decisionHandler(.allow)
            } else {
                DispatchQueue.main.async {
                    self.parent.activeExternalURL = IdentifiableURL(url: url)
                }
                decisionHandler(.cancel)
            }
        }
        
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            if type == .microphone || type == .cameraAndMicrophone {
                if #available(iOS 17.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async {
                            decisionHandler(granted ? .grant : .deny)
                        }
                    }
                } else {
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        DispatchQueue.main.async {
                            decisionHandler(granted ? .grant : .deny)
                        }
                    }
                }
            } else {
                decisionHandler(.prompt)
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ContentView: View {
    @State private var isLoading = true
    @State private var showError = false
    @State private var activeExternalURL: IdentifiableURL? = nil
    @State private var triggerRefresh = false
    
    let baseURL = URL(string: "https://www.idealistic.ai")!
    
    var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isPreview {
                Text("WKWebView is not supported in Preview.\nPress Cmd + R for the Simulator.")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            } else {
                if !showError {
                    CustomWebView(
                        url: baseURL,
                        isLoading: $isLoading,
                        showError: $showError,
                        activeExternalURL: $activeExternalURL,
                        triggerRefresh: $triggerRefresh
                    )
                    .ignoresSafeArea(.all, edges: .bottom)
                }
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                if showError {
                    VStack(spacing: 20) {
                        Text("Loading error. Please check your connection.")
                            .foregroundColor(.white)
                            .font(.body)
                        
                        Button(action: {
                            triggerRefresh = true
                        }) {
                            Text("Try again")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.2))
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
        }
        .sheet(item: $activeExternalURL) { identifiable in
            SafariView(url: identifiable.url)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView()
}
