import ImpactEngine
import LiveSurfaces

extension LiveCard {
    /// A card's Live Activity (UX.md → System surfaces): its title, answer, and primary action, in its Now phase.
    /// Long text is cut: the layouts show one line, and ActivityKit refuses attributes over 4 KB (120 characters
    /// keeps ordinary text well under it).
    /// shortcut: a character can stack any number of combining marks, so crafted invite text can still pass 4 KB and
    /// lose its Live Activity (logged); cap by UTF-8 bytes if that shows up.
    init?(_ card: ImpactCard) {
        guard let primary = card.primaryAction else { return nil }
        self.init(cardID: card.id, title: String(card.title.prefix(120)), answer: String(card.answer.prefix(120)),
                  symbol: primary.kind.symbol, actionLabel: primary.kind.label, start: card.start,
                  nowPhase: ImpactEngine.nowPhase(of: card))
    }
}

extension HomeModel {
    /// The Live Activities that should be scheduled or running now (`HomeSnapshot.liveActivityCards`).
    var liveCards: [LiveCard] { snapshot.liveActivityCards.compactMap(LiveCard.init) }
}
