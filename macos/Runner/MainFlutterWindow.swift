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
  func notifyVisible() { backgroundChannel?.invokeMethod("visible", arguments: nil) }
  func prepareToTerminate(_ completion: @escaping () -> Void) {
    updater.prepareToTerminate {
      var replied = false
      let finish = {
        guard !replied else { return }
        replied = true
        completion()
      }
      guard let channel = self.backgroundChannel else {
        finish()
        return
      }
      channel.invokeMethod("shutdown", arguments: nil) { _ in finish() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: finish)
    }
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
        result([
          "active": (NSApplication.shared.delegate as? AppDelegate)?.backgroundActive ?? false,
          "loginSupported": self.loginStatus() != "unsupported", "loginStatus": self.loginStatus(),
        ])
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
          if enabled && service.status == .notRegistered {
            try service.register()
          } else if !enabled && service.status != .notRegistered {
            try service.unregister()
          }
          result(self.loginStatus())
        } catch {
          result(FlutterError(code: "login", message: error.localizedDescription, details: nil))
        }
      case "isVisible":
        result(self.isVisible && NSApplication.shared.isActive)
      case "getWindowVisible":
        result(self.isVisible)
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
      case "offer":
        let args = call.arguments as? [String: Any] ?? [:]
        let app = NSApplication.shared.delegate as? AppDelegate
        app?.setIncoming(true)
        if args["focus"] as? Bool == true { app?.showWindow() }
        self.offerGeneration += 1
        let generation = self.offerGeneration
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, _ in
          DispatchQueue.main.async {
            guard allowed, self?.offerGeneration == generation else { return }
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
}
