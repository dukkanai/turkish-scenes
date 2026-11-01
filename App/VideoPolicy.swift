import Foundation

enum VideoPolicy {
    static func valid(videoID: String, start: Double, end: Double) -> Bool {
        videoID.utf8.count == 11 && videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
            && start.isFinite && end.isFinite && start >= 0 && end > start
    }
    static func allows(_ url: URL?, mainFrame: Bool, appHost: String) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        if mainFrame { return host == appHost.lowercased() }
        return host == appHost.lowercased() || host == "www.youtube.com"
            || host == "www.youtube-nocookie.com"
    }
}
