import Carbon
import Cocoa
import FlutterMacOS
import UserNotifications

private final class MenuStatusLight: NSView {
  var color = NSColor.systemGray {
    didSet { needsDisplay = true }
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: bounds.midX + 2.5, y: bounds.midY + 2.5, width: 6, height: 6)
    ).fill()
  }
}

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private var statusItem: NSStatusItem?
  private let statusLight = MenuStatusLight()
  private var backgroundActivity: NSObjectProtocol?
  private var menuLanguage: String?
  private var menuIsChinese: Bool {
    (menuLanguage ?? Locale.preferredLanguages.first)?.hasPrefix("zh") == true
  }
  private(set) var incoming = false
  private(set) var nodeStatus = "starting"
  private(set) var transferring = false
  private var completed = false
  var menuStatus: String {
    if incoming { return "notification" }
    if transferring { return "transferring" }
    return completed ? "completed" : nodeStatus
  }

  var menuStatusColor: NSColor {
    switch menuStatus {
    case "starting": return .systemGray
    case "failed": return .systemRed
    case "notification": return .systemOrange
    case "transferring": return .systemBlue
    case "completed": return .systemPurple
    default: return .systemGreen
    }
  }

  var backgroundActive: Bool { backgroundActivity != nil }

  func setBackgroundActive(_ enabled: Bool) {
    if enabled && backgroundActivity == nil {
      backgroundActivity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiated, reason: "Vela background receiving")
    } else if !enabled, let activity = backgroundActivity {
      ProcessInfo.processInfo.endActivity(activity)
      backgroundActivity = nil
    }
  }

  static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        == keyAELaunchedAsLogInItem
  }

  #if DEBUG
    var statusDetails: [String: Any] {
      let button = statusItem?.button
      return [
        "exists": statusItem != nil, "visible": statusItem?.isVisible ?? false,
        "status": menuStatus,
        "hasImage": button?.image != nil, "windowVisible": button?.window?.isVisible ?? false,
        "lightColor": statusLight.superview != nil ? statusLight.color.description : "",
        "frame": button?.window.map { NSStringFromRect($0.frame) } ?? "none",
      ]
    }
  #endif

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let launchedAtLogin = Self.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    super.applicationDidFinishLaunching(notification)
    ensureStatusItem()
    if launchedAtLogin {
      (NSApplication.shared.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow)?
        .hideWindow()
    }
  }

  func ensureStatusItem() {
    guard statusItem == nil else { return }
    UNUserNotificationCenter.current().delegate = self
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.target = self
    item.button?.action = #selector(statusClicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item
    if let button = item.button {
      button.image = menuImage()
      statusLight.frame = button.bounds
      statusLight.autoresizingMask = [.width, .height]
      button.addSubview(statusLight)
    }
    updateMenuLight()
  }

  @objc private func statusClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent,
      event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    else {
      showWindow()
      return
    }
    let menu = NSMenu()
    let quit = menu.addItem(
      withTitle: menuIsChinese ? "退出 Vela" : "Quit Vela",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "")
    quit.target = NSApplication.shared
    NSMenu.popUpContextMenu(menu, with: event, for: sender)
  }

  private func menuImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setFill()
      for angle in stride(from: 0.0, to: 360.0, by: 90.0) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 9, yBy: 9)
        transform.rotate(byDegrees: angle)
        transform.concat()
        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: 0, y: 0))
        blade.curve(
          to: NSPoint(x: 0, y: 7), controlPoint1: NSPoint(x: 3, y: 1),
          controlPoint2: NSPoint(x: 3, y: 5))
        blade.curve(
          to: NSPoint(x: -4.5, y: 2), controlPoint1: NSPoint(x: -1, y: 5),
          controlPoint2: NSPoint(x: -1, y: 3))
        blade.curve(
          to: NSPoint(x: 0, y: 0), controlPoint1: NSPoint(x: -2.5, y: 2),
          controlPoint2: NSPoint(x: -1, y: 1))
        blade.close()
        blade.fill()
        NSGraphicsContext.restoreGraphicsState()
      }
      let cutout = NSRect(x: 10.5, y: 10.5, width: 8, height: 8)
      NSGraphicsContext.current?.compositingOperation = .clear
      NSBezierPath(ovalIn: cutout).fill()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Vela"
    return image
  }

  func setIncoming(_ incoming: Bool) {
    self.incoming = incoming
    updateMenuLight()
  }

  func setNodeStatus(_ status: String) {
    guard ["starting", "ready", "failed"].contains(status) else { return }
    nodeStatus = status
    updateMenuLight()
  }

  func setTransferring(_ transferring: Bool) {
    self.transferring = transferring
    if transferring { completed = false }
    updateMenuLight()
  }

  func finishTransfer(inBackground: Bool) {
    transferring = false
    completed = inBackground
    updateMenuLight()
  }

  func clearTransferCompletion() {
    guard completed else { return }
    completed = false
    updateMenuLight()
  }

  func setMenuLanguage(_ language: String) {
    menuLanguage = language
    updateMenuLight()
  }

  private func menuDescription(_ status: String) -> String {
    let chinese = menuIsChinese
    switch status {
    case "starting": return chinese ? "Vela — 正在启动" : "Vela — Starting"
    case "failed": return chinese ? "Vela — 启动失败" : "Vela — Could not start"
    case "transferring": return chinese ? "Vela — 正在传输" : "Vela — Transferring"
    case "completed": return chinese ? "Vela — 传输完成" : "Vela — Transfer complete"
    case "notification": return chinese ? "Vela — 有通知" : "Vela — Notification"
    default: return chinese ? "Vela — 可以接收" : "Vela — Ready to receive"
    }
  }

  private func updateMenuLight() {
    guard let button = statusItem?.button else { return }
    let description = menuDescription(menuStatus)
    statusLight.color = menuStatusColor
    button.toolTip = description
    button.setAccessibilityLabel(description)
  }

  @objc func showWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let window = NSApplication.shared.windows.first(where: { $0 is MainFlutterWindow })
      as? MainFlutterWindow
    {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
      window.notifyVisible()
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
    if urls.contains(where: { $0.scheme == "vela-share" }) {
      showWindow()
      (NSApplication.shared.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow)?
        .shareAvailable()
    }
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !flag { showWindow() }
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
  {
    setBackgroundActive(false)
    guard let window = sender.windows.compactMap({ $0 as? MainFlutterWindow }).first else {
      return .terminateNow
    }
    var replied = false
    let finish = {
      guard !replied else { return }
      replied = true
      sender.reply(toApplicationShouldTerminate: true)
    }
    window.prepareToTerminate(finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: finish)
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    showWindow()
    completionHandler()
  }
}
