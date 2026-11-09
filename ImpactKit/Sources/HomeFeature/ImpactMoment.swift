import SwiftUI

/// An Impact waiting to be shown: the acted-on card's symbol and its frame on Home when its action ran.
struct Moment {
    let id = UUID()
    /// When it was queued, for Next up's double-tap window: uptime, which clock changes do not move
    /// (not `HomeModel.now`, which is fixed).
    let recorded = ProcessInfo.processInfo.systemUptime
    let symbol: String
    let from: CGRect?
}

/// The Impact moment's motion (UX.md → The Impact moment): the card folds into a token, and the token
/// travels to the Impact ring. Home fills the ring's segment and plays the haptic in `onLanded`.
struct ImpactToken: View {
    let symbol: String
    let from: CGRect
    let to: CGRect
    let onLanded: () -> Void
    @State private var stage = Stage.card

    private enum Stage { case card, token, ring }

    var body: some View {
        let (size, center): (CGSize, CGPoint) = switch stage {
        case .card: (from.size, CGPoint(x: from.midX, y: from.midY))
        case .token: (CGSize(width: 52, height: 52), CGPoint(x: from.midX, y: from.midY))
        case .ring: (CGSize(width: 14, height: 14), CGPoint(x: to.midX, y: to.midY))
        }
        RoundedRectangle(cornerRadius: stage == .card ? 28 : size.height / 2)
            .fill(Color.accentColor)
            .overlay {
                Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .opacity(stage == .token ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3) // stays visible over the accent Next up card
            .position(center)
            .opacity(stage == .ring ? 0.4 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.spring(duration: 0.35)) { stage = .token } completion: {
                    withAnimation(.spring(duration: 0.45)) { stage = .ring } completion: { onLanded() }
                }
            }
    }
}
