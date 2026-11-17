import AppKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: NSViewController {
  override func loadView() {
    let label = NSTextField(labelWithString: NSLocalizedString("Preparing…", comment: ""))
    label.alignment = .center
    label.frame = NSRect(x: 0, y: 0, width: 280, height: 64)
    view = label
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    Task { await handoff() }
  }

  private func handoff() async {
    let inbox: ShareInbox
    do {
      inbox = try ShareInbox.open()
    } catch {
      fail(error.localizedDescription)
      return
    }
    let stage = UUID().uuidString
    do {
      let directory = try inbox.prepare(stage: stage)
      var paths: [String] = []
      var text: String?
      for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
        for provider in item.attachments ?? [] {
          if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
            let url: URL?
            if let value = value as? URL {
              url = value
            } else if let value = value as? Data {
              url = URL(dataRepresentation: value, relativeTo: nil)
            } else if let value = value as? String {
              url = URL(string: value)
            } else {
              url = nil
            }
            guard let url = url, url.isFileURL else {
              throw NSError(
                domain: "Vela", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not read shared file."])
            }
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
              throw NSError(
                domain: "Vela", code: 5,
                userInfo: [
                  NSLocalizedDescriptionKey: NSLocalizedString(
                    "Folder sharing is not available yet.", comment: "")
                ])
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let slot = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            paths.append(destination.path)
          } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
          {
            let type =
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              ? UTType.image.identifier : UTType.movie.identifier
            let destination = try await stageRepresentation(
              provider, type: type, directory: directory)
            paths.append(destination.path)
          } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
            let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
          {
            text = url.absoluteString
          } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
            let value = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
              as? String
          {
            text = value
          }
        }
      }
      guard !paths.isEmpty || text != nil else { throw NSError(domain: "Vela", code: 1) }
      try inbox.publish(stage: stage, paths: paths, text: text)
      guard NSWorkspace.shared.open(URL(string: "vela-share://open")!) else {
        throw NSError(domain: "Vela", code: 2)
      }
      extensionContext?.completeRequest(returningItems: nil)
    } catch {
      inbox.cleanup(stage: stage)
      fail(error.localizedDescription)
    }
  }

  private func stageRepresentation(_ provider: NSItemProvider, type: String, directory: URL)
    async throws -> URL
  {
    let suggested = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        do {
          guard let url = url else { throw error ?? NSError(domain: "Vela", code: 3) }
          let slot = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
          try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
          let name = (suggested as NSString?)?.lastPathComponent ?? url.lastPathComponent
          let destination = slot.appendingPathComponent(name)
          try FileManager.default.copyItem(at: url, to: destination)
          continuation.resume(returning: destination)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func fail(_ message: String) {
    let error = NSError(domain: "Vela", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    extensionContext?.cancelRequest(withError: error)
  }
}
