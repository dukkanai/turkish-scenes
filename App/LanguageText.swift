import SwiftUI
import UIKit

struct LanguageText: UIViewRepresentable {
    let text: String
    let language: String
    var style: UIFont.TextStyle = .body
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.accessibilityLabel = text
        let speechLanguage = language.hasPrefix("ar") ? "ar-SA" : language
        label.accessibilityLanguage = speechLanguage
        label.accessibilityAttributedLabel = NSAttributedString(string: text,
            attributes: [.accessibilitySpeechLanguage: speechLanguage])
        label.font = .preferredFont(forTextStyle: style)
        label.textColor = .label
        label.textAlignment = language.hasPrefix("ar") ? .right : .left
        label.semanticContentAttribute = language.hasPrefix("ar") ? .forceRightToLeft : .forceLeftToRight
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
