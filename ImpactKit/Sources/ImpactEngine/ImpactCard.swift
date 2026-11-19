import Foundation

public enum Provenance: Sendable, Hashable {
    case calendar(field: String)
    case computed(by: String)
    case inferred(by: String)
}

public struct Fact: Sendable, Hashable {
    public let label: String
    public let value: String
    public let provenance: Provenance
}

public enum ActionKind: Sendable, Hashable {
    case joinMeeting(URL)
    case directions(to: Place)
    case openLink(URL)
    case call(String)
    /// Starts an in-app focus session on a focus block (PRODUCT.md → Focus blocks); Home runs it, nothing opens.
    case startFocus
}

public struct ImpactAction: Sendable, Hashable, Identifiable {
    public var id: ActionKind { kind }
    public let kind: ActionKind
    public let provenance: Provenance
}

/// `focusBlock`: an event Impact created with Block time (PRODUCT.md → Focus blocks).
public enum CardKind: Sendable, Hashable { case onlineMeeting, inPerson, hybrid, focusBlock }

public struct ImpactCard: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let kind: CardKind
    public let facts: [Fact]
    /// In display order. Selection always produces at least one calendar or computed action.
    public let actions: [ImpactAction]

    /// The actions shown as buttons: calendar and computed ones. Inferred ones belong in Suggested
    /// (UX.md → Confirmed vs. inferred; AGENTS.md hard rule 2).
    public var confirmedActions: [ImpactAction] {
        actions.filter { if case .inferred = $0.provenance { false } else { true } }
    }

    /// The card's one primary action (UX.md → Simplicity rules): the first confirmed one. Running it once it
    /// counts (`ActionLog.countsFrom`) makes the card done and records its Impact (PRODUCT.md →
    /// Completion semantics); a focus block's Start focus does so through its session (`ActionLog.recordFocus`).
    public var primaryAction: ImpactAction? { confirmedActions.first }
}
