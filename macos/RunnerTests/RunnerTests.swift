import Carbon
import Cocoa
import FlutterMacOS
import XCTest

@testable import Vela

class RunnerTests: XCTestCase {

  func testIdleStatusMenuStartsWithActions() {
    let app = AppDelegate()
    app.setMenuLanguage("en")
    let menu = NSMenu()

    app.menuNeedsUpdate(menu)

    XCTAssertEqual(menu.items.map(\.title), ["Open received folder", "Open Vela", "Quit Vela"])
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

  func testPairedDevicesAppearUnderRequestsAndClearOnNodeRestart() {
    let app = AppDelegate()
    app.setMenuLanguage("en")
    let menu = NSMenu()
    app.setMenuDevices([
      ["name": "Phone", "presence": "reachable", "label": "Reachable"],
      ["name": "Tablet", "presence": "unavailable", "label": "Temporarily unreachable"],
      ["name": "Laptop", "presence": "unknown", "label": "Checking"],
    ])
    app.menuNeedsUpdate(menu)
    XCTAssertEqual(Array(menu.items.prefix(3).map(\.title)), ["Phone", "Tablet", "Laptop"])
    XCTAssertEqual(menu.items.first?.accessibilityLabel(), "Phone, Reachable")
    XCTAssertTrue(menu.items.prefix(3).allSatisfy { $0.image != nil && $0.action == nil })
    XCTAssertTrue(menu.items[3].isSeparatorItem)
    app.setMenuOffer(["id": "request", "title": "Incoming file"]) { _, _ in }
    app.menuNeedsUpdate(menu)
    XCTAssertEqual(menu.items.first?.title, "Incoming file")
    app.setIncoming(false)
    app.setNodeStatus("starting")
    app.menuNeedsUpdate(menu)
    XCTAssertEqual(menu.items.first?.title, "Open received folder")
  }

  func testMenuOfferOnlyDecidesTheCurrentRequestOnce() throws {
    let app = AppDelegate()
    let menu = NSMenu()
    var decisions: [String] = []
    app.setMenuOffer(["id": "old"]) { _, _ in XCTFail("Decided a stale request") }
    app.menuNeedsUpdate(menu)
    let stale = try XCTUnwrap(menu.items.first { $0.representedObject as? String == "old" && $0.tag == 1 })
    app.setMenuOffer(["id": "current"]) { id, accepted in
      if accepted { decisions.append(id) }
    }
    app.menuNeedsUpdate(menu)
    let accept = try XCTUnwrap(menu.items.first { $0.representedObject as? String == "current" && $0.tag == 1 })
    XCTAssertTrue(accept.isEnabled)
    XCTAssertFalse(menu.items[0].isEnabled)
    for item in [stale, accept, accept] {
      let action = try XCTUnwrap(item.action)
      XCTAssertTrue(NSApplication.shared.sendAction(action, to: app, from: item))
    }
    XCTAssertEqual(decisions, ["current"])
  }

  func testMenuStatusPrioritizesNotificationsAndRestoresNodeState() {
    let app = AppDelegate()
    XCTAssertEqual(app.menuStatus, "starting")
    XCTAssertEqual(app.menuStatusColor, .systemGray)
    app.setNodeStatus("ready")
    XCTAssertEqual(app.menuStatusColor, .systemGreen)
    app.setTransferring(true)
    XCTAssertEqual(app.menuStatus, "transferring")
    XCTAssertEqual(app.menuStatusColor, .systemBlue)
    app.setIncoming(true)
    XCTAssertEqual(app.menuStatus, "notification")
    XCTAssertEqual(app.menuStatusColor, .systemOrange)
    app.setNodeStatus("failed")
    app.setIncoming(false)
    XCTAssertEqual(app.menuStatus, "transferring")
    app.setTransferring(false)
    XCTAssertEqual(app.menuStatus, "failed")
    XCTAssertEqual(app.menuStatusColor, .systemRed)
    app.setNodeStatus("unexpected")
    XCTAssertEqual(app.menuStatus, "failed")
  }

  func testBackgroundActivityStartsOnceAndStops() {
    let app = AppDelegate()
    defer { app.setBackgroundActive(false) }
    XCTAssertFalse(app.backgroundActive)
    app.setBackgroundActive(true)
    app.setBackgroundActive(true)
    XCTAssertTrue(app.backgroundActive)
    app.setBackgroundActive(false)
    app.setBackgroundActive(false)
    XCTAssertFalse(app.backgroundActive)
  }

  func testBackgroundCompletionLastsUntilTheWindowOpensOrAnotherTransferStarts() {
    let app = AppDelegate()
    app.setNodeStatus("ready")
    app.setTransferring(true)
    app.finishTransfer(inBackground: true)
    XCTAssertEqual(app.menuStatus, "completed")
    XCTAssertEqual(app.menuStatusColor, .systemPurple)
    app.clearTransferCompletion()
    XCTAssertEqual(app.menuStatus, "ready")
    app.finishTransfer(inBackground: true)
    app.setTransferring(true)
    XCTAssertEqual(app.menuStatus, "transferring")
    app.finishTransfer(inBackground: false)
    XCTAssertEqual(app.menuStatus, "ready")
  }

  func testOnlyLoginLaunchEventIsRecognized() {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    XCTAssertFalse(AppDelegate.isLoginLaunch(nil))
    XCTAssertFalse(AppDelegate.isLoginLaunch(event))
    event.setParam(
      NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
    XCTAssertTrue(AppDelegate.isLoginLaunch(event))
  }

  func testShareManifestReturnsNativePathsForCurrentAndLegacyManifests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaShares")
    let stage = UUID().uuidString
    let manifest = root.appendingPathComponent("\(stage).json")
    let paths = [root.appendingPathComponent("\(stage)/file.txt").path]
    let encodedPaths = String(decoding: try JSONEncoder().encode(paths), as: UTF8.self)
    for storedPaths: Any in [paths, encodedPaths] {
      let data = try JSONSerialization.data(withJSONObject: ["stage": stage, "paths": storedPaths])
      let decoded = try ShareInbox.decodeManifest(data, file: manifest, root: root)
      XCTAssertEqual(decoded["paths"] as? [String], paths)
    }

    let text = try JSONSerialization.data(withJSONObject: ["stage": stage, "text": "Hello"])
    XCTAssertEqual(
      try ShareInbox.decodeManifest(text, file: manifest, root: root)["text"] as? String,
      "Hello")
  }

  func testShareManifestRejectsInvalidPathsInCurrentAndLegacyManifests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaShares")
    let stage = UUID().uuidString
    let manifest = root.appendingPathComponent("\(stage).json")
    let outsidePaths = [root.appendingPathComponent("other/file.txt").path]
    let encodedOutsidePaths = String(decoding: try JSONEncoder().encode(outsidePaths), as: UTF8.self)
    for paths: Any in [outsidePaths, encodedOutsidePaths, "not json"] {
      let data = try JSONSerialization.data(withJSONObject: ["stage": stage, "paths": paths])
      XCTAssertThrowsError(try ShareInbox.decodeManifest(data, file: manifest, root: root))
    }
    let wrongStage = try JSONSerialization.data(
      withJSONObject: ["stage": UUID().uuidString, "text": "Hello"])
    XCTAssertThrowsError(
      try ShareInbox.decodeManifest(wrongStage, file: manifest, root: root))
  }

  func testShareManifestRejectsEmptyOversizedAndEscapingPaths() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("VelaShares")
    let stage = UUID().uuidString
    let manifest = root.appendingPathComponent("\(stage).json")
    let path = root.appendingPathComponent("\(stage)/file.txt").path
    for paths in [
      [String](), Array(repeating: path, count: 101),
      [root.appendingPathComponent("\(stage)/../outside.txt").path],
      [root.appendingPathComponent(stage).path],
    ] {
      let data = try JSONSerialization.data(withJSONObject: ["stage": stage, "paths": paths])
      XCTAssertThrowsError(try ShareInbox.decodeManifest(data, file: manifest, root: root))
    }
    let data = try JSONSerialization.data(
      withJSONObject: ["stage": stage, "paths": Array(repeating: path, count: 100)])
    XCTAssertEqual(
      try ShareInbox.decodeManifest(data, file: manifest, root: root)["paths"] as? [String],
      Array(repeating: path, count: 100))
  }

}
