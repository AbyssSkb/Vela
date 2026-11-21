import Cocoa

private final class MenuFileDropArea: NSVisualEffectView {
  var targetChanged: ((Bool) -> Void)?
  var acceptFiles: (([URL]) -> Bool)?

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard sender.draggingSourceOperationMask.contains(.copy),
          sender.draggingPasteboard.types?.contains(.fileURL) == true else { return [] }
    targetChanged?(true)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { targetChanged?(false) }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return acceptFiles?(urls) == true
  }
}

final class MenuFileDropPanel: NSPanel {
  private static let accent = NSColor(name: nil) { appearance in
    if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
      return NSColor(srgbRed: 0.73, green: 0.77, blue: 1, alpha: 1)
    }
    return NSColor(srgbRed: 0.33, green: 0.40, blue: 0.79, alpha: 1)
  }
  private let dropArea = MenuFileDropArea()
  private var icon: NSImage?
  private var hint = ""
  private var dropHint = ""
  private var choosingDevice = false
  private var dismissalMonitors: [Any] = []

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
    dropArea.registerForDraggedTypes([.fileURL])
    dropArea.targetChanged = { [weak self] targeted in self?.showDropArea(targeted: targeted) }
    dropArea.acceptFiles = { [weak self] urls in self?.acceptFiles?(urls) == true }
    contentView = dropArea
  }

  func showHint(under button: NSStatusBarButton, icon: NSImage?, hint: String, dropHint: String) -> Bool {
    if isVisible { return true }
    guard let window = button.window, let screen = window.screen else { return false }
    self.icon = icon
    self.hint = hint
    self.dropHint = dropHint
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let visible = screen.visibleFrame
    let width = min(280, visible.width)
    let x = max(visible.minX, min(anchor.midX - width / 2, visible.maxX - width))
    setFrame(NSRect(x: x, y: anchor.minY - 40, width: width, height: 36), display: false)
    showDropArea(targeted: false)
    orderFrontRegardless()
    return true
  }

  private func showDropArea(targeted: Bool) {
    guard !choosingDevice else { return }
    resize(height: targeted ? 96 : 36)
    dropArea.subviews.forEach { $0.removeFromSuperview() }
    dropArea.layer?.borderWidth = targeted ? 1 : 0
    dropArea.effectiveAppearance.performAsCurrentDrawingAppearance {
      dropArea.layer?.borderColor = Self.accent.cgColor
      dropArea.layer?.backgroundColor = targeted ? Self.accent.withAlphaComponent(0.14).cgColor : nil
    }
    let label = NSTextField(labelWithString: targeted ? dropHint : hint)
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let image = NSImageView()
    image.image = targeted ? NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil) : icon
    image.contentTintColor = targeted ? Self.accent : .labelColor
    let stack = NSStackView(views: [image, label])
    stack.orientation = targeted ? .vertical : .horizontal
    stack.alignment = targeted ? .centerX : .centerY
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    dropArea.addSubview(stack)
    NSLayoutConstraint.activate([
      image.widthAnchor.constraint(equalToConstant: targeted ? 24 : 18),
      image.heightAnchor.constraint(equalTo: image.widthAnchor),
      stack.centerXAnchor.constraint(equalTo: dropArea.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: dropArea.centerYAnchor),
    ])
  }

  func showDevices(_ menu: NSMenu) {
    choosingDevice = true
    dropArea.layer?.borderWidth = 0
    dropArea.layer?.backgroundColor = nil
    dropArea.subviews.forEach { $0.removeFromSuperview() }

    let devices = Array(menu.items.dropFirst())
    let rowHeight: CGFloat = 34
    let listHeight = CGFloat(devices.count) * rowHeight
    let visibleHeight = min(listHeight, rowHeight * 6)
    let width = frame.width - 20
    resize(height: 42 + visibleHeight)

    let title = NSTextField(labelWithString: menu.items[0].title)
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    title.lineBreakMode = .byTruncatingMiddle
    title.frame = NSRect(x: 14, y: frame.height - 30, width: frame.width - 28, height: 18)
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

    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    dismissalMonitors = [
      NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.dismiss() },
      NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
        if event.window !== self { self?.dismiss() }
        return event
      },
    ].compactMap { $0 }
    DispatchQueue.main.async { [weak self] in
      if self?.choosingDevice == true { self?.makeKey() }
    }
  }

  func endDrag() {
    if !choosingDevice { dismiss() }
  }

  func dismiss() {
    choosingDevice = false
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

  private func resize(height: CGFloat) {
    let top = frame.maxY
    let size = NSSize(width: frame.width, height: height)
    dropArea.maskImage = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
      return true
    }
    setFrame(NSRect(x: frame.minX, y: top - height, width: size.width, height: size.height), display: true)
  }
}
