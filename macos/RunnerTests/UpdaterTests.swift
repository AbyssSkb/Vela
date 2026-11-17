import XCTest

@testable import Vela

@MainActor
final class UpdaterTests: XCTestCase {
  func testOnlyPrivateLoopbackFeedsAreAccepted() async {
    let nonce = String(repeating: "a", count: 64)
    XCTAssertNotNil(VelaUpdater.localFeed("http://127.0.0.1:49152/\(nonce)/appcast.xml"))
    for value in [
      "https://example.com:49152/\(nonce)/appcast.xml",
      "http://localhost:49152/\(nonce)/appcast.xml",
      "http://127.0.0.1/\(nonce)/appcast.xml",
      "http://127.0.0.1:0/\(nonce)/appcast.xml",
      "http://127.0.0.1:49152/appcast.xml",
      "http://127.0.0.1:49152/\(nonce)/appcast.xml?feed=external",
      "http://user@127.0.0.1:49152/\(nonce)/appcast.xml",
      "file:///tmp/\(nonce)/appcast.xml",
    ] {
      XCTAssertNil(VelaUpdater.localFeed(value), value)
    }
  }
}
