import SwiftUI

@main struct TurkishScenesApp: App {
    @StateObject private var store = AudioProgressStore()
    var body: some Scene {
        WindowGroup {
            AudioLearningView(store: store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
        }
    }
}
