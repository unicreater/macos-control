import SwiftUI

struct MeshBackgroundView: View {
    let colors: [Color]

    var body: some View {
        if colors.count >= 9 {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: Array(colors.prefix(9))
            )
            .ignoresSafeArea()
        }
    }
}

struct ThemeBackground: ViewModifier {
    func body(content: Content) -> some View {
        if let mesh = ThemeManager.shared.current.meshColors {
            content.background {
                MeshBackgroundView(colors: mesh)
            }
            .toolbarBackground(.hidden, for: .tabBar)
        } else {
            content.background(DeckColor.chassis.ignoresSafeArea())
        }
    }
}

extension View {
    func themeBackground() -> some View {
        modifier(ThemeBackground())
    }
}
