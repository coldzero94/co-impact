@testable import ImpactIntelligence
import Testing

@Suite struct SuggestionsTests {
    private let notes = """
        Please read the Q3 plan before we meet.
        Bring the signed NDA.
        Zoom: https://zoom.us/j/1
        """

    @Test("Only steps whose quote is in the notes stay, at most two, with quotation marks and spaces trimmed")
    func grounded() {
        let steps = [
            NextStep(text: "Read the Q3 plan", quote: "  “read the Q3 plan”  "),
            NextStep(text: "Bring the budget", quote: "Bring the budget"),
            NextStep(text: "Bring the NDA", quote: "Bring the signed NDA."),
            NextStep(text: "Sign up", quote: "Zoom: https://zoom.us/j/1"),
        ]
        #expect(Suggestions.grounded(steps, in: notes) == [
            NextStep(text: "Read the Q3 plan", quote: "read the Q3 plan"),
            NextStep(text: "Bring the NDA", quote: "Bring the signed NDA."),
        ])
        // No text, or a quote of one word, which justifies nothing, is no step; a repeated step shows once.
        #expect(Suggestions.grounded([NextStep(text: " ", quote: "Bring the signed NDA."),
                                      NextStep(text: "Bring your laptop", quote: "the")], in: notes).isEmpty)
        let twice = NextStep(text: "Bring the NDA", quote: "Bring the signed NDA.")
        #expect(Suggestions.grounded([twice, NextStep(text: "Bring the NDA", quote: "the signed NDA")], in: notes)
                == [twice])
        // Too long to read at a glance: dropped, so the view never cuts a step short.
        let long = String(repeating: "Read the Q3 plan ", count: 8)
        #expect(Suggestions.grounded([NextStep(text: long, quote: "read the Q3 plan")], in: notes).isEmpty)
        let longNotes = String(repeating: "Bring the signed NDA. ", count: 12)
        #expect(Suggestions.grounded([NextStep(text: "Bring the NDA", quote: longNotes)], in: longNotes).isEmpty)
    }

    @Test("Notes are worth asking about only with a few words beyond a link")
    func worthAsking() {
        #expect(Suggestions.worthAsking(notes))
        #expect(!Suggestions.worthAsking("Zoom: https://zoom.us/j/1"))
        #expect(!Suggestions.worthAsking("See you there"))
        #expect(Suggestions.worthAsking("회의 전에 3분기 계획서를 읽어 주세요"))
    }
}
