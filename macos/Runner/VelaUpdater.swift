import Cocoa
import FlutterMacOS
import Sparkle

@MainActor
final class VelaUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
  private var channel: FlutterMethodChannel?
  private var updater: SPUUpdater?
  private var feedURL: String?
  private var busy = true
  private var driverActive = false
  private var installApproved = false
  private var quitting = false
  private var cancelDownload: (() -> Void)?
  private var ready: CheckedContinuation<SPUUserUpdateChoice, Never>?
  private var termination: (() -> Void)?
  private var version: String?
  private var expectedBytes: UInt64 = 0
  private var downloadedBytes: UInt64 = 0

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
    case "info":
      #if arch(arm64)
        let arch = "arm64"
      #else
        let arch = "x64"
      #endif
      result([
        "platform": "macos", "arch": arch,
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "0.0.0",
        "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
      ])
    case "configure":
      guard let args = call.arguments as? [String: Any],
        let feed = args["feedUrl"] as? String,
        let url = URL(string: feed), url.scheme == "https", url.host != nil,
        url.user == nil, url.password == nil,
        let key = args["publicKey"] as? String,
        let bytes = Data(base64Encoded: key), bytes.count == 32
      else {
        result(FlutterError(code: "update_config", message: "Invalid update configuration", details: nil))
        return
      }
      guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String == key else {
        emit("disabled", message: "This build has no matching update verification key")
        result(false)
        return
      }
      guard updater == nil else {
        result(feedURL == feed)
        return
      }
      feedURL = feed
      let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
      updater.automaticallyChecksForUpdates = false
      updater.automaticallyDownloadsUpdates = false
      do {
        try updater.start()
        self.updater = updater
        result(true)
      } catch {
        result(FlutterError(code: "update_config", message: error.localizedDescription, details: nil))
      }
    case "check":
      guard let updater else {
        result(FlutterError(code: "update_disabled", message: "Updates are not configured", details: nil))
        return
      }
      if updater.canCheckForUpdates { updater.checkForUpdates() }
      result(nil)
    case "setBusy":
      guard let args = call.arguments as? [String: Any], let value = args["busy"] as? Bool else {
        result(FlutterError(code: "update_busy", message: "Missing activity state", details: nil))
        return
      }
      busy = value
      if !busy, installApproved, let termination {
        self.termination = nil
        termination()
      }
      result(nil)
    case "install":
      guard !busy, ready != nil, !quitting else {
        result(FlutterError(code: "update_busy", message: "Wait for active tasks to finish", details: nil))
        return
      }
      emit("installing")
      channel?.invokeMethod("prepareInstall", arguments: nil) { [weak self] response in
        guard let self else { return }
        guard response as? Bool == true, !self.busy, !self.quitting, let ready = self.ready else {
          self.emit("ready")
          result(FlutterError(code: "update_busy", message: "Could not prepare to install", details: nil))
          return
        }
        self.installApproved = true
        self.ready = nil
        ready.resume(returning: .install)
        result(nil)
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ status: String, message: String? = nil) {
    var event: [String: Any] = ["status": status]
    if let version { event["version"] = version }
    if let message { event["message"] = message }
    if expectedBytes > 0 {
      event["bytes"] = downloadedBytes
      event["total"] = expectedBytes
    }
    channel?.invokeMethod("updateEvent", arguments: event)
  }

  func prepareToTerminate(_ completion: @escaping () -> Void) {
    if installApproved {
      if busy { termination = completion } else { completion() }
      return
    }
    guard driverActive else {
      completion()
      return
    }
    quitting = true
    termination = completion
    // Sparkle otherwise installs a staged update on ordinary quit, without per-update consent.
    if let ready {
      self.ready = nil
      ready.resume(returning: .skip)
    } else {
      cancelDownload?()
    }
  }

  func feedURLString(for updater: SPUUpdater) -> String? { feedURL }

  func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
    SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    driverActive = true
    cancelDownload = cancellation
    if quitting { cancellation() } else { emit("checking") }
  }

  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async
    -> SPUUserUpdateChoice
  {
    driverActive = true
    cancelDownload = nil
    version = appcastItem.displayVersionString
    if quitting { return state.stage == .installing ? .skip : .dismiss }
    guard !appcastItem.isInformationOnlyUpdate else {
      emit("error", message: "This release does not contain an installable update")
      return .dismiss
    }
    if state.stage == .installing { return await showReadyToInstallAndRelaunch() }
    emit("downloading")
    return .install
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(_ error: Error) async { emit("current") }
  func showUpdaterError(_ error: Error) async {
    installApproved = false
    if !quitting { emit("error", message: error.localizedDescription) }
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    driverActive = true
    cancelDownload = cancellation
    expectedBytes = 0
    downloadedBytes = 0
    if quitting { cancellation() } else { emit("downloading") }
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    expectedBytes = expectedContentLength
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    downloadedBytes += length
    emit("downloading")
  }

  func showDownloadDidStartExtractingUpdate() {
    driverActive = true
    cancelDownload = nil
  }

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
    driverActive = true
    if quitting { return .skip }
    emit("ready")
    return await withCheckedContinuation { ready = $0 }
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    emit("installing")
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}

  func dismissUpdateInstallation() {
    driverActive = false
    cancelDownload = nil
    let termination = termination
    self.termination = nil
    termination?()
  }

  func showUpdateInFocus() {
    if ready != nil { emit("ready") }
  }
}
