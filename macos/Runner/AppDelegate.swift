import Carbon
import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import UserNotifications

private final class MenuStatusLight: NSView {
  var acceptDrop: (([URL]) -> Bool)?
  var color = NSColor.systemGray {
    didSet { needsDisplay = true }
  }

  override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }

  private func files(from sender: NSDraggingInfo) -> [URL] {
    sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let urls = files(from: sender)
    guard !urls.isEmpty, sender.draggingSourceOperationMask.contains(.copy) else { return [] }
    return .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return acceptDrop?(files(from: sender)) == true
  }

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: bounds.midX + 5, y: bounds.midY - 3, width: 6, height: 6)
    ).fill()
  }
}

final class MenuPreviewButton: NSButton {
  var menuItem: NSMenuItem?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  private var hoverArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  func setHovered(_ hovered: Bool) {
    let foreground: NSColor = hovered ? .alternateSelectedControlTextColor : .labelColor
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingMiddle
    if menuItem?.image != nil { style.tailIndent = -30 }
    attributedTitle = NSAttributedString(string: title, attributes: [
      .font: NSFont.menuFont(ofSize: 0), .foregroundColor: foreground, .paragraphStyle: style,
    ])
    contentTintColor = foreground
    layer?.backgroundColor = (hovered ? NSColor.selectedContentBackgroundColor : .clear).cgColor
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }
}

private struct MenuOffer {
  let id: String
  let sender: String
  let detail: String
  let clipboardHint: String?
  let accept: String
  let decline: String
  let decide: (String, Bool) -> Void
}

private struct MenuFileSelection {
  let peer: String
  let files: [[String: Any]]
}

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private let statusLight = MenuStatusLight()
  private let statusMenu = NSMenu()
  private weak var openStatusMenu: NSMenu?
  private var folderOpenFailed = false
  private var menuOffer: MenuOffer?
  private var menuDevices: [[String: String]] = []
  private var fileDropPanel: MenuFileDropPanel?
  private var finderDragTimer: Timer?
  private var dragChangeCount = 0
  private var finderDragActive = false
  private var receiptPanel: NSPanel?
  private var receiptDismissalMonitors: [Any] = []
  private var receipt: (title: String, files: [URL], text: Bool, link: URL?)?
  private var receiptError: String?
  private var menuSendError: String?
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
    if menuSendError != nil { return "sendFailed" }
    if completed { return "completed" }
    if nodeStatus == "ready", !backgroundActive,
      let window = NSApp?.windows.compactMap({ $0 as? MainFlutterWindow }).first,
      !window.isVisible || window.isMiniaturized
    { return "paused" }
    return nodeStatus
  }

  var menuStatusColor: NSColor {
    switch menuStatus {
    case "starting", "paused": return .systemGray
    case "failed", "sendFailed": return .systemRed
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
    updateMenuLight()
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
        "status": menuStatus, "panelVisible": openStatusMenu != nil,
        "panelHasOffer": menuOffer != nil,
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
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusMenu.delegate = self
    statusMenu.autoenablesItems = false
    menuNeedsUpdate(statusMenu)
    item.menu = statusMenu
    statusItem = item
    if let button = item.button {
      button.image = menuImage()
      statusLight.frame = button.bounds
      statusLight.autoresizingMask = [.width, .height]
      statusLight.registerForDraggedTypes([.fileURL])
      statusLight.acceptDrop = { [weak self] urls in self?.acceptDroppedFiles(urls) == true }
      button.addSubview(statusLight)
      let pasteboard = NSPasteboard(name: .drag)
      dragChangeCount = pasteboard.changeCount
      let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
        self?.observeFinderDrag(pasteboard)
      }
      timer.tolerance = 0.03
      RunLoop.main.add(timer, forMode: .common)
      finderDragTimer = timer
    }
    updateMenuLight()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    let chinese = menuIsChinese
    menu.removeAllItems()
    if let offer = menuOffer {
      menu.addItem(menuItem(shortMenuTitle(offer.sender)))
      if !offer.detail.isEmpty { menu.addItem(menuItem(shortMenuTitle(offer.detail))) }
      if let hint = offer.clipboardHint { menu.addItem(menuItem(hint)) }
      let accept = menuItem(offer.accept, action: #selector(decideMenuOfferFromItem(_:)))
      accept.representedObject = offer.id
      accept.tag = 1
      menu.addItem(accept)
      let decline = menuItem(offer.decline, action: #selector(decideMenuOfferFromItem(_:)))
      decline.representedObject = offer.id
      menu.addItem(decline)
      menu.addItem(.separator())
    }
    let receiptItems = receiptMenuItems()
    if !receiptItems.isEmpty {
      receiptItems.forEach(menu.addItem)
      menu.addItem(.separator())
    }

    for device in menuDevices {
      guard let name = device["name"], let status = device["label"] else { continue }
      let item = menuItem(shortMenuTitle(name))
      let image = deviceLight(for: device["presence"])
      // A read-only NSMenuItem title uses the disabled text color.
      let label = NSTextField(labelWithString: item.title)
      label.font = NSFont.menuFont(ofSize: 0)
      label.lineBreakMode = .byTruncatingMiddle
      let size = label.fittingSize
      label.frame = NSRect(x: 36, y: (24 - size.height) / 2,
                           width: min(size.width, 280), height: size.height)
      let light = NSImageView(image: image)
      light.frame = NSRect(origin: NSPoint(x: 17, y: 5.5), size: image.size)
      let row = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.maxX + 16, height: 24))
      row.addSubview(light)
      row.addSubview(label)
      row.setAccessibilityElement(true)
      row.setAccessibilityRole(.staticText)
      row.setAccessibilityLabel("\(name), \(status)")
      label.setAccessibilityElement(false)
      light.setAccessibilityElement(false)
      item.view = row
      menu.addItem(item)
    }
    if !menuDevices.isEmpty { menu.addItem(.separator()) }

    menu.addItem(menuItem(
      chinese ? "发送文件…" : "Send files…", icon: "paperplane",
      action: #selector(pickMenuFiles)))
    if let menuSendError { menu.addItem(menuItem(shortMenuTitle(menuSendError))) }
    menu.addItem(menuItem(
      chinese ? "打开接收文件夹" : "Open received folder", icon: "folder",
      action: #selector(openReceivedFolderFromMenu)))
    if folderOpenFailed {
      menu.addItem(menuItem(chinese ? "无法打开接收文件夹" : "Could not open the received folder"))
    }
    menu.addItem(menuItem(
      chinese ? "打开 Vela" : "Open Vela", icon: "macwindow", action: #selector(showWindow)))
    let quit = menuItem(
      chinese ? "退出 Vela" : "Quit Vela", icon: "power", action: #selector(NSApplication.terminate(_:)))
    quit.target = NSApp
    menu.addItem(quit)
  }

  func menuWillOpen(_ menu: NSMenu) {
    fileDropPanel?.dismiss()
    dismissReceiptPreview()
    openStatusMenu = menu
  }
  func menuDidClose(_ menu: NSMenu) { openStatusMenu = nil }

  @objc private func pickMenuFiles() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { [weak self] result in
      if result == .OK { _ = self?.chooseMenuRecipient(for: panel.urls) }
    }
  }

  private func menuFileTitle(_ urls: [URL]) -> String {
    let name = shortMenuTitle(urls[0].lastPathComponent)
    if menuIsChinese {
      return urls.count == 1 ? "把「\(name)」发送到" : "发送 \(urls.count) 个文件到"
    }
    let files = urls.count == 1 ? "“\(name)”" : "\(urls.count) files"
    return "Send \(files) to"
  }

  private func observeFinderDrag(_ pasteboard: NSPasteboard) {
    let count = pasteboard.changeCount
    guard NSEvent.pressedMouseButtons & 1 != 0 else {
      dragChangeCount = count
      if finderDragActive {
        finderDragActive = false
        // AppKit can deliver the accepted drop after the mouse button is released.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak panel = fileDropPanel] in
          if self?.finderDragActive == false { panel?.endDrag() }
        }
      }
      return
    }
    guard count != dragChangeCount else { return }
    dragChangeCount = count
    guard !finderDragActive, openStatusMenu == nil,
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
          pasteboard.types?.contains(.fileURL) == true else { return }
    finderDragActive = showFileDropHint()
  }

  private func showFileDropHint() -> Bool {
    guard let button = statusItem?.button else { return false }
    if fileDropPanel?.isVisible == true { return true }
    let panel = MenuFileDropPanel()
    fileDropPanel = panel
    panel.acceptFiles = { [weak self] urls in self?.acceptDroppedFiles(urls) == true }
    dismissReceiptPreview()
    return panel.showHint(
      under: button, icon: button.image,
      hint: menuIsChinese ? "把文件拖到这里" : "Drag files here",
      dropHint: menuIsChinese ? "松手添加文件" : "Release to add files")
  }

  private func acceptDroppedFiles(_ urls: [URL]) -> Bool {
    guard let files = prepareMenuFiles(urls), showFileDropHint(), let fileDropPanel else { return false }
    fileDropPanel.showDevices(menuTargets(for: urls, files: files, showPresence: true))
    return true
  }

  private func receiptMenuItems() -> [NSMenuItem] {
    guard let receipt else { return [] }
    var items = [
      menuHeading(shortMenuTitle(receipt.title)),
      menuItem(menuIsChinese ? "打开" : "Open", icon: "arrow.up.right.square",
               action: #selector(openMenuReceipt)),
      menuItem(menuIsChinese ? "复制" : "Copy", icon: "document.on.document",
               action: #selector(copyMenuReceipt)),
    ]
    if let receiptError { items.append(menuItem(receiptError)) }
    return items
  }

  // Keep AppKit menu tracking for clicks on the status item. Automatic previews
  // render the same commands without starting a menu tracking session.
  private func showMenuPreview(_ items: [NSMenuItem]) -> NSPanel? {
    guard let button = statusItem?.button, let window = button.window,
      let screen = window.screen else { return nil }
    let rows: [NSView] = items.enumerated().map { index, item in
      if let action = item.action {
        let command = MenuPreviewButton(title: item.title, target: item.target, action: action)
        command.image = item.image
        command.imagePosition = .imageLeading
        command.alignment = .left
        command.isBordered = false
        command.wantsLayer = true
        command.layer?.cornerRadius = 5
        command.setHovered(false)
        command.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return command
      }
      let label = NSTextField(labelWithString: item.title)
      label.font = index == 0
        ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        : .menuFont(ofSize: 0)
      label.lineBreakMode = .byTruncatingMiddle
      label.widthAnchor.constraint(lessThanOrEqualToConstant: 328).isActive = true
      return label
    }
    let stack = NSStackView(views: rows)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let size = stack.fittingSize
    let width = max(size.width, 220)
    for case let command as MenuPreviewButton in rows {
      command.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
    }
    let visible = screen.visibleFrame
    let x = max(visible.minX, min(anchor.minX, visible.maxX - width))
    let frame = NSRect(x: x, y: anchor.minY - size.height - 4, width: width, height: size.height)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
    material.material = .menu
    material.blendingMode = .behindWindow
    material.state = .active
    material.maskImage = NSImage(size: frame.size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
      return true
    }
    stack.frame = material.bounds
    material.addSubview(stack)
    panel.contentView = material
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.orderFrontRegardless()
    return panel
  }

  func recordMenuReceipt(_ args: [String: Any], inBackground: Bool) {
    finishTransfer(inBackground: inBackground)
    guard let title = args["title"] as? String, let paths = args["paths"] as? [String],
      !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) else { return }
    let link = (args["link"] as? String).flatMap(URL.init(string:)).flatMap { url in
      (url.scheme == "https" || url.scheme == "http") && url.host != nil ? url : nil
    }
    receipt = (title, paths.map { URL(fileURLWithPath: $0) }, args["isText"] as? Bool == true, link)
    receiptError = nil
    dismissReceiptPreview()
    if let openStatusMenu {
      menuNeedsUpdate(openStatusMenu)
      return
    }
    guard inBackground, args["showWindow"] as? Bool != true, fileDropPanel?.isVisible != true,
      let panel = showMenuPreview(receiptMenuItems()) else { return }
    receiptPanel = panel
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    receiptDismissalMonitors = [
      NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
        self?.dismissReceiptPreview()
      },
      NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
        if event.window !== self?.receiptPanel { self?.dismissReceiptPreview() }
        return event
      },
    ].compactMap { $0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak panel] in
      guard let self, let panel, receiptPanel === panel else { return }
      dismissReceiptPreview()
    }
  }

  private func dismissReceiptPreview() {
    receiptPanel?.orderOut(nil)
    receiptPanel = nil
    receiptDismissalMonitors.forEach(NSEvent.removeMonitor)
    receiptDismissalMonitors.removeAll()
  }

  @objc private func openMenuReceipt() {
    guard let receipt else { return }
    if let link = receipt.link {
      finishReceiptAction(NSWorkspace.shared.open(link))
    } else if receipt.files.count == 1 {
      finishReceiptAction(NSWorkspace.shared.open(receipt.files[0]))
    } else {
      let existing = receipt.files.filter { FileManager.default.fileExists(atPath: $0.path) }
      if !existing.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(existing) }
      finishReceiptAction(!existing.isEmpty)
    }
  }

  func copyCurrentReceipt(to pasteboard: NSPasteboard) -> Bool {
    guard let receipt else { return false }
    let first = receipt.files[0]
    if receipt.text {
      guard let text = try? String(contentsOf: first, encoding: .utf8) else { return false }
      pasteboard.clearContents()
      return pasteboard.setString(text, forType: .string)
    }
    guard receipt.files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      return false
    }
    if receipt.files.count == 1,
      UTType(filenameExtension: first.pathExtension)?.conforms(to: .image) == true,
      let image = NSImage(contentsOf: first) {
      pasteboard.clearContents()
      return pasteboard.writeObjects([image])
    }
    pasteboard.clearContents()
    return pasteboard.writeObjects(receipt.files.map { $0 as NSURL })
  }

  @objc private func copyMenuReceipt() {
    finishReceiptAction(copyCurrentReceipt(to: .general))
  }

  private func finishReceiptAction(_ success: Bool) {
    dismissReceiptPreview()
    receiptError = success ? nil : (menuIsChinese ? "无法处理接收内容" : "Could not access received content")
    if !success, let button = statusItem?.button {
      DispatchQueue.main.async { [weak self] in
        self?.statusMenu.popUp(positioning: nil, at: .zero, in: button)
      }
    }
  }

  @discardableResult
  func chooseMenuRecipient(for urls: [URL]) -> Bool {
    guard let button = statusItem?.button, let files = prepareMenuFiles(urls) else { return false }
    dismissReceiptPreview()
    let targets = menuTargets(for: urls, files: files)
    DispatchQueue.main.async { targets.popUp(positioning: nil, at: .zero, in: button) }
    return true
  }

  private func prepareMenuFiles(_ urls: [URL]) -> [[String: Any]]? {
    guard !urls.isEmpty, urls.count <= 100,
      urls.allSatisfy({ url in
        url.isFileURL && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      }) else { return nil }
    return urls.map { url in
      var file: [String: Any] = ["path": url.path]
      if let bookmark = try? url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil, relativeTo: nil) {
        file["bookmark"] = FlutterStandardTypedData(bytes: bookmark)
      }
      return file
    }
  }

  func menuTargets(for urls: [URL], files: [[String: Any]], showPresence: Bool = false) -> NSMenu {
    let targets = NSMenu()
    targets.autoenablesItems = false
    targets.addItem(menuHeading(menuFileTitle(urls)))
    for device in menuDevices {
      guard let name = device["name"], let peer = device["id"] else { continue }
      let item = menuItem(shortMenuTitle(name), action: #selector(sendMenuSelection(_:)))
      item.representedObject = MenuFileSelection(peer: peer, files: files)
      if showPresence {
        item.image = deviceLight(for: device["presence"])
        item.toolTip = device["label"].map { "\(name), \($0)" } ?? name
      }
      targets.addItem(item)
    }
    if targets.items.count == 1 {
      targets.addItem(menuItem(menuIsChinese ? "添加设备…" : "Add a device…", action: #selector(showWindow)))
    }
    return targets
  }

  @objc private func sendMenuSelection(_ item: NSMenuItem) {
    guard let selection = item.representedObject as? MenuFileSelection,
      let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first else { return }
    menuSendError = nil
    updateMenuLight()
    window.sendMenuFiles(selection.files, to: selection.peer) { [weak self] error in
      guard let self else { return }
      menuSendError = error
      updateMenuLight()
    }
  }

  private func shortMenuTitle(_ text: String) -> String {
    let line = text.components(separatedBy: .newlines).joined(separator: " ")
    if line.count <= 54 { return line }
    return String(line.prefix(35)) + "…" + String(line.suffix(18))
  }

  private func deviceLight(for presence: String?) -> NSImage {
    let color: NSColor = switch presence {
    case "reachable": .systemGreen
    case "unavailable": .systemRed
    default: .systemGray
    }
    return NSImage(size: NSSize(width: 13, height: 13), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5)).fill()
      return true
    }
  }

  private func menuItem(_ title: String, icon: String? = nil, action: Selector? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = action != nil
    if let icon {
      item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
    }
    return item
  }

  private func menuHeading(_ title: String) -> NSMenuItem {
    let item = menuItem(title)
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    label.lineBreakMode = .byTruncatingMiddle
    let size = label.fittingSize
    label.frame = NSRect(x: 14, y: (25 - size.height) / 2, width: min(size.width, 328), height: size.height)
    let row = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.maxX + 14, height: 25))
    row.addSubview(label)
    item.view = row
    return item
  }

  @objc private func decideMenuOfferFromItem(_ item: NSMenuItem) {
    guard let id = item.representedObject as? String else { return }
    decideMenuOffer(id, accepted: item.tag == 1)
  }

  @objc private func openReceivedFolderFromMenu() {
    let window = NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first
    folderOpenFailed = (try? window?.openReceiveFolder()) != true
  }

  func setMenuOffer(_ args: [String: Any], decide: @escaping (String, Bool) -> Void) {
    if let id = args["id"] as? String {
      menuOffer = MenuOffer(
        id: id, sender: args["title"] as? String ?? "Vela",
        detail: args["detail"] as? String ?? "",
        clipboardHint: args["clipboardHint"] as? String,
        accept: args["accept"] as? String ?? "Accept",
        decline: args["reject"] as? String ?? "Decline", decide: decide)
    }
    setIncoming(true)
  }

  func decideMenuOffer(_ id: String, accepted: Bool) {
    guard let offer = menuOffer, offer.id == id else { return }
    menuOffer = nil
    updateMenuLight()
    offer.decide(id, accepted)
  }

  private func menuImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { _ in
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
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Vela"
    return image
  }

  func setIncoming(_ incoming: Bool) {
    self.incoming = incoming
    if !incoming { menuOffer = nil }
    updateMenuLight()
  }

  func setNodeStatus(_ status: String) {
    guard ["starting", "ready", "failed"].contains(status) else { return }
    nodeStatus = status
    if status != "ready" { menuDevices = [] }
    updateMenuLight()
  }

  func setMenuDevices(_ devices: [[String: String]]) {
    guard devices != menuDevices else { return }
    menuDevices = devices
    if let openStatusMenu { menuNeedsUpdate(openStatusMenu) }
  }

  func setTransferring(_ transferring: Bool) {
    self.transferring = transferring
    if transferring {
      completed = false
      menuSendError = nil
    }
    updateMenuLight()
  }

  func finishTransfer(inBackground: Bool) {
    transferring = false
    menuSendError = nil
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
    case "paused": return chinese ? "Vela — 接收已暂停" : "Vela — Receiving paused"
    case "failed": return chinese ? "Vela — 启动失败" : "Vela — Could not start"
    case "sendFailed": return chinese ? "Vela — 发送失败" : "Vela — Send failed"
    case "transferring": return chinese ? "Vela — 正在传输" : "Vela — Transferring"
    case "completed": return chinese ? "Vela — 传输完成" : "Vela — Transfer complete"
    case "notification": return chinese ? "Vela — 接收请求" : "Vela — Incoming request"
    default: return chinese ? "Vela — 可以接收" : "Vela — Ready to receive"
    }
  }

  func updateMenuLight() {
    guard let button = statusItem?.button else { return }
    let description = menuDescription(menuStatus)
    statusLight.color = menuStatusColor
    button.toolTip = description
    button.setAccessibilityLabel(description)
    if let openStatusMenu { menuNeedsUpdate(openStatusMenu) }
  }

  @objc func showWindow() {
    statusMenu.cancelTracking()
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
    finderDragTimer?.invalidate()
    fileDropPanel?.dismiss()
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
