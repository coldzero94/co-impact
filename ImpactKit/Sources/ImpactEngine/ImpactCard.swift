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
}

public struct ImpactAction: Sendable, Hashable, Identifiable {
    public var id: ActionKind { kind }
    public let kind: ActionKind
    public let provenance: Provenance
}

public enum CardKind: Sendable, Hashable { case onlineMeeting, inPerson, hybrid }

public struct ImpactCard: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let kind: CardKind
    public let facts: [Fact]
    /// First is primary. Selection always produces at least one action.
    public let actions: [ImpactAction]
}
