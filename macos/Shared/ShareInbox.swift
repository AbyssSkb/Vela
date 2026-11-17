import Darwin
import Foundation

struct ShareInbox {
  let root: URL

  static func open() throws -> ShareInbox {
    guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
      throw NSError(
        domain: "Vela", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unable to locate user home"])
    }
    let root = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
      .appendingPathComponent("Library/Application Support/Vela/Shares", isDirectory: true)
    return ShareInbox(root: root)
  }

  func prepare(stage: String) throws -> URL {
    guard UUID(uuidString: stage) != nil else { throw NSError(domain: "Vela", code: 1) }
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    let directory = root.appendingPathComponent(stage, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return directory
  }

  func publish(stage: String, paths: [String], text: String?) throws {
    var value: [String: Any] = ["stage": stage]
    if !paths.isEmpty {
      value["paths"] = paths
    } else if let text {
      value["text"] = text
    }
    let file = root.appendingPathComponent("\(stage).json")
    let data = try JSONSerialization.data(withJSONObject: value)
    _ = try Self.decodeManifest(data, file: file, root: root)
    try data.write(to: file, options: .atomic)
  }

  func take() throws -> [String: Any]? {
    let entries =
      (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    guard let file = entries.filter({ $0.pathExtension == "json" }).sorted(by: {
      $0.lastPathComponent < $1.lastPathComponent
    }).first else { return nil }
    let value = try Self.decodeManifest(Data(contentsOf: file), file: file, root: root)
    // Taking consumes the manifest; Dart releases the stage after sending or abandoning it.
    try FileManager.default.removeItem(at: file)
    return value
  }

  func cleanup(stage: String) {
    guard UUID(uuidString: stage) != nil else { return }
    try? FileManager.default.removeItem(at: root.appendingPathComponent(stage, isDirectory: true))
  }

  static func decodeManifest(_ data: Data, file: URL, root: URL) throws -> [String: Any] {
    guard var value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let stage = value["stage"] as? String, UUID(uuidString: stage) != nil,
      file.deletingPathExtension().lastPathComponent == stage
    else { throw NSError(domain: "Vela", code: 1) }
    if let encodedPaths = value["paths"] as? String {
      value["paths"] = try JSONDecoder().decode([String].self, from: Data(encodedPaths.utf8))
    }
    if let rawPaths = value["paths"] {
      let prefix =
        root.appendingPathComponent(stage, isDirectory: true).resolvingSymlinksInPath().path + "/"
      guard let paths = rawPaths as? [String], !paths.isEmpty, paths.count <= 100,
        paths.allSatisfy({
          URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(prefix)
        })
      else { throw NSError(domain: "Vela", code: 2) }
    } else if value["text"] as? String == nil {
      throw NSError(domain: "Vela", code: 3)
    }
    return value
  }
}
