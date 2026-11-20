import Carbon
import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private var statusItem: NSStatusItem?
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
        "imageHash": button?.image?.tiffRepresentation?.hashValue ?? 0,
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
    updateMenuImage()
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

  private func menuImage(status: String) -> NSImage {
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
      if status != "ready" {
        let badge = NSRect(x: 11, y: 11, width: 7, height: 7)
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: badge.insetBy(dx: -0.5, dy: -0.5)).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        if status == "notification" {
          NSBezierPath(ovalIn: badge.insetBy(dx: 1, dy: 1)).fill()
        } else if status == "starting" {
          NSBezierPath(ovalIn: badge.insetBy(dx: 1.5, dy: 1.5)).stroke()
        } else {
          let path = NSBezierPath()
          path.lineWidth = 1.3
          if status == "failed" {
            path.move(to: NSPoint(x: 12, y: 12))
            path.line(to: NSPoint(x: 17, y: 17))
            path.move(to: NSPoint(x: 17, y: 12))
            path.line(to: NSPoint(x: 12, y: 17))
          } else if status == "completed" {
            path.move(to: NSPoint(x: 12, y: 14))
            path.line(to: NSPoint(x: 14, y: 12))
            path.line(to: NSPoint(x: 17, y: 16))
          } else {
            path.move(to: NSPoint(x: 12, y: 13))
            path.line(to: NSPoint(x: 15.5, y: 16.5))
            path.move(to: NSPoint(x: 13.5, y: 16.5))
            path.line(to: NSPoint(x: 15.5, y: 16.5))
            path.line(to: NSPoint(x: 15.5, y: 14.5))
          }
          path.stroke()
        }
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = menuDescription(status)
    return image
  }

  func setIncoming(_ incoming: Bool) {
    self.incoming = incoming
    updateMenuImage()
  }

  func setNodeStatus(_ status: String) {
    guard ["starting", "ready", "failed"].contains(status) else { return }
    nodeStatus = status
    updateMenuImage()
  }

  func setTransferring(_ transferring: Bool) {
    self.transferring = transferring
    if transferring { completed = false }
    updateMenuImage()
  }

  func finishTransfer(inBackground: Bool) {
    transferring = false
    completed = inBackground
    updateMenuImage()
  }

  func clearTransferCompletion() {
    guard completed else { return }
    completed = false
    updateMenuImage()
  }

  func setMenuLanguage(_ language: String) {
    menuLanguage = language
    updateMenuImage()
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

  private func updateMenuImage() {
    statusItem?.button?.image = menuImage(status: menuStatus)
    statusItem?.button?.toolTip = menuDescription(menuStatus)
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
