import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?

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
        DispatchQueue.main.async {
          let picker: UIDocumentPickerViewController
          if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
          } else {
            picker = UIDocumentPickerViewController(documentTypes: ["com.adobe.pdf", "public.image"], in: .import)
          }
          picker.delegate = self
          picker.allowsMultipleSelection = false
          if let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.present(picker, animated: true, completion: nil)
          } else {
            self.pendingResult = nil
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Cannot find root view controller", details: nil))
          }
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

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let res = pendingResult else { return }
    pendingResult = nil
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
    res(nil)
  }
}

