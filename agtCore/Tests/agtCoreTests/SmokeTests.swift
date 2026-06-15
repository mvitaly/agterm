import Testing
@testable import agtCore

@Test func packageBuildsAndImports() {
    #expect(!AgtCore.version.isEmpty)
}
