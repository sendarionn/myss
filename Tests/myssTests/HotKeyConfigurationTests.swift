import Carbon
import XCTest
@testable import myss

final class HotKeyConfigurationTests: XCTestCase {
    func testDefaultHotKeyDoesNotUseSystemMinimizeShortcut() {
        let configuration = HotKeyConfiguration.default

        XCTAssertEqual(configuration.keyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(configuration.modifiers, UInt32(controlKey | optionKey | cmdKey))
        XCTAssertEqual(configuration.displayName, "⌃⌥⌘K")
    }
}
