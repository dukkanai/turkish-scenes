import Foundation

enum PreviewQuestions {
    // Small editorial preview only. Never label the full 1666-block corpus reviewed.
    static let all: [PracticeQuestion] = [
        PracticeQuestion(id:"miracle-cell-7:c0001:w01:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"ذكر؛ رجل، كما وردت في وصف المتحدث.", answer:"erkek", explanation:"erkek = ذكر؛ رجل.",
            choices:["erkek","spiker","Amerika","George"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w02:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"مذيع.", answer:"spiker", explanation:"spiker = مذيع.",
            choices:["spiker","erkek","Birleşik","Amerika"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w03:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"أمريكا؛ الاسم كما ورد في المقطع.", answer:"Amerika", explanation:"Amerika = أمريكا.",
            choices:["Amerika","George","Başkanı","Devletleri"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w04:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"متحد أو موحد، في اسم الولايات المتحدة.", answer:"Birleşik", explanation:"Birleşik من birleşmek: يتحد.",
            choices:["Birleşik","Devletleri","spiker","erkek"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w05:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"الدول، بالصيغة الواردة ضمن اسم الولايات المتحدة.", answer:"Devletleri", explanation:"devlet: دولة؛ -ler للجمع، والصيغة هنا جزء من الاسم المركب.",
            choices:["Devletleri","Birleşik","Başkanı","spiker"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w06:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"رئيسها، بالصيغة الواردة بعد اسم الولايات المتحدة.", answer:"Başkanı", explanation:"başkan: رئيس؛ واللاحقة هنا للإضافة.",
            choices:["Başkanı","Devletleri","Amerika","erkek"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w07:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"جورج؛ الاسم كما ورد.", answer:"George", explanation:"George اسم شخص.",
            choices:["George","Amerika","spiker","Birleşik"]),
        PracticeQuestion(id:"miracle-cell-7:c0001:w08:writing", version:1, segmentID:"miracle-cell-7:c0001",
            prompt:"لبوش أو الخاص ببوش؛ اكتب الاسم مع لاحقة الإضافة كما ورد.", answer:"Bush'un", explanation:"Bush اسم شخص؛ -un للإضافة.",
            choices:["Bush'un","George","Başkanı","Amerika"])
    ]
    static let phrases: [PracticeQuestion] = {
        guard let url = Bundle.main.url(forResource: "reviewed-phrases-1-10", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([PracticeQuestion].self, from: data) else { return [] }
        return values
    }()
    static func forSegment(_ segment: Segment) -> [PracticeQuestion] {
        all.filter { $0.segmentID == segment.id } + ReviewedQuestionBank.questions(for: segment)
            + phrases.filter { $0.segmentID == segment.id }
    }
    static func shuffled(_ questions: [PracticeQuestion]) -> [PracticeQuestion] {
        questions.map { q in
            PracticeQuestion(id:q.id,version:q.version,segmentID:q.segmentID,prompt:q.prompt,
                             answer:q.answer,explanation:q.explanation,choices:q.choices.shuffled(),kind:q.kind)
        }
    }
}
