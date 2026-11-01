import SwiftUI
import WebKit

@MainActor final class PlayerControls: ObservableObject {
    @Published var ready = false
    @Published var playing = false
    @Published var status = "جارٍ تحميل المشغل"
    @Published var reloadID = 0
    weak var webView: WKWebView?
    var videoID = ""
    var start = 0.0
    var end = 0.0
    private var polling = false
    func poll() {
        guard !polling, let webView else { return }
        polling = true
        webView.evaluateJavaScript("""
        (() => {
          const p=window.player;
          return {ready:!!(p && p.getPlayerState), state:p && p.getPlayerState ? p.getPlayerState() : -1,
            time:p && p.getCurrentTime ? p.getCurrentTime() : 0,
            error:document.getElementById('status')?.textContent || ''};
        })()
        """) { [weak self] value, _ in
            guard let self else { return }
            self.polling = false
            guard let data = value as? [String: Any] else { return }
            self.ready = data["ready"] as? Bool ?? false
            let state = (data["state"] as? NSNumber)?.intValue ?? -1
            self.playing = state == 1
            let error = data["error"] as? String ?? ""
            if error.contains("تعذر") { self.status = error }
            else if state == 1 { self.status = "المقطع يعمل" }
            else if state == 2 { self.status = "متوقف مؤقتًا" }
            else if state == 0 { self.status = "انتهى المقطع" }
            else if self.ready { self.status = "جاهز للتشغيل" }
            if state == 1, let time = data["time"] as? Double, time >= self.end {
                self.pause()
                self.status = "انتهى المقطع"
            }
        }
    }
    func toggle() {
        guard ready, VideoPolicy.valid(videoID: videoID, start: start, end: end) else { return }
        if playing { pause() }
        else {
            webView?.evaluateJavaScript("""
            if(window.player){
              const t=player.getCurrentTime();
              if(t>=\(end) || t<\(start)) { \(loadCommand) }
              else { player.playVideo(); }
            }
            """)
        }
    }
    private var loadCommand: String {
        guard VideoPolicy.valid(videoID: videoID, start: start, end: end) else { return "" }
        return "player.loadVideoById({videoId:'\(videoID)',startSeconds:\(start),endSeconds:\(end)});"
    }
    func replay() {
        guard ready else { return }
        webView?.evaluateJavaScript("if(window.player){\(loadCommand)}")
    }
    func pause() {
        webView?.evaluateJavaScript("if(window.player && player.pauseVideo){player.pauseVideo();}")
        playing = false
    }
    func retry() {
        pause()
        ready = false
        status = "جارٍ إعادة تحميل المشغل"
        reloadID += 1
    }
}
struct YouTubeView: View {
    let videoID: String
    let start: Double
    let end: Double
    @StateObject private var controls = PlayerControls()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoWebView(videoID: videoID, start: start, end: end, controls: controls)
                .frame(height: 260)
            Text(controls.status).font(.footnote)
            ViewThatFits(in: .horizontal) {
                HStack { buttons }
                VStack(alignment: .leading) { buttons }
            }
        }
        .task {
            while !Task.isCancelled {
                controls.poll()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onDisappear { controls.pause() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { controls.pause() }
        }
    }
    @ViewBuilder private var buttons: some View {
        Button(controls.playing ? "إيقاف مؤقت" : "تشغيل المقطع") { controls.toggle() }
            .disabled(!controls.ready).frame(minHeight: 44)
        Button("إعادة المقطع من البداية") { controls.replay() }
            .disabled(!controls.ready).frame(minHeight: 44)
        Button("إعادة تحميل المشغل") { controls.retry() }.frame(minHeight: 44)
    }
}
