import SwiftUI
import UIKit

struct PracticeView: View {
    @ObservedObject var store: ProgressStore
    var onNextSegment: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @AccessibilityFocusState private var focused: Focus?
    @State private var pendingAdvance: UUID?
    @State private var pendingFocus: UUID?
    enum Focus: Hashable { case question, result }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let session = store.progress.session, let question = session.current {
                    Text("السؤال \(session.index + 1) من \(session.questions.count)")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    LanguageText(text: question.prompt, language: "ar")
                        .accessibilityFocused($focused, equals: .question)
                    let phase = session.phases[question.id, default: .unanswered]
                    if phase == .unanswered {
                        if (session.mode == .choice || question.kind == .phrase), !question.choices.isEmpty {
                            ForEach(question.choices, id: \.self) { choice in
                                Button { answer(choice) } label: {
                                    LanguageText(text: choice, language: "tr-TR")
                                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.bordered)
                            }
                        } else {
                            LanguageText(text: "اكتب الكلمة التركية نفسها الواردة في المقطع، باللواحق نفسها، لا مرادفًا لها.", language: "ar")
                            TextField("اكتب الإجابة التركية", text: $input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .environment(\.layoutDirection, .leftToRight)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { answer(input) }
                            Button("تحقق") { answer(input) }
                                .buttonStyle(.borderedProminent)
                                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(phase == .correct ? "صحيح" : phase == .skipped ? "تم التجاوز" : "الإجابة غير صحيحة")
                                .font(.headline)
                            if phase != .skipped {
                                LanguageText(text: question.answer, language: "tr-TR", style: .headline)
                                LanguageText(text: question.explanation, language: "ar")
                            }
                        }.accessibilityElement(children: .contain)
                            .accessibilityFocused($focused, equals: .result)
                    }
                    HStack {
                        Button("السابق") { cancelAdvance(); store.previous(); input = ""; focusQuestion() }
                            .disabled(session.index == 0)
                        Spacer()
                        Button(phase == .unanswered ? "تجاوز السؤال" : "التالي") { advance() }
                    }.buttonStyle(.bordered)
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                } else if let session = store.progress.session {
                    Text("انتهى التدريب").font(.title).accessibilityAddTraits(.isHeader)
                    Text("الصحيحة: \(session.answers.values.filter { $0.correct }.count)")
                    Text("الخاطئة: \(session.answers.values.filter { !$0.correct }.count)")
                    Text("المتجاوزة: \(session.phases.values.filter { $0 == .skipped }.count)")
                    Button("إعادة هذا التدريب") {
                        cancelAdvance()
                        if store.begin(mode: session.mode, questions: PreviewQuestions.shuffled(session.questions)) {
                            input = ""
                            focusQuestion()
                        }
                    }.buttonStyle(.borderedProminent)
                    Button("العودة") { dismiss() }.buttonStyle(.bordered)
                    if let onNextSegment {
                        Button("الانتقال إلى المقطع التالي", action: onNextSegment).buttonStyle(.bordered)
                    }
                } else {
                    Text("اختر تدريبًا من مقطع الفيلم.")
                }
            }.padding()
        }
        .navigationTitle("التدريب")
        .onAppear { focusQuestion() }
        .onDisappear { cancelAdvance(); pendingFocus = nil; focused = nil }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.announcementDidFinishNotification)) { notification in
            let value = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey]
            let spoken = (value as? String) ?? (value as? NSAttributedString)?.string
            guard pendingAdvance != nil, spoken == "صحيح" else { return }
            advance()
        }
    }
    private func answer(_ value: String) {
        guard let result = store.submit(value) else { return }
        pendingFocus = nil
        focused = .result
        if result.correct {
            let token = UUID()
            pendingAdvance = token
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: NSAttributedString(string: "صحيح", attributes: [.accessibilitySpeechLanguage: "ar-SA"]))
            }
            let delay: UInt64 = UIAccessibility.isVoiceOverRunning ? 6_000_000_000 : 700_000_000
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: delay)
                if pendingAdvance == token { advance() }
            }
        }
    }
    private func focusQuestion() {
        let token = UUID()
        pendingFocus = token
        focused = nil
        Task { @MainActor in
            await Task.yield()
            guard pendingFocus == token else { return }
            pendingFocus = nil
            focused = .question
        }
    }
    private func cancelAdvance() { pendingAdvance = nil }
    private func advance() {
        cancelAdvance()
        store.next()
        input = ""
        focusQuestion()
    }
}
