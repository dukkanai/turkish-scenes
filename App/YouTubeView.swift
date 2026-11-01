import SwiftUI
import WebKit

struct YouTubeView: UIViewRepresentable {
    let videoID: String
    let start: Double
    let end: Double
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let identity = "\(videoID):\(start):\(end)"
        guard context.coordinator.identity != identity,
              videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil,
              start.isFinite, end.isFinite, start >= 0, end > start else { return }
        context.coordinator.identity = identity
        let origin = "https://" + (Bundle.main.bundleIdentifier ?? "dev.nextaura.turkishscenes").lowercased()
        let document = """
        <!doctype html><html lang="ar" dir="rtl"><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>body{margin:0;background:#111;color:white;font:16px -apple-system}#player{width:100%;height:220px}#status{padding:8px}</style>
        </head><body><div id="player"></div><div id="status" role="status">جارٍ تحميل المشغل</div>
        <script>
        var player;
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('player',{width:'100%',height:'220',
            playerVars:{playsinline:1,origin:'\(origin)',controls:1},
            events:{onReady:function(e){
              e.target.cueVideoById({videoId:'\(videoID)',startSeconds:\(start),endSeconds:\(end)});
              document.getElementById('status').textContent='';
            },onError:function(){
              document.getElementById('status').textContent='تعذر تشغيل الفيديو. تحقق من الاتصال أو أعد فتح المقطع.';
            }}
          });
        }
        document.addEventListener('visibilitychange',function(){
          if(document.hidden && player && player.pauseVideo)player.pauseVideo();
        });
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
        view.loadHTMLString(document, baseURL: URL(string: origin))
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.evaluateJavaScript("if(window.player && player.stopVideo){player.stopVideo();}")
        view.stopLoading()
        view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var identity: String?
    }
}
