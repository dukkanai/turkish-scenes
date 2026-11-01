import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var store: ProgressStore
    @State private var confirmDelete = false
    @State private var status: String?
    var body: some View {
        List {
            Section("عن التطبيق") {
                Text("لقطة تركية: تعلم من النصوص والمقاطع مع تدريبات الكتابة والاختيارات.")
                Text("هذه نسخة اختبار؛ نطاق التدريب والملاحظات التحريرية موضحان في شاشة التعلم.")
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                Text("الإصدار \(version)، البناء \(build)")
            }
            Section("الخصوصية والمحتوى") {
                Text("التقدم محفوظ محليًا. لا حسابات ولا مزامنة يوفرها التطبيق؛ قد يشمله النسخ الاحتياطي للنظام.")
                Text("المشغل يتصل بخدمة YouTube ويخضع لسياساتها. لا ينزّل التطبيق ملفات الفيديو للاستخدام دون اتصال.")
                Text("النص مشتق من ملف المصدر المرفق بالمشروع، مع إبقاء الأصل وتوضيح مواضع المراجعة والاستبعاد.")
                Link("فتح مصدر الفيديو في YouTube", destination: URL(string: "https://www.youtube.com/watch?v=5Xv11SlXPBY")!)
            }
            Section("التقدم") {
                Button("حذف التقدم المحفوظ", role: .destructive) { confirmDelete = true }
                    .accessibilityHint("يفتح تأكيدًا قبل الحذف")
                if let status { Text(status) }
                if let error = store.errorMessage { Text(error) }
            }
        }
        .navigationTitle("الإعدادات")
        .confirmationDialog("حذف التقدم نهائيًا؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف التقدم نهائيًا", role: .destructive) {
                if store.deleteAllProgress() {
                    status = "حُذف التقدم المحفوظ من هذا الهاتف."
                    let spoken = NSAttributedString(string: status!, attributes: [.accessibilitySpeechLanguage: "ar-SA"])
                    UIAccessibility.post(notification: .announcement, argument: spoken)
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيُحذف موضع التعلم والإجابات والأخطاء والنسخ السابقة المحفوظة داخل التطبيق. لا يمكن التراجع عن الحذف.")
        }
    }
}
