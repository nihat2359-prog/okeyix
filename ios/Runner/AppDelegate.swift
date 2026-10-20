import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var comparisonShareChannel: FlutterMethodChannel?
  private var comparisonShareOpen = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.okeyix.game/comparison_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    comparisonShareChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "shareInviteWhatsApp" {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String, !text.isEmpty, text.count <= 4000 else {
          result(FlutterError(code: "INVALID_INVITE", message: "Invalid invitation text", details: nil)); return
        }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        guard let url = components.url else {
          result(FlutterError(code: "INVALID_INVITE", message: "Invalid invitation text", details: nil)); return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened { result(nil) }
          else { result(FlutterError(code: "WHATSAPP_UNAVAILABLE", message: "WhatsApp unavailable", details: nil)) }
        }
        return
      }
      guard call.method == "shareComparison" else { result(FlutterMethodNotImplemented); return }
      guard let self = self, !self.comparisonShareOpen,
            let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "SHARE_UNAVAILABLE", message: "Share is not available", details: nil)); return
      }
      let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
      // path_provider getTemporaryDirectory uses NSCachesDirectory on iOS.
      guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        result(FlutterError(code: "SHARE_UNAVAILABLE", message: "Cache unavailable", details: nil)); return
      }
      let allowed = caches.appendingPathComponent("okeyix_comparisons")
        .resolvingSymlinksInPath().standardizedFileURL
      guard file.deletingLastPathComponent() == allowed, file.pathExtension == "png",
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= 20_000_000, let image = UIImage(contentsOfFile: file.path) else {
        result(FlutterError(code: "INVALID_SHARE_FILE", message: "Image unavailable", details: nil)); return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController
              ?? self.window?.rootViewController else {
        result(FlutterError(code: "SHARE_UNAVAILABLE", message: "No visible view", details: nil)); return
      }
      while let top = presenter.presentedViewController { presenter = top }
      let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
      if let popover = activity.popoverPresentationController {
        popover.sourceView = presenter.view
        let x = (args["x"] as? NSNumber)?.doubleValue ?? Double(presenter.view.bounds.midX)
        let y = (args["y"] as? NSNumber)?.doubleValue ?? Double(presenter.view.bounds.midY)
        let width = (args["width"] as? NSNumber)?.doubleValue ?? 1
        let height = (args["height"] as? NSNumber)?.doubleValue ?? 1
        let proposed = CGRect(x: x, y: y, width: max(1, width), height: max(1, height))
        let anchor = presenter.view.bounds.intersection(proposed)
        popover.sourceRect = anchor.isNull ? CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1) : anchor
        popover.permittedArrowDirections = []
      }
      self.comparisonShareOpen = true
      activity.completionWithItemsHandler = { [weak self] _, _, _, error in
        self?.comparisonShareOpen = false
        if error != nil { result(FlutterError(code: "SHARE_FAILED", message: "Sharing failed", details: nil)) }
        else { result(nil) }
      }
      presenter.present(activity, animated: true)
    }
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
  return super.application(app, open: url, options: options)
}
}
