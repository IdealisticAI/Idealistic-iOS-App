import SwiftUI
import WebKit
import SafariServices
import AVFoundation

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct CustomWebView: UIViewRepresentable {
    var url: URL
    @Binding var isLoading: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
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
        
        context.coordinator.webView = webView
        
        // Initial Load
        context.coordinator.lastLoadedURL = url
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If a new URL comes in (like a Deep Link), load it immediately
        if url != context.coordinator.lastLoadedURL {
            context.coordinator.lastLoadedURL = url
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
            uiView.load(request)
        }
        
        // If the user taps "Try again"
        if triggerRefresh {
            DispatchQueue.main.async {
                self.triggerRefresh = false
                self.showError = false
                
                let currentURLToLoad = uiView.url ?? self.url
                let request = URLRequest(url: currentURLToLoad, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                uiView.load(request)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: CustomWebView
        weak var webView: WKWebView?
        var lastLoadedURL: URL?
        let allowedDomain = "idealistic.ai"
        
        init(_ parent: CustomWebView) {
            self.parent = parent
        }
        
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            parent.showError = false
            if let currentURLToLoad = webView?.url ?? parent.url as URL? {
                let request = URLRequest(url: currentURLToLoad, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                webView?.load(request)
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.showError = false
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.showError = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(error)
        }
        
        private func handleError(_ error: Error) {
            let nsError = error as NSError
            
            // Silently ignore navigation cancellations (-999) and interruptions (102)
            if nsError.code == NSURLErrorCancelled || nsError.code == 102 {
                return
            }
            
            parent.isLoading = false
            parent.showError = true
            parent.errorMessage = "Error \(nsError.code): \(nsError.localizedDescription)"
            webView?.scrollView.refreshControl?.endRefreshing()
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
    @State private var errorMessage = ""
    @State private var activeExternalURL: IdentifiableURL? = nil
    @State private var triggerRefresh = false
    
    @State private var currentURL = URL(string: "https://www.idealistic.ai")!
    
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
                
                // WebView is now ALWAYS alive in the background, preventing rebuilds
                CustomWebView(
                    url: currentURL,
                    isLoading: $isLoading,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    activeExternalURL: $activeExternalURL,
                    triggerRefresh: $triggerRefresh
                )
                .ignoresSafeArea(.all, edges: .bottom)
                .opacity(showError ? 0 : 1) // Hides the webview if there's an error, but keeps it active
                
                if isLoading && !showError {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                if showError {
                    VStack(spacing: 20) {
                        Text("Loading error. Please check your connection.")
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        // Diagnostic text to show exactly what broke
                        Text(errorMessage)
                            .foregroundColor(.gray)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        
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
        .onOpenURL { incomingURL in
            if incomingURL.scheme?.lowercased() == "idealistic",
               let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
               var targetUrlString = components.queryItems?.first(where: { $0.name == "url" })?.value {
                
                // FORCE HTTPS: Fix for ATS Error -1022
                if targetUrlString.lowercased().hasPrefix("http://") {
                    targetUrlString = "https://" + targetUrlString.dropFirst(7)
                } else if !targetUrlString.lowercased().hasPrefix("https://") {
                    targetUrlString = "https://" + targetUrlString
                }
                
                if let targetURL = URL(string: targetUrlString) {
                    // 0.8s delay ensures the iOS Networking Daemon is fully awake before requesting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showError = false
                        currentURL = targetURL
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
