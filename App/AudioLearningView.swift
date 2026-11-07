import SwiftUI
import AVFoundation

struct AudioLearningView: View {
    @ObservedObject var store: AudioProgressStore
    @StateObject private var tutor: LiveTutor
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionPresented = false
    @State private var pendingLesson: AudioLesson?
    @State private var pendingReview = false
    @State private var replacementConfirmation = false
    init(store: AudioProgressStore) {
        self.store = store
        _tutor = StateObject(wrappedValue: LiveTutor(store: store))
    }
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        Text("تعلّم التركية بالسماع: كلمات وعبارات وقواعد، مع شرح عربي وتدريب صوتي. الصوت والتصحيح بالذكاء الاصطناعي وقد يخطئان.")
                        if let session = store.progress.session, session.phase != .complete {
                            Button("متابعة درسي المحفوظ") { sessionPresented = true }
                                .accessibilityIdentifier("audio-resume")
                        }
                    }
                    Section("المنهج") {
                        ForEach([AudioTrack.word, .phrase, .grammar]) { track in
                            NavigationLink {
                                AudioLessonList(store: store, track: track) { request($0, review: false) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(track.title).font(.headline)
                                    Text("\(store.cards.filter { $0.kind == track }.count) عنصرًا · \(AudioCurriculum.lessons(store.cards, track: track).count) درسًا")
                                        .font(.subheadline)
                                }
                            }.accessibilityIdentifier("audio-track-\(track.rawValue)")
                        }
                    }
                    Section("طريقة التعلم") {
                        Text("خمس كلمات أو خمس عبارات في الدرس، وقاعدة واحدة في درس القواعد. نكرر الأسئلة حتى تجيب عن كل عنصر إجابتين صحيحتين دون تلقين. الخطأ يعيد عدّ هذا العنصر من البداية. هذه سياسة التدريب وليست شهادة إتقان لغوي.")
                        Text("تصفح المنهج والتقدم لا يحتاج مفتاحًا ولا يتصل بالذكاء الاصطناعي. يبدأ الاتصال والميكروفون فقط عند موافقتك على جلسة صوتية.")
                    }
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                }.navigationTitle("تعلّم التركية")
            }.tabItem { Label("الدروس", systemImage: "headphones") }
            NavigationStack {
                List {
                    let due = store.progress.reviewCards(from: store.allCards)
                    Text("للمراجعة الآن: \(due.count)")
                    Text("الأخطاء أولًا، ثم مراجعة اليوم التالي؛ بعد المراجعة الناجحة نعود بعد ثلاثة أيام. لا تُحتسب الإجابة الغامضة خطأ.")
                    Button("ابدأ مراجعة خمسة عناصر") {
                        request(AudioLesson(id: "review-\(UUID().uuidString)", track: .word, number: 0, cards: Array(due.prefix(5))), review: true)
                    }.disabled(due.isEmpty).accessibilityIdentifier("audio-review-start")
                    ForEach(due) { card in
                        VStack(alignment: .leading) {
                            LanguageText(text: card.kind == .grammar ? card.arabic : card.turkish, language: card.kind == .grammar ? "ar" : "tr-TR")
                            Text(store.progress.mastery[card.id]?.openMistake == true ? "خطأ يحتاج مراجعة" : "حان موعد المراجعة")
                        }
                    }
                }.navigationTitle("المراجعة")
            }.tabItem { Label("المراجعة", systemImage: "arrow.counterclockwise") }
            NavigationStack {
                List {
                    Text("قل أثناء الجلسة: أضف كلمة ... إلى كلماتي. ستراجع الكلمة والمعنى والمثال قبل حفظها. لا تُضاف تلقائيًا.")
                    if store.progress.personalCards.isEmpty { Text("لم تضف كلمات شخصية بعد.") }
                    ForEach(AudioCurriculum.lessons(store.allCards, track: .personal)) { lesson in
                        Button("درس كلماتي \(lesson.number) · \(lesson.cards.count) كلمات") { request(lesson, review: false) }
                    }
                    ForEach(store.progress.personalCards) { card in
                        VStack(alignment: .leading) {
                            LanguageText(text: card.turkish, language: "tr-TR")
                            Text(card.arabic)
                        }
                    }
                }.navigationTitle("كلماتي")
            }.tabItem { Label("كلماتي", systemImage: "text.badge.plus") }
            NavigationStack {
                List {
                    Text("دروس مكتملة: \(store.progress.completedLessons.count)")
                    Text("عناصر اجتازت التدريب: \(store.progress.mastery.values.filter { $0.masteredAt != nil }.count)")
                    Text("أخطاء مفتوحة: \(store.progress.mastery.values.filter(\.openMistake).count)")
                    NavigationLink("مفتاح OpenAI والخصوصية") { AudioSettingsView(tutor: tutor) }
                        .accessibilityIdentifier("audio-settings")
                    Text("التقدم محفوظ على هذا الهاتف. لا حساب ولا مزامنة. لا نحفظ التسجيلات الصوتية أو نص إجاباتك. تغيير واجهة التطبيق لم يحذف تقدم تجربة الأفلام القديمة.")
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                }.navigationTitle("تقدمي")
            }.tabItem { Label("تقدمي", systemImage: "chart.bar") }
        }
        .controlSize(.large)
        .sheet(isPresented: $sessionPresented, onDismiss: { tutor.stop() }) {
            NavigationStack { AudioSessionView(store: store, tutor: tutor) }
        }
        .alert("استبدال الدرس الجاري؟", isPresented: $replacementConfirmation) {
            Button("متابعة الدرس الجاري", role: .cancel) { sessionPresented = true; pendingLesson = nil }
            Button("ابدأ الدرس المختار") { beginPending() }
        } message: { Text("سيبقى سجل إجاباتك وأخطائك، لكن ترتيب أسئلة الدرس غير المكتمل سيبدأ من جديد عند العودة إليه.") }
        .onChange(of: scenePhase) { phase in if phase != .active { tutor.stop("توقفت الجلسة عند مغادرة التطبيق. يمكنك استئناف الدرس لاحقًا.") } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in tutor.stop("توقفت الجلسة بسبب مقاطعة صوتية. تقدمك محفوظ.") }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereLostNotification)) { _ in
            tutor.stop("توقفت خدمة الصوت في النظام. توقفت الجلسة؛ حاول مجددًا بعد عودة الصوت.")
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            tutor.stop("أعاد النظام تهيئة خدمة الصوت. توقفت الجلسة؛ أعد فتح التطبيق قبل المحاولة مجددًا.")
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            if let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable {
                tutor.stop("فُصل جهاز الصوت. توقفت الجلسة حتى لا يُشغّل الصوت في مكان غير متوقع.")
            }
        }
    }
    private func request(_ lesson: AudioLesson, review: Bool) {
        pendingLesson = lesson; pendingReview = review
        if let existing = store.progress.session, existing.phase != .complete {
            if existing.lessonID == lesson.id { sessionPresented = true; pendingLesson = nil }
            else { replacementConfirmation = true }
        } else { beginPending() }
    }
    private func beginPending() {
        guard let lesson = pendingLesson else { return }
        tutor.stop()
        if store.change({ $0.begin(lesson, review: pendingReview) }) { sessionPresented = true }
        pendingLesson = nil
    }
}

private struct AudioLessonList: View {
    @ObservedObject var store: AudioProgressStore
    let track: AudioTrack
    let choose: (AudioLesson) -> Void
    var body: some View {
        let lessons = AudioCurriculum.lessons(store.cards, track: track)
        List {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                let unlocked = index == 0 || store.progress.completedLessons.contains(lessons[index - 1].id)
                Section {
                    Button {
                        choose(lesson)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("الدرس \(lesson.number)").font(.headline)
                            LanguageText(text: lesson.cards.map { $0.kind == .grammar ? $0.arabic : $0.turkish }.joined(separator: "، "), language: track == .grammar ? "ar" : "tr-TR")
                            Text(store.progress.completedLessons.contains(lesson.id) ? "مكتمل ويمكن تكراره" : (unlocked ? "متاح" : "أكمل الدرس السابق لفتح التدريب"))
                        }
                    }.disabled(!unlocked).accessibilityIdentifier("audio-lesson-\(lesson.id)")
                    NavigationLink("تصفح محتوى الدرس \(lesson.number)") {
                        List { ForEach(lesson.cards) { card in AudioCardView(card: card) } }
                            .navigationTitle("محتوى الدرس \(lesson.number)")
                    }
                }
            }
        }.navigationTitle(track.title)
    }
}

struct AudioCardView: View {
    let card: AudioCard
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let explanation = card.explanationArabic {
                Text(card.arabic).font(.headline).accessibilityAddTraits(.isHeader)
                LanguageText(text: explanation, language: "ar")
            } else {
                LanguageText(text: card.turkish, language: "tr-TR", style: .headline)
                LanguageText(text: card.arabic, language: "ar")
            }
            LanguageText(text: card.exampleTurkish, language: "tr-TR")
            LanguageText(text: card.exampleArabic, language: "ar")
        }.padding(.vertical, 6).accessibilityElement(children: .contain)
    }
}

private struct AudioSessionView: View {
    @ObservedObject var store: AudioProgressStore
    @ObservedObject var tutor: LiveTutor
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 5
    @State private var consent = false
    var body: some View {
        List {
            Section("حالة الجلسة") {
                Text(tutor.status).accessibilityIdentifier("audio-status")
                    .accessibilityValue(tutor.state == .stopped ? "متوقفة" : tutor.state == .connecting ? "جارٍ الاتصال" : tutor.state == .closing ? "جارٍ الإغلاق" : "متصلة")
                if let session = store.progress.session {
                    Text(session.phase == .teaching ? "الشرح أولًا ثم الاختبار" : session.phase == .quiz ? "متبقٍ للتدريب: \(session.queue.count)" : "اكتمل الدرس. يمكنك العودة إلى الدروس لاختيار التالي.")
                    if session.phase == .quiz, let id = session.currentID, let card = store.allCards.first(where: { $0.id == id }) {
                        LanguageText(text: card.question, language: "ar").accessibilityIdentifier("audio-current-question")
                    }
                }
                if tutor.state == .stopped, store.progress.session?.phase != .complete {
                    Picker("الحد الزمني للجلسة", selection: $minutes) {
                        Text("3 دقائق").tag(3); Text("5 دقائق").tag(5); Text("10 دقائق").tag(10)
                    }
                    Button("بدء جلسة OpenAI الصوتية") { consent = true }
                        .accessibilityIdentifier("audio-paid-start")
                } else if tutor.state != .stopped {
                    Button("إيقاف الجلسة والميكروفون", role: .destructive) { tutor.stop() }
                    if tutor.state == .connected {
                        Button(tutor.muted ? "تشغيل الميكروفون" : "كتم الميكروفون") { tutor.toggleMute() }.disabled(tutor.mutePending)
                        Button("أعد السؤال أو الشرح") { tutor.repeatQuestion() }.disabled(tutor.mutePending)
                        if store.progress.session?.phase == .teaching {
                            Button("ابدأ الاختبار الآن") { tutor.beginQuiz() }.disabled(tutor.mutePending)
                        }
                    }
                }
                if tutor.voiceUsage.seconds > 0 {
                    Text("مدة صوت أبلغت عنها الخدمة: \(Int(tutor.voiceUsage.seconds.rounded(.up))) ثانية. \(tutor.voiceUsage.finalized ? "استخدام نهائي مؤكد." : "استخدام جارٍ أو غير مؤكد نهائيًا.")").font(.footnote)
                }
                if tutor.totalTokens > 0 { Text("وحدات نموذج التقييم الخلفي: \(tutor.totalTokens). تُحاسب منفصلة عن الصوت وليست تقديرًا بالدولار.").font(.footnote) }
            }
            if !tutor.diagnostics.entries.isEmpty {
                Section {
                    DisclosureGroup("تشخيص الجلسة الآمن") {
                        ForEach(tutor.diagnostics.entries) { entry in
                            Text("\(entry.id). \(entry.code.rawValue)").font(.caption).textSelection(.enabled)
                        }
                        Text("رموز تقنية فقط، دون المفتاح أو الصوت أو نص إجابتك. تبقى مؤقتًا في الذاكرة حتى الجلسة التالية ولا تُرفع لأي جهة.").font(.footnote)
                    }
                }
            }
            if !tutor.transcript.isEmpty {
                Section("آخر كلام المعلم") { LanguageText(text: tutor.transcript, language: "ar") }
            }
            if store.progress.session?.phase == .teaching {
                Section("محتوى الدرس") {
                    ForEach(store.allCards.filter { store.progress.session?.cardIDs.contains($0.id) == true }) { AudioCardView(card: $0) }
                }
            }
            if let proposed = tutor.proposedWord {
                Section("راجع الكلمة المقترحة") {
                    AudioCardView(card: proposed)
                    Text("اقتراح مولد آليًا؛ تأكد من المعنى قبل حفظه.")
                    Button("تأكيد وإضافة إلى كلماتي") {
                        if store.addPersonal(proposed) { tutor.proposedWord = nil }
                    }
                    Button("تجاهل الاقتراح", role: .cancel) { tutor.proposedWord = nil }
                }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("درسي الصوتي")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { tutor.stop(); dismiss() } } }
        .alert("بدء جلسة مدفوعة؟", isPresented: $consent) {
            Button("إلغاء", role: .cancel) {}
            Button("أوافق وأبدأ") { Task { await tutor.start(minutes: minutes) } }
        } message: {
            Text("سيُرسل صوتك ومحتوى الدرس إلى OpenAI مباشرة بمفتاحك لاستخدام GPT-Live-1، مع GPT-6-Luna لتقييم الإجابات والأدوات. تُحاسب مدة الصوت وتوكنات الخلفية منفصلتين وفق حسابك. يستمر احتساب مدة الجلسة أثناء الصمت والكتم، وقد توجد مدة بدء محتسبة. لا يشمله اشتراك ChatGPT بالضرورة. نوقف الميكروفون بعد \(minutes) دقائق كحد أقصى أو عند مغادرة التطبيق، وقد ينتظر تأكيد إغلاق الخدمة بضع ثوانٍ. هذا حد زمني وليس سقفًا ماليًا. لا نحفظ التسجيلات أو نص إجاباتك؛ نحتفظ بنتائج التدريب فقط. الإتاحة وجودة الصوت تحتاجان اختبارًا على حسابك وجهازك.")
        }
    }
}

private struct AudioSettingsView: View {
    @ObservedObject var tutor: LiveTutor
    @Environment(\.scenePhase) private var scenePhase
    @State private var key = ""
    @State private var hasKey = false
    @State private var keyReadFailed = false
    @State private var message = ""
    @State private var deleteConfirmation = false
    var body: some View {
        Form {
            Section("مفتاحك الشخصي") {
                Text(keyReadFailed ? "تعذر التحقق من المفتاح المحفوظ" : hasKey ? "يوجد مفتاح محفوظ على هذا الهاتف" : "لم يُحفظ مفتاح")
                if keyReadFailed { Button("إعادة فحص المفتاح المحفوظ") { loadKeyState() } }
                SecureField("أدخل مفتاح OpenAI", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .accessibilityIdentifier("audio-key-input")
                Button(hasKey ? "حفظ واستبدال المفتاح" : "حفظ المفتاح بأمان") {
                    tutor.stop()
                    do { try PersonalAPIKey.save(key); key = ""; hasKey = true; keyReadFailed = false; message = "حُفظ في Keychain لهذا الهاتف فقط. لم يبدأ اتصال مدفوع." }
                    catch PersonalAPIKey.KeyError.invalid { message = "صيغة المفتاح غير صالحة. لم يتغير المفتاح المحفوظ. الرمز: keyFormat" }
                    catch { message = "تعذر الحفظ في Keychain. لم نؤكد حفظ المفتاح. الرمز: keychainWrite" }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("حذف المفتاح المحفوظ", role: .destructive) { deleteConfirmation = true }.disabled(!hasKey)
                Text(message)
            }
            Section("الخصوصية والتكلفة") {
                Text("لا تضع المفتاح في المحادثات أو المستودع. يُحفظ في Keychain دون مزامنة أو نسخة سحابية، ولا يُرسل إلا إلى api.openai.com عند بدء جلسة توافق عليها. المفتاح الشخصي على جهازك له مخاطر إذا اختُرق الجهاز؛ استخدم مفتاح مشروع مخصصًا وحدود إنفاق من حساب OpenAI.")
                Text("يستخدم GPT-Live اتصال WebSocket أصليًا بمفتاحك الشخصي دون خادم وسيط. توصي OpenAI بخادم موثوق عند استخدام مفتاح إنتاج مشترك؛ لا يتضمن التطبيق مفتاحًا مشتركًا. تُحاسب مدة الصوت حتى أثناء الكتم، وتُحاسب توكنات GPT-6-Luna منفصلة. لا نعيد الاتصال تلقائيًا. الصوت والتصحيح قد يخطئان.")
                Link("أسعار OpenAI الحالية", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                Link("بياناتك في واجهة OpenAI", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                Text("مراجعة المنهج نصية آلية، وليست اعتمادًا من متحدث أصلي أو اختبار نطق على جميع الأجهزة.")
            }
        }.navigationTitle("المفتاح والخصوصية")
            .onAppear { loadKeyState() }
            .onDisappear { key = "" }
            .onChange(of: scenePhase) { if $0 != .active { key = "" } }
            .alert("حذف مفتاح OpenAI؟", isPresented: $deleteConfirmation) {
                Button("إلغاء", role: .cancel) {}
                Button("حذف", role: .destructive) {
                    tutor.stop()
                    do { try PersonalAPIKey.delete(); hasKey = false; keyReadFailed = false; key = ""; message = "حُذف المفتاح. تقدم التعلم لم يتغير." }
                    catch { message = "تعذر حذف المفتاح. لم نؤكد الحذف؛ حاول مجددًا. الرمز: keychainDelete" }
                }
            } message: { Text("ستحتاج إلى إدخاله مجددًا قبل جلسة صوتية. لا يحذف هذا تقدّمك.") }
    }
    private func loadKeyState() {
        do {
            hasKey = try PersonalAPIKey.read() != nil
            keyReadFailed = false
        } catch {
            keyReadFailed = true
            message = "تعذر قراءة Keychain. لا يعني ذلك غياب المفتاح. الرمز: keychainRead"
        }
    }

}
