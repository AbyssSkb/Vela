import Foundation

final class ReceiveDirectoryAccess {
  private let defaults: UserDefaults
  private var directories: [URL] = []
  private let bookmarksKey = "vela_save_directory_bookmarks"
  private let activeKey = "vela_save_directory"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    for data in defaults.array(forKey: bookmarksKey) as? [Data] ?? [] {
      var stale = false
      if let url = try? URL(
        resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
        bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource()
      {
        directories.append(url)
      }
    }
  }

  deinit {
    for directory in directories { directory.stopAccessingSecurityScopedResource() }
  }

  func currentDirectory() throws -> URL {
    if let path = defaults.string(forKey: activeKey) {
      guard let url = directories.first(where: { $0.path == path }) else {
        throw NSError(
          domain: "VelaStorage", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "The selected folder is unavailable"])
      }
      return url
    }
    guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    else { throw NSError(domain: "VelaStorage", code: 2) }
    return url
  }

  func location() throws -> [String: Any] {
    let path = try currentDirectory().path
    return [
      "displayPath": path,
      "directoryPath": path,
      "isDefault": defaults.string(forKey: activeKey) == nil,
    ]
  }

  func select(_ url: URL) throws {
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    if !directories.contains(where: { $0.path == url.path }) {
      guard url.startAccessingSecurityScopedResource() else {
        throw NSError(domain: "VelaStorage", code: 3)
      }
      directories.append(url)
      var bookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
      bookmarks.append(bookmark)
      defaults.set(bookmarks, forKey: bookmarksKey)
    }
    defaults.set(url.path, forKey: activeKey)
  }

  func reset() {
    defaults.removeObject(forKey: activeKey)
  }
}
