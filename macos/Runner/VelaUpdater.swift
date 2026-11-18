import Cocoa
import FlutterMacOS
import Sparkle

@MainActor
final class VelaUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
  private var channel: FlutterMethodChannel?
  private var updater: SPUUpdater?
  private var feedURL: String?
  private var busy = true
  private var installing = false
  private var pendingInstall: CheckedContinuation<SPUUserUpdateChoice, Never>?

  static func localFeed(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme == "http", url.host == "127.0.0.1",
      let port = url.port, (1...65535).contains(port), url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil,
      url.path.range(of: "^/[0-9a-f]{64}/appcast\\.xml$", options: .regularExpression) != nil
    else { return nil }
    return url
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "vela/update", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getUpdateDirectory":
      do {
        let directory = try FileManager.default.url(
          for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Vela/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        result(directory.path)
      } catch {
        result(FlutterError(code: "update_directory", message: error.localizedDescription, details: nil))
      }
    case "setBusy":
      guard let args = call.arguments as? [String: Any], let value = args["busy"] as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: "Missing activity state", details: nil))
        return
      }
      busy = value
      if !busy, let pendingInstall {
        self.pendingInstall = nil
        pendingInstall.resume(returning: .install)
      }
      result(nil)
    case "installDownloaded":
      guard let args = call.arguments as? [String: Any],
        let feed = args["feedUrl"] as? String, Self.localFeed(feed) != nil,
        let key = args["publicKey"] as? String,
        let bytes = Data(base64Encoded: key), bytes.count == 32,
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == key
      else {
        result(FlutterError(code: "update_config", message: "Invalid local update configuration", details: nil))
        return
      }
      guard !busy, !installing else {
        result(FlutterError(code: "busy", message: "Wait for active tasks to finish", details: nil))
        return
      }
      installing = true
      channel?.invokeMethod("prepareInstall", arguments: nil) { [weak self] response in
        guard let self else { return }
        guard response as? Bool == true, !self.busy else {
          self.installing = false
          let busy = self.busy || (response as? FlutterError)?.code == "busy"
          result(FlutterError(code: busy ? "busy" : "update_failed",
                              message: "Could not prepare to install", details: nil))
          return
        }
        self.feedURL = feed
        let updater = SPUUpdater(
          hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        do {
          self.updater = updater
          try updater.start()
          updater.checkForUpdates()
          result(nil)
        } catch {
          self.updater = nil
          self.installing = false
          result(FlutterError(code: "update_install", message: error.localizedDescription, details: nil))
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ status: String, message: String? = nil) {
    var event: [String: Any] = ["status": status]
    if let message { event["message"] = message }
    channel?.invokeMethod("updateEvent", arguments: event)
  }

  func feedURLString(for updater: SPUUpdater) -> String? { feedURL }

  func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
    SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { emit("installing") }

  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async
    -> SPUUserUpdateChoice
  {
    guard installing, !appcastItem.isInformationOnlyUpdate else { return .skip }
    return .install
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(_ error: Error) async { await showUpdaterError(error) }
  func showUpdaterError(_ error: Error) async {
    installing = false
    emit("error", message: error.localizedDescription)
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) { emit("installing") }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
  func showDownloadDidReceiveData(ofLength length: UInt64) {}
  func showDownloadDidStartExtractingUpdate() {}
  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
    guard installing else { return .skip }
    if !busy { return .install }
    return await withCheckedContinuation { pendingInstall = $0 }
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    emit("installing")
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}
  func dismissUpdateInstallation() { installing = false }
}
