import ImpactEngine
import LiveSurfaces

extension LiveCard {
    /// A card's Live Activity (UX.md → System surfaces): its title, answer, and primary action, in its Now phase.
    init?(_ card: ImpactCard) {
        guard let primary = card.primaryAction else { return nil }
        self.init(cardID: card.id, title: card.title, answer: card.answer, symbol: primary.kind.symbol,
                  actionLabel: primary.kind.label, start: card.start, nowPhase: ImpactEngine.nowPhase(of: card))
    }
}

extension HomeModel {
    /// The Live Activities that should be scheduled or running now (`ImpactEngine.liveActivityCards`).
    var liveCards: [LiveCard] { ImpactEngine.liveActivityCards(in: snapshot, now: now).compactMap(LiveCard.init) }
}
