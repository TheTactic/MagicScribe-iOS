import SwiftUI

/// Standalone "magic stars" celebration overlay. Not tied to any single screen —
/// reusable anywhere a delight moment is needed (e.g. a future "payment succeeded" state).
struct ConfettiView: View {
    var colors: [Color] = [.magicGold, .magicBlue]
    var symbol: String = "sparkle"
    var particleCount: Int = 16

    @State private var isAnimating = false
    @State private var particles: [Particle] = []

    private struct Particle {
        let angle: Double
        let distance: Double
        let delay: Double
        let scale: Double
        let color: Color
    }

    private func makeParticles() -> [Particle] {
        (0..<particleCount).map { index in
            Particle(
                angle: Double.random(in: 0..<360),
                distance: Double.random(in: 60...160),
                delay: Double.random(in: 0...0.3),
                scale: Double.random(in: 0.6...1.3),
                color: colors[index % colors.count]
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(Array(particles.enumerated()), id: \.offset) { _, particle in
                    let offset = CGPoint(
                        x: CGFloat(cos(particle.angle * .pi / 180) * particle.distance),
                        y: CGFloat(sin(particle.angle * .pi / 180) * particle.distance)
                    )
                    Image(systemName: symbol)
                        .foregroundStyle(particle.color)
                        .scaleEffect(particle.scale)
                        .opacity(isAnimating ? 0 : 1)
                        .position(
                            x: center.x + (isAnimating ? offset.x : 0),
                            y: center.y + (isAnimating ? offset.y : 0)
                        )
                        .animation(
                            .easeOut(duration: 0.9).delay(particle.delay),
                            value: isAnimating
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            particles = makeParticles()
            isAnimating = true
        }
    }
}

#Preview {
    ZStack {
        Color.magicNavy.ignoresSafeArea()
        ConfettiView()
    }
}
