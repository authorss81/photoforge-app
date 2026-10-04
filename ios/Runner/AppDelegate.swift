import Flutter
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  PHPickerViewControllerDelegate
{
  private var pickerResult: FlutterResult?
  private var pendingShared: [[String: Any]] = []

  /// Carries a FlutterResult through the C callback of
  /// UIImageWriteToSavedPhotosAlbum, which cannot capture Swift state.
  private final class SaveBox {
    let result: FlutterResult
    init(result: @escaping FlutterResult) {
      self.result = result
    }
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let decoder = FlutterMethodChannel(
      name: "dev.pixelforge/native_decoder",
      binaryMessenger: engineBridge.binaryMessenger
    )
    decoder.setMethodCallHandler { [weak self] call, result in
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

    let picker = FlutterMethodChannel(
      name: "dev.pixelforge/system_picker",
      binaryMessenger: engineBridge.binaryMessenger
    )
    picker.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickImages" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentPicker(result: result)
    }

    let shared = FlutterMethodChannel(
      name: "dev.pixelforge/shared_content",
      binaryMessenger: engineBridge.binaryMessenger
    )
    shared.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getSharedImages":
        result(self?.pendingShared ?? [])
        self?.pendingShared = []
      case "saveToGallery":
        guard let args = call.arguments as? [String: Any],
          let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data
        else {
          result(
            FlutterError(code: "ARG", message: "missing image bytes",
              details: nil))
          return
        }
        self?.saveToPhotos(bytes, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // "Open in PixelForge" lands a copy in Documents/Inbox. Read it now;
    // the sandbox may clean it before Dart gets around to asking.
    if let data = try? Data(contentsOf: url) {
      pendingShared.append([
        "name": url.lastPathComponent,
        "bytes": FlutterStandardTypedData(bytes: data),
      ])
      try? FileManager.default.removeItem(at: url)
    }
    return super.application(app, open: url, options: options)
  }

  private func saveToPhotos(_ bytes: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: bytes) else {
      result(
        FlutterError(code: "SAVE", message: "bytes are not an image",
          details: nil))
      return
    }
    UIImageWriteToSavedPhotosAlbum(
      image, self,
      #selector(savedPhoto(_:didFinishSavingWithError:contextInfo:)),
      Unmanaged.passRetained(SaveBox(result: result)).toOpaque())
  }

  @objc private func savedPhoto(
    _ image: UIImage,
    didFinishSavingWithError error: Error?,
    contextInfo: UnsafeRawPointer
  ) {
    let box = Unmanaged<SaveBox>.fromOpaque(contextInfo).takeRetainedValue()
    if let error = error {
      box.result(
        FlutterError(code: "SAVE", message: error.localizedDescription,
          details: nil))
    } else {
      box.result(nil)
    }
  }

  /// System photo picker. Returns only what the user selected and needs no
  /// photo-library permission, which is the entire point.
  private func presentPicker(result: @escaping FlutterResult) {
    guard pickerResult == nil else {
      result(
        FlutterError(code: "BUSY", message: "a pick is already in progress",
          details: nil))
      return
    }
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.selectionLimit = 20
    config.filter = .images
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    pickerResult = result
    guard let root = keyRootViewController() else {
      pickerResult = nil
      result(
        FlutterError(code: "PICK", message: "no view controller to present from",
          details: nil))
      return
    }
    root.present(picker, animated: true)
  }

  private func keyRootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController
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

  // MARK: - PHPickerViewControllerDelegate

  func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)
    guard let result = pickerResult else { return }
    pickerResult = nil
    guard !results.isEmpty else {
      result([])
      return
    }
    // Load every selection, then reply exactly once.
    let group = DispatchGroup()
    var items: [[String: Any]] = []
    let lock = NSLock()
    for r in results {
      group.enter()
      let name =
        r.itemProvider.suggestedName ?? "image"
      if r.itemProvider.hasItemConformingToTypeIdentifier(
        UTType.image.identifier)
      {
        r.itemProvider.loadFileRepresentation(
          forTypeIdentifier: UTType.image.identifier
        ) { url, _ in
          defer { group.leave() }
          guard let url = url,
            let data = try? Data(contentsOf: url)
          else {
            return
          }
          lock.lock()
          items.append([
            "name": name,
            "bytes": FlutterStandardTypedData(bytes: data),
          ])
          lock.unlock()
        }
      } else {
        group.leave()
      }
    }
    group.notify(queue: .main) {
      result(items)
    }
  }
}
