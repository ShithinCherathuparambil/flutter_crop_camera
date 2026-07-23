import FlutterMacOS
import Foundation
import AVFoundation

// MARK: - FlutterCropCameraPlugin

/// macOS implementation of the flutter_crop_camera method channel.
///
/// Handles camera preview (via FlutterTexture + AVCaptureSession) and
/// photo capture. Gallery picking and image cropping are handled entirely
/// in Dart using file_selector and dart:ui respectively.
public class FlutterCropCameraPlugin: NSObject, FlutterPlugin {

    // MARK: Properties

    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var latestBuffer: CVPixelBuffer?
    private var currentDevice: AVCaptureDevice?
    private var isFrontCamera = false

    // MARK: Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_crop_camera",
            binaryMessenger: registrar.messenger
        )
        let instance = FlutterCropCameraPlugin()
        instance.textureRegistry = registrar.textures
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: Method channel dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)

        case "startCamera":
            startCamera(call: call, result: result)

        case "stopCamera":
            tearDownCameraSession()
            result(nil)

        case "switchCamera":
            isFrontCamera = !isFrontCamera
            startCamera(call: call, result: result)

        case "takePicture":
            takePicture(result: result)

        case "getMaxZoom":
            // macOS webcams don't expose a zoom API
            result(Double(1.0))

        case "setZoom":
            // Silently no-op — webcams don't support zoom
            result(nil)

        case "setFlashMode":
            // Silently no-op — webcams don't have flash
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Camera lifecycle

    private func startCamera(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        // Honour explicit frontCamera flag from Dart
        if let front = args?["frontCamera"] as? Bool {
            isFrontCamera = front
        }

        // Tear down any pre-existing session
        tearDownCameraSession()

        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // Pick best available camera device
        guard let device = selectCamera(front: isFrontCamera) else {
            result(FlutterError(
                code: "CAMERA_UNAVAILABLE",
                message: "No camera found. Please connect a FaceTime HD or USB camera.",
                details: nil
            ))
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            result(FlutterError(
                code: "CAMERA_INPUT_ERROR",
                message: "Could not create camera input.",
                details: nil
            ))
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
            currentDevice = device
        }

        // ── Video output → FlutterTexture ──────────────────────────────────
        let vo = AVCaptureVideoDataOutput()
        vo.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        vo.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.flutter_crop_camera.mac"))
        if session.canAddOutput(vo) {
            session.addOutput(vo)
            if let conn = vo.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
        videoOutput = vo

        // ── Photo output → still capture ───────────────────────────────────
        let po = AVCapturePhotoOutput()
        if session.canAddOutput(po) {
            session.addOutput(po)
        }
        photoOutput = po

        // Start on background queue — never block the main/UI thread
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        captureSession = session

        // Register the texture with Flutter and return its ID
        let tid = textureRegistry?.register(self) ?? 0
        textureId = tid
        result(tid)
    }

    /// Stops and tears down the current AVCaptureSession, if any.
    private func tearDownCameraSession() {
        captureSession?.stopRunning()
        if let tid = textureId {
            textureRegistry?.unregisterTexture(tid)
        }
        captureSession  = nil
        videoOutput     = nil
        photoOutput     = nil
        textureId       = nil
        currentDevice   = nil
        latestBuffer    = nil
    }

    // MARK: Camera selection

    /// Returns the best available camera for the requested position.
    ///
    /// - On Macs with a built-in camera (e.g. FaceTime HD) the position is
    ///   `.front` on most models.
    /// - External USB webcams usually appear as `.unspecified`.
    private func selectCamera(front: Bool) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = front ? .front : .back

        let targeted = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        if let d = targeted.devices.first { return d }

        // Fall back to any attached camera (covers USB webcams)
        let any = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return any.devices.first ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: Photo capture

    private func takePicture(result: @escaping FlutterResult) {
        guard let photoOutput = photoOutput else {
            result(FlutterError(
                code: "CAMERA_NOT_INITIALIZED",
                message: "startCamera() must be called before takePicture().",
                details: nil
            ))
            return
        }

        let settings = AVCapturePhotoSettings()
        let delegate = MacPhotoCaptureDelegate(result: result)
        // Retain via associated object so it is not deallocated before callback
        objc_setAssociatedObject(
            self,
            "photo_delegate_\(arc4random())",
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - FlutterTexture (pixel buffer feed)

extension FlutterCropCameraPlugin: FlutterTexture {
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FlutterCropCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = pixelBuffer
        // Tell Flutter a new frame is available so it renders the texture
        textureRegistry?.textureFrameAvailable(textureId ?? 0)
    }
}

// MARK: - MacPhotoCaptureDelegate

/// Receives still-image data from AVCapturePhotoOutput and writes a JPEG to
/// the user's caches directory, returning the file path via FlutterResult.
private class MacPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    let result: FlutterResult

    init(result: @escaping FlutterResult) {
        self.result = result
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            result(FlutterError(
                code: "CAPTURE_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            result(FlutterError(
                code: "CAPTURE_FAILED",
                message: "Photo data representation was nil.",
                details: nil
            ))
            return
        }

        // Write to caches directory — reliable location that doesn't need entitlements
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let fileName  = "captured_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL   = cacheDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(
                code: "CAPTURE_FAILED",
                message: "Failed to save photo: \(error.localizedDescription)",
                details: nil
            ))
        }
    }
}
