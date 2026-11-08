import ImpactEngine
import Testing

// shortcut: smoke test so CI runs the package tests; roadmap step 4 adds the rule tests.
@Test func engineModuleLinks() {
    #expect(ImpactEngine.self == ImpactEngine.self)
}
