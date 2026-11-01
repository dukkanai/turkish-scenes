import SwiftUI

@main
struct TurkishScenesApp: App {
    var body: some Scene {
        WindowGroup { ContentView().environment(\.layoutDirection, .rightToLeft) }
    }
}
struct ContentView: View {
    @State private var film: Film?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let film {
                    List {
                        Section {
                            Text("نسخة تطوير: المحتوى والتوقيت قيد المراجعة، والتدريب لم يُجهّز بعد.")
                                .font(.footnote)
                        }
                        Section(film.title) {
                            ForEach(film.segments) { segment in
                                NavigationLink {
                                    SegmentView(segment: segment, videoID: film.youtubeID)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text("المقطع \(segment.number)").font(.headline)
                                        Text(segment.arabic).lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                } else if let error {
                    VStack(spacing: 16) {
                        Text(error)
                        Button("إعادة المحاولة", action: load)
                    }.padding()
                } else {
                    ProgressView("تحميل المحتوى")
                }
            }
            .navigationTitle("لقطة تركية")
            .task { load() }
        }
    }
    private func load() {
        do {
            guard let url = Bundle.main.url(forResource: "film", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            film = try JSONDecoder().decode(Film.self, from: Data(contentsOf: url))
            error = nil
        } catch {
            self.error = "تعذر فتح محتوى الفيلم. لم تُحذف أي بيانات."
        }
    }
}
struct SegmentView: View {
    let segment: Segment
    let videoID: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                YouTubeView(videoID: videoID, start: Double(segment.startMS)/1000,
                            end: Double(segment.endMS)/1000)
                    .frame(minHeight: 220)
                Text("اضغط تشغيل داخل المشغل. يتطلب الفيديو اتصالًا بالإنترنت.")
                    .font(.footnote)
                LanguageText(text: segment.turkish, language: "tr-TR")
                LanguageText(text: segment.arabic, language: "ar")
                Text("الكلمات بالترتيب").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(segment.words) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        LanguageText(text: word.text, language: "tr-TR", style: .headline)
                        LanguageText(text: word.explanation, language: "ar")
                    }.accessibilityElement(children: .contain)
                }
                ForEach(Array(segment.expressions.enumerated()), id: \.offset) { item in
                    Text(item.element)
                }
            }.padding()
        }.navigationTitle("المقطع \(segment.number)")
    }
}
