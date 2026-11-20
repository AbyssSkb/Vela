import Cocoa
import FlutterMacOS
import Network
import ServiceManagement
import UserNotifications

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var backgroundChannel: FlutterMethodChannel?
  private var wakeObserver: NSObjectProtocol?
  private let networkMonitor = NWPathMonitor()
  private var lastNetworkPath: NWPath?
  private var networkChangeScheduled = false
  private var offerGeneration = 0
  private let receiveDirectory = ReceiveDirectoryAccess()
  private let updater = VelaUpdater()

  private func loginStatus() -> String {
    guard #available(macOS 13.0, *) else { return "unsupported" }
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .notRegistered: return "notRegistered"
    case .requiresApproval: return "requiresApproval"
    case .notFound: return "notFound"
    @unknown default: return "unknown"
    }
  }

  deinit {
    networkMonitor.cancel()
    if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
  }

  private func networkChanged() {
    guard !networkChangeScheduled else { return }
    networkChangeScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self else { return }
      self.networkChangeScheduled = false
      self.backgroundChannel?.invokeMethod("networkChanged", arguments: nil)
    }
  }

  func shareAvailable() { shareChannel?.invokeMethod("available", arguments: nil) }
  func notifyVisible() {
    (NSApplication.shared.delegate as? AppDelegate)?.clearTransferCompletion()
    backgroundChannel?.invokeMethod("visible", arguments: nil)
  }
  func prepareToTerminate(_ completion: @escaping () -> Void) {
    guard let channel = backgroundChannel else {
      completion()
      return
    }
    channel.invokeMethod("shutdown", arguments: nil) { _ in completion() }
  }
  func hideWindow() {
    orderOut(nil)
    backgroundChannel?.invokeMethod("hidden", arguments: nil)
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideWindow()
    return false
  }
  func windowDidBecomeKey(_ notification: Notification) { notifyVisible() }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 320, height: 480)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)
    updater.register(messenger: flutterViewController.engine.binaryMessenger)
    self.delegate = self

    let channel = FlutterMethodChannel(
      name: "vela/device", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "info" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
      result(["name": name, "type": "desktop"])
    }

    let share = FlutterMethodChannel(
      name: "vela/share", binaryMessenger: flutterViewController.engine.binaryMessenger)
    shareChannel = share
    share.setMethodCallHandler { call, result in
      do {
        let inbox = try ShareInbox.open()
        switch call.method {
        case "take": result(try inbox.take())
        case "cleanup":
          guard let args = call.arguments as? [String: String],
            let stage = args["stage"], UUID(uuidString: stage) != nil
          else {
            result(FlutterMethodNotImplemented)
            return
          }
          inbox.cleanup(stage: stage)
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "share", message: error.localizedDescription, details: nil))
      }
    }

    let files = FlutterMethodChannel(
      name: "vela/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    files.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "reveal", let path = args["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(nil)
      } else if call.method == "openUrl", let value = args["url"] as? String,
        let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
        url.host != nil
      {
        result(
          NSWorkspace.shared.open(url)
            ? nil : FlutterError(code: "url", message: "Cannot open URL", details: nil))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let storage = FlutterMethodChannel(
      name: "vela/storage", binaryMessenger: flutterViewController.engine.binaryMessenger)
    storage.setMethodCallHandler { call, result in
      switch call.method {
      case "location":
        do {
          result(try self.receiveDirectory.location())
        } catch {
          result(FlutterError(code: "storage", message: error.localizedDescription, details: nil))
        }
      case "openFolder":
        do {
          result(
            NSWorkspace.shared.open(try self.receiveDirectory.currentDirectory())
              ? nil : FlutterError(code: "storage", message: "Cannot open folder", details: nil))
        } catch {
          result(FlutterError(code: "storage", message: error.localizedDescription, details: nil))
        }
      case "reset":
        self.receiveDirectory.reset()
        result(nil)
      case "choose":
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let url = panel.url else {
            result(false)
            return
          }
          do {
            try self.receiveDirectory.select(url)
            result(true)
          } catch {
            result(FlutterError(code: "storage", message: error.localizedDescription, details: nil))
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }

    let background = FlutterMethodChannel(
      name: "vela/background", binaryMessenger: flutterViewController.engine.binaryMessenger)
    backgroundChannel = background
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.backgroundChannel?.invokeMethod("systemWake", arguments: nil)
    }
    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let previous = self.lastNetworkPath
      self.lastNetworkPath = path
      if let previous, previous != path { self.networkChanged() }
    }
    networkMonitor.start(queue: .main)
    background.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "setMacBackground":
        guard let enabled = call.arguments as? Bool,
          let app = NSApplication.shared.delegate as? AppDelegate
        else {
          result(
            FlutterError(
              code: "background", message: "Cannot update background receiving", details: nil))
          return
        }
        app.setBackgroundActive(enabled)
        result(nil)
      case "macBackgroundStatus":
        let login = self.loginStatus()
        center.getNotificationSettings { settings in
          DispatchQueue.main.async {
            result([
              "active": (NSApplication.shared.delegate as? AppDelegate)?.backgroundActive ?? false,
              "loginSupported": login != "unsupported", "loginStatus": login,
              "notifications": Self.canNotify(settings),
            ])
          }
        }
      case "setLaunchAtLogin":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "login", message: "Missing login setting", details: nil))
          return
        }
        guard #available(macOS 13.0, *) else {
          result(
            FlutterError(
              code: "login", message: "Login items require macOS 13 or later", details: nil))
          return
        }
        do {
          let service = SMAppService.mainApp
          switch (enabled, service.status) {
          case (true, .notRegistered), (true, .notFound):
            try service.register()
          case (false, .enabled), (false, .requiresApproval):
            try service.unregister()
          default:
            break
          }
          result(self.loginStatus())
        } catch {
          result(FlutterError(code: "login", message: error.localizedDescription, details: nil))
        }
      case "settings":
        let section = (call.arguments as? [String: String])?["section"]
        if section == "notification_requests" {
          Self.openNotificationSettings(center, result: result)
          return
        }
        guard #available(macOS 13.0, *),
          section == "login"
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        SMAppService.openSystemSettingsLoginItems()
        result(nil)
      case "isVisible":
        result(self.isVisible && NSApplication.shared.isActive)
      case "getWindowVisible":
        result(self.isVisible)
      case "setMenuLanguage":
        guard let language = call.arguments as? String else {
          result(FlutterError(code: "language", message: "Missing menu language", details: nil))
          return
        }
        (NSApplication.shared.delegate as? AppDelegate)?.setMenuLanguage(language)
        result(nil)
      case "setNodeStatus":
        guard let status = call.arguments as? String else {
          result(FlutterError(code: "status", message: "Missing node status", details: nil))
          return
        }
        (NSApplication.shared.delegate as? AppDelegate)?.setNodeStatus(status)
        result(nil)
      case "setTransferring":
        guard let transferring = call.arguments as? Bool else {
          result(FlutterError(code: "status", message: "Missing transfer state", details: nil))
          return
        }
        (NSApplication.shared.delegate as? AppDelegate)?.setTransferring(transferring)
        result(nil)
      case "transferCompleted":
        guard let showOnCompletion = call.arguments as? Bool else {
          result(FlutterError(code: "status", message: "Missing completion setting", details: nil))
          return
        }
        let app = NSApplication.shared.delegate as? AppDelegate
        let inBackground = !self.isVisible || self.isMiniaturized || !NSApp.isActive
        app?.finishTransfer(inBackground: inBackground)
        if inBackground && showOnCompletion { app?.showWindow() }
        result(nil)
      case "offer":
        let args = call.arguments as? [String: Any] ?? [:]
        let app = NSApplication.shared.delegate as? AppDelegate
        app?.setIncoming(true)
        self.offerGeneration += 1
        let generation = self.offerGeneration
        center.getNotificationSettings { [weak self] settings in
          DispatchQueue.main.async {
            guard Self.canNotify(settings), self?.offerGeneration == generation else { return }
            let content = UNMutableNotificationContent()
            content.title = args["title"] as? String ?? "Vela"
            content.body = args["message"] as? String ?? "Incoming transfer"
            content.sound = .default
            center.add(
              UNNotificationRequest(identifier: "incoming-offer", content: content, trigger: nil))
          }
        }
        result(nil)
      case "clearOffer":
        self.offerGeneration += 1
        (NSApplication.shared.delegate as? AppDelegate)?.setIncoming(false)
        center.removeDeliveredNotifications(withIdentifiers: ["incoming-offer"])
        center.removePendingNotificationRequests(withIdentifiers: ["incoming-offer"])
        result(nil)
      #if DEBUG
        case "testMenu":
          result((NSApplication.shared.delegate as? AppDelegate)?.statusDetails ?? [:])
        case "testMenuIncoming":
          (NSApplication.shared.delegate as? AppDelegate)?.setIncoming(
            call.arguments as? Bool ?? false)
          result(nil)
        case "testClose":
          self.performClose(nil)
          result(nil)
        case "testShow":
          (NSApplication.shared.delegate as? AppDelegate)?.showWindow()
          result(nil)
        case "testStatus":
          result([
            "incoming": (NSApplication.shared.delegate as? AppDelegate)?.incoming ?? false,
            "visible": self.isVisible,
          ])
      #endif
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    DispatchQueue.main.async {
      (NSApplication.shared.delegate as? AppDelegate)?.ensureStatusItem()
    }
  }

  private static func canNotify(_ settings: UNNotificationSettings) -> Bool {
    settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
  }

  private static func openNotificationSettings(
    _ center: UNUserNotificationCenter, result: @escaping FlutterResult
  ) {
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        if settings.authorizationStatus == .notDetermined {
          center.requestAuthorization(options: [.alert, .sound]) { _, error in
            DispatchQueue.main.async {
              if let error {
                result(FlutterError(code: "notification", message: error.localizedDescription, details: nil))
              } else {
                result(nil)
              }
            }
          }
          return
        }
        let pane: String
        if #available(macOS 13.0, *) {
          pane = "com.apple.Notifications-Settings.extension"
        } else {
          pane = "com.apple.preference.notifications"
        }
        if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) {
          result(nil)
        } else {
          result(FlutterError(code: "notification", message: "Could not open notification settings", details: nil))
        }
      }
    }
  }
}
