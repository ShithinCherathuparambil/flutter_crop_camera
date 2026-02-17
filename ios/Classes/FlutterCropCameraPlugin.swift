import Flutter
import UIKit
import AVFoundation
import PhotosUI



public class FlutterCropCameraPlugin: NSObject, FlutterPlugin, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
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
        case "pickImage":
            pickImage(result: result)
        case "pickImages":
            pickImages(result: result)
        case "cropImage":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String,
               let x = args["x"] as? Int,
               let y = args["y"] as? Int,
               let width = args["width"] as? Int,
               let height = args["height"] as? Int {
                let rotationDegrees = args["rotationDegrees"] as? Int ?? 0
                let flipX = args["flipX"] as? Bool ?? false
                cropImage(path: path, x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height), rotationDegrees: rotationDegrees, flipX: flipX, result: result)
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
        case "setFlashMode":
            if let args = call.arguments as? [String: Any],
               let mode = args["mode"] as? String {
                setFlashMode(mode: mode, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing flash mode argument", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var currentDevice: AVCaptureDevice?
    private var isFrontCamera = false
    private var isMultiPick = false

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
            
            // Set video orientation to portrait to match device orientation
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
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
    
    func setFlashMode(mode: String, result: @escaping FlutterResult) {
        guard let device = currentDevice else {
            result(FlutterError(code: "CAMERA_ERROR", message: "Camera not initialized", details: nil))
            return
        }
        
        // Check if device has flash
        guard device.hasFlash else {
            // No flash available, just return success silently
            result(nil)
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            switch mode {
            case "off":
                if device.isFlashModeSupported(.off) {
                    device.flashMode = .off
                }
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            case "on":
                if device.isFlashModeSupported(.on) {
                    device.flashMode = .on
                }
            case "auto":
                if device.isFlashModeSupported(.auto) {
                    device.flashMode = .auto
                }
            case "torch":
                if device.isTorchModeSupported(.on) {
                    device.torchMode = .on
                }
            default:
                device.unlockForConfiguration()
                result(FlutterError(code: "INVALID_FLASH_MODE", message: "Invalid flash mode: \(mode)", details: nil))
                return
            }
            
            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "FLASH_ERROR", message: "Failed to set flash mode: \(error)", details: nil))
        }
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
    
    func cropImage(path: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotationDegrees: Int, flipX: Bool, result: @escaping FlutterResult) {
        guard let image = UIImage(contentsOfFile: path) else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to load image", details: nil))
            return
        }
        
        // Step 1: Normalize EXIF orientation first (like Android does)
        // This converts the image to .up orientation by applying the EXIF rotation
        let normalizedImage: UIImage
        if image.imageOrientation == .up {
            normalizedImage = image
        } else {
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        }
        
        // Step 2: Apply user transformations (rotation + flip) to the normalized image
        var transformedImage = normalizedImage
        
        if rotationDegrees != 0 || flipX {
            // Calculate size after user rotation
            let radians = CGFloat(rotationDegrees) * .pi / 180.0
            let rotatedSize: CGSize
            
            if rotationDegrees == 90 || rotationDegrees == 270 {
                rotatedSize = CGSize(width: normalizedImage.size.height, height: normalizedImage.size.width)
            } else {
                rotatedSize = normalizedImage.size
            }
            
            // Create graphics context for user transformation
            UIGraphicsBeginImageContextWithOptions(rotatedSize, false, normalizedImage.scale)
            guard let context = UIGraphicsGetCurrentContext() else {
                result(FlutterError(code: "CROP_ERROR", message: "Failed to create graphics context", details: nil))
                return
            }
            
            // Move origin to center
            context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            
            // Apply user rotation
            context.rotate(by: radians)
            
            // Apply flip if needed
            if flipX {
                context.scaleBy(x: -1, y: 1)
            }
            
            // Draw the normalized image centered
            normalizedImage.draw(in: CGRect(
                x: -normalizedImage.size.width / 2,
                y: -normalizedImage.size.height / 2,
                width: normalizedImage.size.width,
                height: normalizedImage.size.height
            ))
            
            transformedImage = UIGraphicsGetImageFromCurrentImageContext() ?? normalizedImage
            UIGraphicsEndImageContext()
        }
        
        // Step 3: Crop the transformed image
        guard let transformedCgImage = transformedImage.cgImage else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to get CGImage", details: nil))
            return
        }
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        guard let croppedCgImage = transformedCgImage.cropping(to: rect) else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to crop image", details: nil))
            return
        }
        
        let croppedImage = UIImage(cgImage: croppedCgImage, scale: transformedImage.scale, orientation: .up)
        
        // Step 4: Save the cropped image
        guard let data = croppedImage.jpegData(compressionQuality: 1.0) else {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to compress image", details: nil))
            return
        }
        
        let fileName = "cropped_\(UUID().uuidString).jpg"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(code: "CROP_ERROR", message: "Failed to save image: \(error)", details: nil))
        }
    }

    private struct AssociatedKeys {
        static var pickImageResult = "pickImageResult"
        static var pickImagesResult = "pickImagesResult"
    }

    func pickImages(result: @escaping FlutterResult) {
        if #available(iOS 14, *) {
            // Use a safe UI thread call
            DispatchQueue.main.async {
                var configuration = PHPickerConfiguration()
                configuration.selectionLimit = 0 // 0 means no limit (multiple selection)
                configuration.filter = .images
                
                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = self
                
                // Store result for delegate callback
                objc_setAssociatedObject(self, &AssociatedKeys.pickImagesResult, result, .OBJC_ASSOCIATION_COPY)
                self.isMultiPick = true
                
                // Find top view controller to present
                if let rootVC = UIApplication.shared.keyWindow?.rootViewController ?? UIApplication.shared.delegate?.window??.rootViewController {
                    var topVC = rootVC
                    while let presentedVC = topVC.presentedViewController {
                        topVC = presentedVC
                    }
                    topVC.present(picker, animated: true, completion: nil)
                } else {
                     result(FlutterError(code: "PICK_ERROR", message: "No view controller to present picker", details: nil))
                }
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED_VERSION", message: "Multi-image picker requires iOS 14+", details: nil))
        }
    }

    func pickImage(result: @escaping FlutterResult) {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            result(FlutterError(code: "PICK_ERROR", message: "Photo library not available", details: nil))
            return
        }
        
        // Use a safe UI thread call
        DispatchQueue.main.async {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            
            // Store result for delegate callback
            objc_setAssociatedObject(self, &AssociatedKeys.pickImageResult, result, .OBJC_ASSOCIATION_COPY)
            
            // Find top view controller to present
            if let rootVC = UIApplication.shared.keyWindow?.rootViewController ?? UIApplication.shared.delegate?.window??.rootViewController {
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController {
                    topVC = presentedVC
                }
                topVC.present(picker, animated: true, completion: nil)
            } else {
                 result(FlutterError(code: "PICK_ERROR", message: "No view controller to present picker", details: nil))
            }
        }
    }

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let result = objc_getAssociatedObject(self, &AssociatedKeys.pickImageResult) as? FlutterResult else { return }
        
        guard let image = info[.originalImage] as? UIImage else {
            result(FlutterError(code: "PICK_ERROR", message: "Failed to pick image", details: nil))
            return
        }
        
        guard let data = image.jpegData(compressionQuality: 1.0) else {
            result(FlutterError(code: "PICK_ERROR", message: "Failed to compress captured image", details: nil))
            return
        }
        
        let fileName = "picked_\(Int(Date().timeIntervalSince1970)).jpg"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            result(fileURL.path)
        } catch {
            result(FlutterError(code: "PICK_ERROR", message: "Failed to save picked image: \(error)", details: nil))
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
        if let result = objc_getAssociatedObject(self, &AssociatedKeys.pickImageResult) as? FlutterResult {
            result(nil)
        }
    }

    // MARK: - PHPickerViewControllerDelegate
}

@available(iOS 14, *)
extension FlutterCropCameraPlugin: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        
        guard let result = objc_getAssociatedObject(self, &AssociatedKeys.pickImagesResult) as? FlutterResult else { return }
        
        if results.isEmpty {
            result([])
            return
        }
        
        var paths: [String] = []
        let dispatchGroup = DispatchGroup()
        
        for (index, item) in results.enumerated() {
            dispatchGroup.enter()
            
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { (object, error) in
                    if let image = object as? UIImage {
                         if let data = image.jpegData(compressionQuality: 1.0) {
                             let fileName = "picked_\(Int(Date().timeIntervalSince1970))_\(index).jpg"
                             let tempDir = FileManager.default.temporaryDirectory
                             let fileURL = tempDir.appendingPathComponent(fileName)
                             
                             do {
                                 try data.write(to: fileURL)
                                 // We need to synchronize access to paths array if we weren't on main thread,
                                 // but loadObject's completion handler might be on background thread.
                                 // Let's use a lock or perform on main queue.
                                 // Actually simpler: just append and handle order later?
                                 // Or wait properly.
                                 DispatchQueue.main.async {
                                     paths.append(fileURL.path)
                                     dispatchGroup.leave()
                                 }
                             } catch {
                                 print("Error saving image: \(error)")
                                 dispatchGroup.leave()
                             }
                         } else {
                             dispatchGroup.leave()
                         }
                    } else {
                        dispatchGroup.leave()
                    }
                }
            } else {
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            result(paths)
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

