import XCTest

@testable import Vela

@MainActor
final class UpdaterTests: XCTestCase {
  func testQuitDuringExtractionCancelsWithoutInstalling() async {
    let updater = VelaUpdater()
    updater.showDownloadDidStartExtractingUpdate()
    var terminated = false
    updater.prepareToTerminate { terminated = true }
    XCTAssertFalse(terminated)

    let choice = await updater.showReadyToInstallAndRelaunch()
    XCTAssertEqual(choice, .skip)
    XCTAssertFalse(terminated)
    updater.dismissUpdateInstallation()
    XCTAssertTrue(terminated)
  }

  func testQuitWaitsForDownloadCancellation() async {
    let updater = VelaUpdater()
    var cancelled = false
    var terminated = false
    updater.showDownloadInitiated { cancelled = true }
    updater.prepareToTerminate { terminated = true }
    XCTAssertTrue(cancelled)
    XCTAssertFalse(terminated)
    updater.dismissUpdateInstallation()
    XCTAssertTrue(terminated)
  }

  func testQuitWithoutAnUpdateDoesNotWait() async {
    let updater = VelaUpdater()
    var terminated = false
    updater.prepareToTerminate { terminated = true }
    XCTAssertTrue(terminated)
  }
}
