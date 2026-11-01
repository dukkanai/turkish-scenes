import Foundation
@main enum VideoPolicyChecks {
 static func main() {
  let host = "dev.nextaura.turkishscenes"
  precondition(VideoPolicy.valid(videoID: "5Xv11SlXPBY", start: 0, end: 10))
  for id in ["';alert(1)//", "5Xv11SlXPBY\n", "", "../secret"] {
   precondition(!VideoPolicy.valid(videoID: id, start: 0, end: 10))
  }
  for pair in [(Double.nan, 10.0), (0, Double.infinity), (-1, 1), (2, 1), (1, 1)] {
   precondition(!VideoPolicy.valid(videoID: "5Xv11SlXPBY", start: pair.0, end: pair.1))
  }
  for raw in ["http://www.youtube.com/embed/x", "javascript:alert(1)", "file:///etc/passwd",
              "https://www.youtube.com.attacker.test/", "https://www.youtube.com@attacker.test/",
              "https://attacker@www.youtube.com/", "https://www.youtube.com:444/"] {
   precondition(!VideoPolicy.allows(URL(string: raw), mainFrame: false, appHost: host))
  }
  precondition(VideoPolicy.allows(URL(string: "https://www.youtube.com/embed/5Xv11SlXPBY"), mainFrame: false, appHost: host))
  precondition(!VideoPolicy.allows(URL(string: "https://www.youtube.com/"), mainFrame: true, appHost: host))
  precondition(VideoPolicy.allows(URL(string: "https://" + host), mainFrame: true, appHost: host))
  precondition(!VideoPolicy.allows(nil, mainFrame: false, appHost: host))
  print("PASS: player parameter and navigation security checks")
 }
}
