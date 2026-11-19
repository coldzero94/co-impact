import Foundation
import ImpactEngine
import LiveSurfaces

extension LiveCard {
    /// A card's Live Activity (UX.md → System surfaces): its title, answer, and primary action, in its Now phase; for
    /// the focus block of the running `focus` session, the session.
    /// Long text is cut: the layouts show one line, and ActivityKit refuses attributes over 4 KB (120 characters
    /// keeps ordinary text well under it).
    /// shortcut: a character can stack any number of combining marks, so crafted invite text can still pass 4 KB and
    /// lose its Live Activity (logged); cap by UTF-8 bytes if that shows up.
    init?(_ card: ImpactCard, runToken: String, focus: FocusSession? = nil) {
        guard let primary = card.primaryAction else { return nil }
        self.init(cardID: card.id, title: String(card.title.prefix(120)), answer: String(card.answer.prefix(120)),
                  symbol: primary.kind.symbol, actionLabel: primary.kind.label, start: card.start,
                  nowPhase: ImpactEngine.nowPhase(of: card), runToken: runToken, timeSensitive: card.kind != .focusBlock,
                  focus: focus.flatMap { $0.cardID == card.id ? $0 : nil })
    }

    /// The Live Activities `home` at `now` wants (`HomeSnapshot.liveActivityCards`), their run links carrying
    /// `runToken`, the block of `focus` showing the session while it runs there (`FocusSession.runs`; a stored one
    /// can be stale). Live Home and background refresh build them alike, or each sync ends the other's activities.
    /// shortcut: a session on a block while an earlier focus block is still in its Now phase gets no activity, since
    /// only the first focus block gets one (`liveActivityCards`); Home still shows the session.
    static func wanted(in home: HomeSnapshot, now: Date, runToken: String, focus: FocusSession?) -> [LiveCard] {
        let focus = focus.flatMap { $0.runs(in: home, now: now) ? $0 : nil }
        return home.liveActivityCards.compactMap { LiveCard($0, runToken: runToken, focus: focus) }
    }
}

extension HomeModel {
    /// The Live Activities that should be scheduled or running now (`LiveCard.wanted`).
    func liveCards(runToken: String) -> [LiveCard] {
        LiveCard.wanted(in: snapshot, now: now, runToken: runToken, focus: focus)
    }
}
