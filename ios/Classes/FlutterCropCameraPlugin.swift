import Flutter
import UIKit
import AVFoundation

public class FlutterCropCameraPlugin: NSObject, FlutterPlugin {
    var textureRegistry: FlutterTextureRegistry?
    var textureId: Int64?
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    var photoOutput: AVCapturePhotoOutput?
    var latestBuffer: CVPixelBuffer?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_crop_camera", binaryMessenger: registrar.messenger())
        let instance = FlutterCropCameraPlugin()
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            startCamera(result: result)
        case "takePicture":
            takePicture(result: result)
        case "cropImage":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String,
               let x = args["x"] as? Int,
               let y = args["y"] as? Int,
               let width = args["width"] as? Int,
               let height = args["height"] as? Int {
                cropImage(path: path, x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height), result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            }
        case "stopCamera":
            stopCamera()
            result(nil)
        case "setZoom":
            if let args = call.arguments as? [String: Any],
               let zoom = args["zoom"] as? Double {
                setZoom(zoom: CGFloat(zoom), result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing zoom argument", details: nil))
            }
        case "switchCamera":
             switchCamera(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var currentDevice: AVCaptureDevice?
    private var isFrontCamera = false

    func startCamera(result: @escaping FlutterResult) {
        let session = AVCaptureSession()
        session.sessionPreset = .photo // Changed to photo for better quality and zoom support
        
        let device = selectBestCamera(front: isFrontCamera)
        
        guard let validDevice = device,
              let input = try? AVCaptureDeviceInput(device: validDevice) else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Camera not available", details: nil))
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
            currentDevice = validDevice
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
        if let videoOutput = videoOutput, session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        photoOutput = AVCapturePhotoOutput()
        if let photoOutput = photoOutput, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        
        captureSession = session
        
        let textureId = textureRegistry?.register(self)
        self.textureId = textureId
        result(textureId)
    }
    
    private func selectBestCamera(front: Bool) -> AVCaptureDevice? {
        if front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            // Prefer Triple > DualWide > Wide
            if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                return device
            } else if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                return device
            } else {
                return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
        }
    }
    
    func switchCamera(result: @escaping FlutterResult) {
        isFrontCamera = !isFrontCamera
        stopCamera()
        startCamera(result: result)
    }
    
    func stopCamera() {
        captureSession?.stopRunning()
        if let textureId = textureId {
            textureRegistry?.unregisterTexture(textureId)
        }
        captureSession = nil
        textureId = nil
        currentDevice = nil
    }
    
    func takePicture(result: @escaping FlutterResult) {
        guard let photoOutput = photoOutput else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Photo output not initialized", details: nil))
            return
        }
        
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate(result: result)
        // Keep reference to delegate so it's not deallocated
        objc_setAssociatedObject(self, "PhotoCaptureDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
    
    func setZoom(zoom: CGFloat, result: @escaping FlutterResult) {
        guard let session = captureSession else {
             result(FlutterError(code: "CAMERA_ERROR", message: "Camera not initialized", details: nil))
             return
        }
        
        // Handle 0.5x zoom logic
        // If zoom < 1.0, we need to switch to Ultra Wide if available and current device is NOT Ultra Wide
        // If zoom >= 1.0, we need to switch to Main/Best if available and current device IS Ultra Wide
        
        let targetDevice: AVCaptureDevice?
        var targetZoomFactor = zoom
        
        if zoom < 1.0 {
            // User wants < 1.0x (e.g. 0.5x)
            // Try to find Ultra Wide camera
            if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
                targetDevice = ultraWide
                // 0.5x on Wide = 1.0x on Ultra Wide. 
                // Scaling: requested 0.5 -> 1.0. requested 0.6 -> 1.2
                targetZoomFactor = zoom * 2.0 
            } else {
                // No ultra wide, stay on current (likely won't support < 1.0)
                targetDevice = currentDevice
            }
        } else {
            // User wants >= 1.0x
            // Switch back to best main camera (Triple/Dual/Wide)
            targetDevice = selectBestCamera(front: isFrontCamera)
            targetZoomFactor = zoom
        }
        
        guard let device = targetDevice else {
             result(FlutterError(code: "ZOOM_ERROR", message: "No camera available", details: nil))
             return
        }
        
        // If we need to switch device
        if device != currentDevice {
             session.beginConfiguration()
             // Remove old input
             if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                 session.removeInput(currentInput)
             }
             
             // Add new input
             do {
                 let newInput = try AVCaptureDeviceInput(device: device)
                 if session.canAddInput(newInput) {
                     session.addInput(newInput)
                     currentDevice = device
                 } else {
                     // Rollback?
                     print("Failed to add new active device input")
                 }
             } catch {
                 print("Failed to create input for new device: \(error)")
             }
             session.commitConfiguration()
        }
        
        // Apply zoom to currentDevice (which might have just changed)
        do {
            try device.lockForConfiguration()
            let maxZoom = device.activeFormat.videoMaxZoomFactor
            let clampedZoom = max(1.0, min(targetZoomFactor, maxZoom))
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "ZOOM_ERROR", message: "Failed to lock device for configuration: \(error)", details: nil))
        }
    }
    
    func cropImage(path: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, result: @escaping FlutterResult) {
        guard let image = UIImage(contentsOfFile: path),
              let cgImage = image.cgImage else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to load image", details: nil))
            return
        }
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        guard let croppedCgImage = cgImage.cropping(to: rect) else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to crop image", details: nil))
            return
        }
        
        let croppedImage = UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
        
        guard let data = croppedImage.jpegData(compressionQuality: 1.0) else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to compress image", details: nil))
            return
        }
        
        let fileName = "cropped_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to save image: \(error)", details: nil))
        }
    }
}

extension FlutterCropCameraPlugin: FlutterTexture {
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

extension FlutterCropCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = pixelBuffer
        textureRegistry?.textureFrameAvailable(textureId ?? 0)
    }
}

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let result: FlutterResult
    
    init(result: @escaping FlutterResult) {
        self.result = result
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            result(FlutterError(code: "CAPTURE_ERROR", message: "No photo data", details: nil))
            return
        }
        
        let fileName = "clicked_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(code: "CAPTURE_ERROR", message: "Failed to save photo: \(error)", details: nil))
        }
    }
}
