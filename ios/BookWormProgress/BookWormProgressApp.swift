import SwiftUI
import BookWormKit

@main
struct BookWormProgressApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Flushing on foreground is half of the offline story: the
                    // other half is that a queued write survives the app being
                    // killed in between.
                    if phase == .active {
                        Task { await model.onForeground() }
                        model.startLiveRefresh()
                    } else {
                        model.stopLiveRefresh()
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.screen {
        case .launching:
            LaunchView()
        case .signIn(let note):
            SignInView(note: note)
        case .list:
            ReadingListView()
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        // Deliberately quiet: the Keychain read behind this is on another
        // thread and normally takes a frame or two.
        Color(.systemBackground).ignoresSafeArea()
    }
}
