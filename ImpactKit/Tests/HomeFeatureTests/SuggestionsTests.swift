import ImpactIntelligence
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
        // No text, or a quote too short to show why, is no step.
        #expect(Suggestions.grounded([NextStep(text: " ", quote: "Bring the signed NDA."),
                                      NextStep(text: "Bring it", quote: "Br")], in: notes).isEmpty)
    }

    @Test("Notes are worth asking about only with a few words beyond a link")
    func worthAsking() {
        #expect(Suggestions.worthAsking(notes))
        #expect(!Suggestions.worthAsking("Zoom: https://zoom.us/j/1"))
        #expect(!Suggestions.worthAsking("See you there"))
        #expect(Suggestions.worthAsking("회의 전에 3분기 계획서를 읽어 주세요"))
    }
}
