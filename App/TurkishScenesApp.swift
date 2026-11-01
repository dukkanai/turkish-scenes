import SwiftUI

@main struct TurkishScenesApp: App {
    @StateObject private var store = ProgressStore()
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
        }
    }
}
struct ContentView: View {
    @ObservedObject var store: ProgressStore
    @State private var film: Film?
    @State private var error: String?
    var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if let film {
                        List {
                            Section {
                                Text("نسخة تطوير: المحتوى والتوقيت قيد المراجعة. التدريب التجريبي متاح للمقطع الأول فقط.")
                                    .font(.footnote)
                                if let id = store.progress.lastSegmentID,
                                   let index = film.segments.firstIndex(where: { $0.id == id }) {
                                    NavigationLink("متابعة التعلم") {
                                        SegmentView(film: film, initialIndex: index, store: store)
                                    }
                                }
                                if store.progress.session != nil {
                                    NavigationLink("متابعة التدريب") { PracticeView(store: store) }
                                }
                            }
                            Section(film.title) {
                                ForEach(Array(film.segments.enumerated()), id: \.element.id) { index, segment in
                                    NavigationLink {
                                        SegmentView(film: film, initialIndex: index, store: store)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text("المقطع \(segment.number)").font(.headline)
                                            Text(segment.arabic).lineLimit(2)
                                            if store.progress.visited.contains(segment.id) {
                                                Text("سبق فتحه").font(.caption)
                                            }
                                        }
                                    }
                                    .accessibilityLabel("المقطع رقم \(segment.number). \(segment.arabic)")
                                    .accessibilityHint("اضغط مرتين لفتح النص والفيديو والتدريب")
                                    .accessibilityIdentifier("segment-\(segment.number)")
                                }
                            }
                        }
                    } else if let error {
                        VStack(spacing: 16) {
                            Text(error)
                            Button("إعادة المحاولة", action: load)
                        }.padding()
                    } else { ProgressView("تحميل المحتوى") }
                }
                .navigationTitle("لقطة تركية")
                .task { if film == nil { load() } }
            }.tabItem { Label("التعلم", systemImage: "book") }
            NavigationStack {
                ReviewView(store: store)
            }.tabItem { Label("مراجعة الأخطاء", systemImage: "arrow.counterclockwise") }
            NavigationStack {
                List {
                    Text("المقاطع التي فتحتها: \(store.progress.visited.count)")
                    Text("الأخطاء المفتوحة: \(store.progress.mistakes.values.filter { $0.open }.count)")
                    Text("إجابات أولى مسجلة: \(store.progress.firstAnswers.count)")
                    Text("فتح المقطع لا يعني إتقانه، وتجاوز السؤال لا يعد إجابة صحيحة.")
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                    Section("الخصوصية") {
                        Text("التقدم محفوظ على هذا الهاتف. لا حساب ولا مزامنة. الفيديو يتصل بخدمة YouTube ويتطلب الإنترنت.")
                    }
                }.navigationTitle("تقدمي")
            }.tabItem { Label("تقدمي", systemImage: "chart.bar") }
        }
    }
    private func load() {
        do {
            guard let url = Bundle.main.url(forResource: "film", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            film = try JSONDecoder().decode(Film.self, from: Data(contentsOf: url))
            error = nil
        } catch { self.error = "تعذر فتح محتوى الفيلم. لم تُحذف أي بيانات." }
    }
}
struct SegmentView: View {
    let film: Film
    @ObservedObject var store: ProgressStore
    @State private var index: Int
    @State private var practicing = false
    init(film: Film, initialIndex: Int, store: ProgressStore) {
        self.film = film; self.store = store
        _index = State(initialValue: initialIndex)
    }
    var segment: Segment { film.segments[index] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !practicing && !ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_VIDEO") {
                    YouTubeView(videoID: film.youtubeID, start: Double(segment.startMS)/1000,
                                end: Double(segment.endMS)/1000)
                        .id(segment.id).frame(minHeight: 260)
                }
                Text("استخدم زر تشغيل المقطع أو عناصر مشغل YouTube. يتطلب الفيديو اتصالًا بالإنترنت.")
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
                ForEach(Array(segment.expressions.enumerated()), id: \.offset) { item in Text(item.element) }
                let questions = PreviewQuestions.forSegment(segment.id)
                if !questions.isEmpty {
                    Button("تدريب كتابة المفردات") { start(.writing, questions) }
                        .buttonStyle(.borderedProminent)
                    Button("تدريب الاختيارات") { start(.choice, questions) }
                        .buttonStyle(.bordered)
                } else { Text("بنك أسئلة هذا المقطع لم يُراجع بعد.") }
                HStack {
                    Button("المقطع السابق") { index -= 1; store.visit(segment.id) }
                        .disabled(index == 0)
                    Spacer()
                    Button("المقطع التالي") { index += 1; store.visit(segment.id) }
                        .disabled(index == film.segments.count-1)
                }.buttonStyle(.bordered)
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }.padding()
        }
        .navigationTitle("المقطع \(segment.number)")
        .onAppear { store.visit(segment.id) }
        .navigationDestination(isPresented: $practicing) { PracticeView(store: store) }
    }
    private func start(_ mode: PracticeMode, _ questions: [PracticeQuestion]) {
        if store.begin(mode: mode, questions: PreviewQuestions.shuffled(questions)) { practicing = true }
    }
}
struct ReviewView: View {
    @ObservedObject var store: ProgressStore
    @State private var reviewing = false
    var body: some View {
        let questions = store.progress.mistakes.values.filter { $0.open }
            .sorted { $0.question.id < $1.question.id }.map(\.question)
        List {
            Text("الأخطاء المفتوحة: \(questions.count)")
            Button("بدء مراجعة الأخطاء") {
                if store.begin(mode: .review, questions: questions) { reviewing = true }
            }.disabled(questions.isEmpty)
            Text("يُحل الخطأ بعد إجابة صحيحة في مراجعة مستقلة، ويُعاد فتحه إذا تكرر.")
        }
        .navigationTitle("مراجعة الأخطاء")
        .navigationDestination(isPresented: $reviewing) { PracticeView(store: store) }
    }
}
