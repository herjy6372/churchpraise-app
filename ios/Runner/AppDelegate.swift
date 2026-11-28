import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?
  /// 지금 열린 문서 선택 창의 용도
  private enum PickerMode { case score, saveBackup, pickBackup }
  private var pickerMode: PickerMode = .score

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "com.terablack.churchpraise/file_picker",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "pickScoreFile":
        if self.pendingResult != nil {
          result(FlutterError(code: "ALREADY_ACTIVE", message: "Picker already active", details: nil))
          return
        }
        self.pendingResult = result
        self.pickerMode = .score
        DispatchQueue.main.async {
          let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
          self.present(picker, result: result)
        }
      case "getTempDir":
        result(NSTemporaryDirectory())
      case "saveBackupFile":
        if self.pendingResult != nil {
          result(FlutterError(code: "ALREADY_ACTIVE", message: "Picker already active", details: nil))
          return
        }
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "NO_FILE", message: "Backup file not found", details: nil))
          return
        }
        self.pendingResult = result
        self.pickerMode = .saveBackup
        DispatchQueue.main.async {
          let picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
          self.present(picker, result: result)
        }
      case "pickBackupFile":
        if self.pendingResult != nil {
          result(FlutterError(code: "ALREADY_ACTIVE", message: "Picker already active", details: nil))
          return
        }
        self.pendingResult = result
        self.pickerMode = .pickBackup
        DispatchQueue.main.async {
          let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .data], asCopy: true)
          self.present(picker, result: result)
        }
      case "getScoresDir":
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("custom_scores")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func present(_ picker: UIDocumentPickerViewController, result: @escaping FlutterResult) {
    picker.delegate = self
    picker.allowsMultipleSelection = false
    if let rootVC = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController {
      rootVC.present(picker, animated: true, completion: nil)
    } else {
      pendingResult = nil
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Cannot find root view controller", details: nil))
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let res = pendingResult else { return }
    pendingResult = nil
    switch pickerMode {
    case .saveBackup:
      res(true)
      return
    case .pickBackup:
      guard let src = urls.first else { res(nil); return }
      do {
        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("import_backup_\(Int(Date().timeIntervalSince1970 * 1000)).zip")
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        res(dest.path)
      } catch {
        res(FlutterError(code: "PICK_ERROR", message: error.localizedDescription, details: nil))
      }
      return
    case .score:
      break
    }
    guard let srcUrl = urls.first else {
      res(nil)
      return
    }
    do {
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let dir = docs.appendingPathComponent("custom_scores")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileName = srcUrl.lastPathComponent
      let ext = srcUrl.pathExtension.lowercased()
      let safeExt = ext.isEmpty ? "" : ".\(ext)"
      let destUrl = dir.appendingPathComponent("score_\(Int(Date().timeIntervalSince1970 * 1000))\(safeExt)")
      if FileManager.default.fileExists(atPath: destUrl.path) {
        try FileManager.default.removeItem(at: destUrl)
      }
      try FileManager.default.copyItem(at: srcUrl, to: destUrl)
      res([
        "path": destUrl.path,
        "name": fileName
      ])
    } catch {
      res(FlutterError(code: "PICK_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let res = pendingResult else { return }
    pendingResult = nil
    res(pickerMode == .saveBackup ? false : nil)
  }
}

