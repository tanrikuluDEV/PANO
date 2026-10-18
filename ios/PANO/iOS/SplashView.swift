import SwiftUI

/// Opening screen. iOS first shows the system launch screen (navy ground, the logo tile in the middle — set in
/// project.yml); this view takes over with the same image in the same place, brings in the slogan,
/// then scales away to reveal the app while the news keeps loading behind it.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var showText = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Color("SplashBackground")
            Image("SplashLogo")
                .overlay(alignment: .top) {
                    Text("Gündemin panosu").font(.serif(20, .regular))
                        .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
                    .offset(y: 120 + 24)          // just under the 120 pt tile, so the tile itself never moves
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 10)
                }
        }
        // centred on the whole screen, like the system launch screen (not the safe area, which sits lower)
        .ignoresSafeArea()
        .scaleEffect(leaving ? 1.12 : 1)
        .opacity(leaving ? 0 : 1)
        .task {
            withAnimation(.easeOut(duration: 0.45)) { showText = true }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeIn(duration: 0.35)) { leaving = true }
            try? await Task.sleep(nanoseconds: 350_000_000)
            onFinish()
        }
    }
}
