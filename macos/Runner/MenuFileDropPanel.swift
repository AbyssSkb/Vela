import Cocoa

final class MenuFileDropPanel: NSPanel, NSDraggingDestination {
  private static let accent = NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
      return NSColor(srgbRed: 0.73, green: 0.77, blue: 1, alpha: 1)
    }
    return NSColor(srgbRed: 0.33, green: 0.40, blue: 0.79, alpha: 1)
  }
  private let dropArea = NSVisualEffectView()
  private let hintFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
  private var visibleScreen = NSRect.zero
  private var anchorX: CGFloat = 0
  private let iconSide: CGFloat = 18
  private let textGap: CGFloat = 4
  private var compactWidth: CGFloat { hintWidth(hint, padding: 12) }
  private var icon: NSImage?
  private var hint = ""
  private var dropHint = ""
  private var choosingDevice = false
  private var dismissalMonitors: [Any] = []
  private var outsidePress: NSPoint?
  private weak var fileTitle: NSTextField?
  private var fileSummary = ""
  private(set) var pendingURLs: [URL] = []
  private(set) var pendingFiles: [[String: Any]] = []

  var acceptFiles: (([URL]) -> Bool)?
  override var canBecomeKey: Bool { choosingDevice }
  override var canBecomeMain: Bool { false }

  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
               backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .popUpMenu
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    dropArea.material = .menu
    dropArea.blendingMode = .behindWindow
    dropArea.state = .active
    dropArea.wantsLayer = true
    dropArea.layer?.cornerRadius = 13
    contentView = dropArea
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard sender.draggingSourceOperationMask.contains(.copy),
          sender.draggingPasteboard.types?.contains(.fileURL) == true else { return [] }
    showDropArea(targeted: true)
    return .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) { showDropArea(targeted: false) }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    let accepted = acceptFiles?(urls) == true
    if choosingDevice { showDropArea(targeted: false) }
    return accepted
  }

  func showHint(under button: NSStatusBarButton, icon: NSImage?, hint: String, dropHint: String) -> Bool {
    if isVisible { return true }
    guard let window = button.window, let screen = window.screen else { return false }
    self.icon = icon
    self.hint = hint
    self.dropHint = dropHint
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    visibleScreen = screen.visibleFrame
    anchorX = anchor.midX
    setFrame(NSRect(x: anchor.minX, y: anchor.minY - 40, width: compactWidth, height: 36), display: false)
    showDropArea(targeted: false)
    orderFrontRegardless()
    registerForDraggedTypes([.fileURL])
    return true
  }

  private func showDropArea(targeted: Bool) {
    highlightDropTarget(targeted)
    if choosingDevice {
      fileTitle?.stringValue = targeted ? dropHint : fileSummary
      return
    }
    let text = targeted ? dropHint : hint
    let width = targeted ? max(compactWidth, hintWidth(text, padding: 16)) : compactWidth
    resize(width: width, height: targeted ? 44 : 36)
    dropArea.subviews.forEach { $0.removeFromSuperview() }
    let label = NSTextField(labelWithString: text)
    label.font = hintFont
    let image = NSImageView()
    image.image = targeted ? NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil) : icon
    image.contentTintColor = targeted ? Self.accent : .labelColor
    let stack = NSStackView(views: [image, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = textGap
    stack.translatesAutoresizingMaskIntoConstraints = false
    dropArea.addSubview(stack)
    NSLayoutConstraint.activate([
      image.widthAnchor.constraint(equalToConstant: iconSide),
      image.heightAnchor.constraint(equalTo: image.widthAnchor),
      stack.centerXAnchor.constraint(equalTo: dropArea.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: dropArea.centerYAnchor),
    ])
  }

  func showDevices(_ menu: NSMenu, urls: [URL], files: [[String: Any]]) {
    choosingDevice = true
    pendingURLs = urls
    pendingFiles = files
    highlightDropTarget(false)
    dropArea.subviews.forEach { $0.removeFromSuperview() }

    let devices = Array(menu.items.dropFirst())
    let rowHeight: CGFloat = 34
    let listHeight = CGFloat(devices.count) * rowHeight
    let visibleHeight = min(listHeight, rowHeight * 6)
    resize(width: 280, height: 42 + visibleHeight)
    let width = frame.width - 20

    fileSummary = menu.items[0].title
    let title = NSTextField(labelWithString: fileSummary)
    fileTitle = title
    title.toolTip = urls.map(\.lastPathComponent).joined(separator: "\n")
    title.font = hintFont
    title.lineBreakMode = .byTruncatingMiddle
    title.frame = NSRect(x: 8, y: frame.height - 30, width: frame.width - 20, height: 18)
    dropArea.addSubview(title)

    let list = NSView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight))
    let scroll = NSScrollView(frame: NSRect(x: 10, y: 8, width: width, height: visibleHeight))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = listHeight > visibleHeight
    scroll.scrollerStyle = .overlay
    scroll.documentView = list
    dropArea.addSubview(scroll)

    for (index, item) in devices.enumerated() {
      let row = MenuPreviewButton(title: item.title, target: self, action: #selector(selectDevice(_:)))
      row.menuItem = item
      row.frame = NSRect(x: 0, y: listHeight - CGFloat(index + 1) * rowHeight, width: width, height: rowHeight)
      row.isBordered = false
      row.alignment = .left
      row.wantsLayer = true
      row.layer?.cornerRadius = 5
      row.cell?.lineBreakMode = .byTruncatingMiddle
      row.setHovered(false)
      row.setAccessibilityLabel(item.toolTip ?? item.title)
      if let icon = item.image {
        let status = NSImageView(image: icon)
        status.frame = NSRect(x: width - 22, y: (rowHeight - 13) / 2, width: 13, height: 13)
        row.addSubview(status)
      }
      list.addSubview(row)
    }
    scroll.contentView.scroll(to: NSPoint(x: 0, y: listHeight - visibleHeight))
    scroll.reflectScrolledClipView(scroll.contentView)
    recalculateKeyViewLoop()

    if dismissalMonitors.isEmpty {
      let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
      dismissalMonitors = [
        NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
          self?.considerDismissal(event)
        },
        NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
          self?.considerDismissal(event)
          return event
        },
      ].compactMap { $0 }
    }
    DispatchQueue.main.async { [weak self] in
      if self?.choosingDevice == true { self?.makeKey() }
    }
  }

  func endDrag() {
    if choosingDevice { showDropArea(targeted: false) } else { dismiss() }
  }

  private func considerDismissal(_ event: NSEvent) {
    if event.window === self {
      outsidePress = nil
      return
    }
    let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    switch event.type {
    case .leftMouseDown:
      outsidePress = point
    case .leftMouseUp:
      defer { outsidePress = nil }
      if let start = outsidePress, abs(start.x - point.x) < 4, abs(start.y - point.y) < 4 {
        dismiss()
      }
    default:
      dismiss()
    }
  }

  private func highlightDropTarget(_ targeted: Bool) {
    dropArea.layer?.borderWidth = targeted ? 1 : 0
    dropArea.effectiveAppearance.performAsCurrentDrawingAppearance {
      dropArea.layer?.borderColor = Self.accent.cgColor
      dropArea.layer?.backgroundColor = targeted ? Self.accent.withAlphaComponent(0.14).cgColor : nil
    }
  }

  func dismiss() {
    choosingDevice = false
    pendingURLs.removeAll()
    pendingFiles.removeAll()
    outsidePress = nil
    unregisterDraggedTypes()
    orderOut(nil)
    dismissalMonitors.forEach(NSEvent.removeMonitor)
    dismissalMonitors.removeAll()
    dropArea.subviews.forEach { $0.removeFromSuperview() }
  }

  override func cancelOperation(_ sender: Any?) { dismiss() }

  @objc private func selectDevice(_ row: MenuPreviewButton) {
    guard let item = row.menuItem, let action = item.action else { return }
    dismiss()
    NSApp.sendAction(action, to: item.target, from: item)
  }

  private func hintWidth(_ text: String, padding: CGFloat) -> CGFloat {
    ceil(text.size(withAttributes: [.font: hintFont]).width) + iconSide + textGap + 2 * padding
  }

  private func resize(width: CGFloat, height: CGFloat) {
    let top = frame.maxY
    let size = NSSize(width: min(width, visibleScreen.width), height: height)
    let x = max(visibleScreen.minX, min(anchorX - size.width / 2, visibleScreen.maxX - size.width))
    dropArea.maskImage = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
      return true
    }
    setFrame(NSRect(x: x, y: top - height, width: size.width, height: size.height), display: true)
  }
}
