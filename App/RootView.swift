import SwiftUI

struct RootView: View {
    @EnvironmentObject private var root: RootState

    var body: some View {
        Group {
            if root.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView(onComplete: { root.onboardingComplete = true })
            }
        }
    }
}

/// MVP 主界面：角色主页 / 日记 / 收藏 / 设置
struct MainTabView: View {
    var body: some View {
        TabView {
            CharacterHomeView()
                .tabItem { Label("角色", systemImage: "person.fill") }
            DiaryView()
                .tabItem { Label("日记", systemImage: "book.fill") }
            CollectionView()
                .tabItem { Label("收藏", systemImage: "shippingbox.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
