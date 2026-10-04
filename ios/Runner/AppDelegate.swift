import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "dev.pixelforge/native_decoder",
      binaryMessenger: engineBridge.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "decodeImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(
          FlutterError(
            code: "ARG", message: "missing image bytes", details: nil))
        return
      }
      guard let png = self?.decodeToPng(bytes.data) else {
        result(
          FlutterError(
            code: "DECODE", message: "ImageIO could not decode this file",
            details: nil))
        return
      }
      result(FlutterStandardTypedData(bytes: png))
    }
  }

  /// Full-resolution PNG via ImageIO, with the EXIF orientation baked in by
  /// drawing through a UIImage. Returning PNG means the Dart pipeline needs
  /// no pixel-format negotiation.
  private func decodeToPng(_ bytes: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      return nil
    }
    let oriented = UIImage(
      cgImage: cg, scale: 1.0, orientation: orientationOf(source))
    UIGraphicsBeginImageContextWithOptions(oriented.size, false, 1.0)
    oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
    let baked = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return baked?.pngData()
  }

  private func orientationOf(_ source: CGImageSource) -> UIImage.Orientation {
    guard
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let raw = props[kCGImagePropertyOrientation] as? UInt32
    else {
      return .up
    }
    // EXIF orientation 1-8.
    switch raw {
    case 2: return .upMirrored
    case 3: return .down
    case 4: return .downMirrored
    case 5: return .leftMirrored
    case 6: return .right
    case 7: return .rightMirrored
    case 8: return .left
    default: return .up
    }
  }
}
