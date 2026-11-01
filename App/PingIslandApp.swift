import SwiftUI

@main
struct PingIslandApp: App {
    @StateObject private var root = RootState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(root)
        }
    }
}

/// 根状态：首次进入走 onboarding，之后进入主界面
final class RootState: ObservableObject {
    @Published var onboardingComplete: Bool {
        didSet {
            SharedStore.defaults?.set(onboardingComplete, forKey: SharedStore.Keys.onboardingComplete)
        }
    }

    init() {
        self.onboardingComplete = SharedStore.defaults?.bool(forKey: SharedStore.Keys.onboardingComplete) ?? false
    }
}
