import DeckKit
import SwiftUI

/// Routes between the four M3 surfaces and owns the one thing every screen shares: a
/// void background under a landscape-locked layout.
struct RootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            DeckColor.void
                .ignoresSafeArea()

            switch model.route {
            case .onboarding:
                OnboardingView(model: model)
            case .discovery:
                DiscoveryView(model: model)
            case .pin:
                PINEntryView(model: model)
            case .deck:
                DeckShellView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .animation(DeckMotion.stateChange, value: model.route)
        .task {
            // Onboarding starts the browse itself, once its pre-prompt is accepted.
            if model.route != .onboarding {
                model.beginDiscovery()
            }
        }
    }
}
