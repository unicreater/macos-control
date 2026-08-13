import SwiftUI

/// A falling emoji particle.
private struct EmojiParticle: Identifiable {
    let id = UUID()
    let character: String
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let rotation: Double
}

/// Overlay that rains emoji from the top of the screen when triggered.
/// Use the `emojiRain(trigger:)` modifier — each increment of `trigger` spawns a burst.
struct EmojiRainOverlay: View {
    let character: String
    let trigger: Int

    @State private var particles: [EmojiParticle] = []
    @State private var fallen = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Text(p.character)
                        .font(.system(size: p.size))
                        .rotationEffect(.degrees(fallen ? p.rotation : -p.rotation))
                        .offset(
                            x: p.x * geo.size.width - geo.size.width / 2,
                            y: fallen ? geo.size.height + 60 : -60
                        )
                        .opacity(fallen ? 0 : 1)
                        .animation(
                            .easeIn(duration: p.duration).delay(p.delay),
                            value: fallen
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            spawnRain()
        }
    }

    private func spawnRain() {
        fallen = false
        particles = (0..<20).map { _ in
            EmojiParticle(
                character: character,
                x: CGFloat.random(in: 0.05...0.95),
                size: CGFloat.random(in: 22...40),
                duration: Double.random(in: 0.9...1.8),
                delay: Double.random(in: 0...0.5),
                rotation: Double.random(in: -35...35)
            )
        }
        // Next frame: start the fall so SwiftUI sees the state change.
        DispatchQueue.main.async {
            withAnimation {
                fallen = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            particles = []
            fallen = false
        }
    }
}
