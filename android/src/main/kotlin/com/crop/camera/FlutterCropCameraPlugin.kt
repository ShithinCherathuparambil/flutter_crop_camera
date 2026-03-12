package com.crop.camera

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/** FlutterCropCameraPlugin */
class FlutterCropCameraPlugin :
        FlutterPlugin,
        MethodCallHandler,
        ActivityAware,
        PluginRegistry.ActivityResultListener,
        PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: Result? = null
    private var pendingStartCall: MethodCall? = null
    private var pendingStartResult: Result? = null
    private var requestingCameraPermission = false
    private val PICK_IMAGE_REQUEST_CODE = 1994
    private val CAMERA_PERMISSION_REQUEST_CODE = 1995
    private var context: Context? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var cameraEntry: TextureRegistry.SurfaceTextureEntry? = null
    private lateinit var messenger: BinaryMessenger
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var camera: Camera? = null
    private var isFrontCamera = false
    private var targetAspectRatio = AspectRatio.RATIO_4_3
    private var jpegQuality = 100
    private var isMultiPick = false
    private val MAX_CROP_PIXELS: Long = 20_000_000L

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_crop_camera")
        channel.setMethodCallHandler(this)
        textureRegistry = flutterPluginBinding.textureRegistry
        messenger = flutterPluginBinding.binaryMessenger
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startCamera" -> startCamera(call, result)
            "takePicture" -> takePicture(result)
            "pickImage" -> pickImage(result)
            "pickImages" -> pickImages(result)
            "cropImage" -> {
                val path = call.argument<String>("path")
                val x = call.argument<Int>("x")
                val y = call.argument<Int>("y")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                val flipX = call.argument<Boolean>("flipX") ?: false
                val quality = call.argument<Number>("quality")?.toInt() ?: 100

                if (path != null && x != null && y != null && width != null && height != null) {
                    cropImage(path, x, y, width, height, rotationDegrees, flipX, quality, result)
                } else {
                    result.error("INVALID_ARGS", "Missing crop arguments", null)
                }
            }
            "stopCamera" -> {
                stopCamera()
                result.success(null)
            }
            "switchCamera" -> switchCamera(result)
            "setZoom" -> {
                val zoom = call.argument<Double>("zoom")
                if (zoom != null) {
                    setZoom(zoom.toFloat(), result)
                } else {
                    result.error("INVALID_ARGS", "Missing zoom argument", null)
                }
            }
            "setFlashMode" -> {
                val mode = call.argument<String>("mode")
                if (mode != null) {
                    setFlashMode(mode, result)
                } else {
                    result.error("INVALID_ARGS", "Missing mode argument", null)
                }
            }
            "getMaxZoom" -> {
                val zoomState = camera?.cameraInfo?.zoomState?.value
                if (zoomState != null) {
                    result.success(zoomState.maxZoomRatio.toDouble())
                } else {
                    result.success(1.0)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startCamera(call: MethodCall, result: Result?) {
        val activity = activity
        if (activity == null) {
            result?.error("NO_ACTIVITY", "Activity is null", null)
            return
        }

        if (!hasCameraPermission(activity)) {
            pendingStartCall = call
            pendingStartResult = result
            if (!requestingCameraPermission) {
                requestingCameraPermission = true
                ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(android.Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_REQUEST_CODE
                )
            }
            return
        }

        // Parse arguments (only update if present)
        val facingArg = call.argument<String>("facing")
        if (facingArg != null) {
            isFrontCamera = (facingArg == "front")
        }

        android.util.Log.d(
                "FlutterCropCamera",
                "startCamera: facingArg=$facingArg, Final isFrontCamera=$isFrontCamera"
        )

        val ratioArg = call.argument<String>("aspectRatio")
        if (ratioArg != null) {
            targetAspectRatio =
                    when (ratioArg) {
                        "9:16", "16:9" -> AspectRatio.RATIO_16_9
                        else -> AspectRatio.RATIO_4_3 // 3:4, 4:3, 1:1
                    }
        }

        val qualityArg = call.argument<Number>("quality")
        if (qualityArg != null) {
            jpegQuality = (qualityArg.toDouble() * 100).toInt()
        }

        android.util.Log.d(
                "FlutterCropCamera",
                "startCamera: ratio=$targetAspectRatio, quality=$jpegQuality, front=$isFrontCamera"
        )

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)

        cameraProviderFuture.addListener(
                {
                    cameraProvider = cameraProviderFuture.get()

                    // Release old texture if exists
                    cameraEntry?.release()

                    cameraEntry = textureRegistry.createSurfaceTexture()
                    val surfaceTexture = cameraEntry!!.surfaceTexture()

                    // Set buffer size based on ratio - Increasing resolution for better preview
                    // quality
                    // Using 1080p base width
                    val width = if (targetAspectRatio == AspectRatio.RATIO_16_9) 1080 else 1440
                    val height = 1920
                    surfaceTexture.setDefaultBufferSize(width, height)

                    // Select Resolution Strategy
                    // Use HIGHEST_AVAILABLE_STRATEGY to get the best possible resolution for the
                    // given AspectRatio
                    val resolutionSelector =
                            ResolutionSelector.Builder()
                                    .setAspectRatioStrategy(
                                            if (targetAspectRatio == AspectRatio.RATIO_16_9)
                                                    AspectRatioStrategy
                                                            .RATIO_16_9_FALLBACK_AUTO_STRATEGY
                                            else
                                                    AspectRatioStrategy
                                                            .RATIO_4_3_FALLBACK_AUTO_STRATEGY
                                    )
                                    .setResolutionStrategy(
                                            ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY
                                    )
                                    .build()

                    val preview =
                            Preview.Builder().setResolutionSelector(resolutionSelector).build()

                    preview.setSurfaceProvider { request ->
                        val surface = Surface(surfaceTexture)
                        request.provideSurface(surface, cameraExecutor) { surface.release() }
                    }

                    val imageCaptureBuilder =
                            ImageCapture.Builder().setResolutionSelector(resolutionSelector)

                    // Only set JPEG quality if it's NOT 100 (Default/Original).
                    // Explicitly setting 100 might override some OEM optimizations or defaults.
                    if (jpegQuality < 100) {
                        imageCaptureBuilder.setJpegQuality(jpegQuality)
                    }

                    imageCapture = imageCaptureBuilder.build()

                    val cameraSelector =
                            if (isFrontCamera) CameraSelector.DEFAULT_FRONT_CAMERA
                            else CameraSelector.DEFAULT_BACK_CAMERA

                    android.util.Log.d(
                            "FlutterCropCamera",
                            "Binding camera. isFront=$isFrontCamera, Selector=$cameraSelector"
                    )

                    try {
                        cameraProvider?.unbindAll()
                        camera =
                                cameraProvider?.bindToLifecycle(
                                        activity as androidx.lifecycle.LifecycleOwner,
                                        cameraSelector,
                                        preview,
                                        imageCapture
                                )

                        // Log zoom capabilities
                        val zoomState = camera?.cameraInfo?.zoomState?.value
                        if (zoomState != null) {
                            android.util.Log.d(
                                    "FlutterCropCamera",
                                    "Camera bound. MinZoom: ${zoomState.minZoomRatio}, MaxZoom: ${zoomState.maxZoomRatio}"
                            )
                        }

                        result?.success(cameraEntry!!.id())
                    } catch (exc: Exception) {
                        result?.error("CAMERA_ERROR", "Use case binding failed", exc.message)
                    }
                },
                ContextCompat.getMainExecutor(activity)
        )
    }

    private fun hasCameraPermission(activity: Activity): Boolean {
        return ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun switchCamera(result: Result) {
        if (cameraProvider == null) {
            result.error("CAMERA_NOT_INIT", "Camera not initialized", null)
            return
        }
        isFrontCamera = !isFrontCamera
        // Reuse startCamera logic which uses existing isFrontCamera and targetAspectRatio
        val emptyCall = MethodCall("switchCamera", HashMap<String, Any>())
        startCamera(emptyCall, result)
    }

    private fun setZoom(zoom: Float, result: Result) {
        if (camera == null) {
            result.error("CAMERA_NOT_INIT", "Camera not initialized", null)
            return
        }
        val zoomState = camera!!.cameraInfo.zoomState.value
        if (zoomState != null) {
            val maxZoom = zoomState.maxZoomRatio
            val minZoom = zoomState.minZoomRatio
            android.util.Log.d(
                    "FlutterCropCamera",
                    "setZoom: requested=$zoom, min=$minZoom, max=$maxZoom"
            )
            val clamedZoom = zoom.coerceIn(minZoom, maxZoom)
            camera!!.cameraControl.setZoomRatio(clamedZoom)
            result.success(null)
        } else {
            result.error("ZOOM_ERROR", "Zoom not supported", null)
        }
    }

    private fun setFlashMode(mode: String, result: Result) {
        if (imageCapture == null) {
            result.error("CAMERA_NOT_INIT", "ImageCapture not initialized", null)
            return
        }

        val flashMode =
                when (mode) {
                    "on" -> ImageCapture.FLASH_MODE_ON
                    "auto" -> ImageCapture.FLASH_MODE_AUTO
                    else -> ImageCapture.FLASH_MODE_OFF
                }

        imageCapture?.flashMode = flashMode
        result.success(null)
    }

    private fun computeInSampleSize(width: Int, height: Int): Int {
        if (width <= 0 || height <= 0) return 1
        var sample = 1
        var w = width.toLong()
        var h = height.toLong()
        while (w * h > MAX_CROP_PIXELS) {
            sample *= 2
            w = width.toLong() / sample
            h = height.toLong() / sample
        }
        return sample
    }

    private fun takePicture(result: Result) {
        val ic =
                imageCapture
                        ?: return result.error(
                                "CAMERA_INIT_ERROR",
                                "ImageCapture not initialized",
                                null
                        )

        // Use OnImageCapturedCallback (in-memory) instead of OnImageSavedCallback (file).
        // CameraX delivers raw JPEG bytes directly — no temp file is created by CameraX,
        // so there is no race where the file disappears before cropImage reads it.
        // We write the bytes ourselves to filesDir, which Android never auto-cleans.
        ic.takePicture(
                ContextCompat.getMainExecutor(activity!!),
                object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(imageProxy: ImageProxy) {
                        try {
                            // Extract JPEG bytes from the ImageProxy plane.
                            val buffer = imageProxy.planes[0].buffer
                            val bytes = ByteArray(buffer.remaining())
                            buffer.get(bytes)
                            imageProxy.close()

                            // Write to filesDir — always available, never auto-cleaned.
                            val dir =
                                    context?.filesDir
                                            ?: activity?.filesDir
                                                    ?: return result.error(
                                                    "CAMERA_ERROR",
                                                    "Files dir unavailable",
                                                    null
                                            )
                            val file = File(dir, "capture_${System.currentTimeMillis()}.jpg")
                            file.writeBytes(bytes)
                            result.success(file.absolutePath)
                        } catch (e: Exception) {
                            result.error(
                                    "CAPTURE_ERROR",
                                    "Failed to process captured image: ${e.message}",
                                    null
                            )
                        }
                    }

                    override fun onError(exc: ImageCaptureException) {
                        result.error("CAPTURE_ERROR", "Photo capture failed: ${exc.message}", null)
                    }
                }
        )
    }

    private fun cropImage(
            path: String,
            x: Int,
            y: Int,
            width: Int,
            height: Int,
            userRotation: Int,
            flipX: Boolean,
            quality: Int,
            result: Result
    ) {
        cameraExecutor.execute {
            try {
                // 1. Decode original bitmap (downsample if extremely large to avoid OOM)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                val inSampleSize = computeInSampleSize(bounds.outWidth, bounds.outHeight)
                val decodeOptions =
                        BitmapFactory.Options().apply {
                            this.inSampleSize = inSampleSize
                            this.inPreferredConfig = Bitmap.Config.RGB_565
                        }
                val originalBitmap =
                        BitmapFactory.decodeFile(path, decodeOptions)
                                ?: throw Exception("Failed to decode image")

                val scaleDivisor = inSampleSize.toFloat()
                val scaledX = (x / scaleDivisor).roundToInt().coerceAtLeast(0)
                val scaledY = (y / scaleDivisor).roundToInt().coerceAtLeast(0)
                val scaledWidth = (width / scaleDivisor).roundToInt().coerceAtLeast(1)
                val scaledHeight = (height / scaleDivisor).roundToInt().coerceAtLeast(1)

                // 2. Read Exif orientation
                val exif = android.media.ExifInterface(path)
                val orientation =
                        exif.getAttributeInt(
                                android.media.ExifInterface.TAG_ORIENTATION,
                                android.media.ExifInterface.ORIENTATION_UNDEFINED
                        )

                // 3. Determine Exif rotation degrees
                val exifRotation =
                        when (orientation) {
                            android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90
                            android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180
                            android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270
                            else -> 0
                        }

                // 4. Calculate Total Rotation and Matrix
                val matrix = Matrix()
                // Apply Exif rotation
                if (exifRotation != 0) {
                    matrix.postRotate(exifRotation.toFloat())
                }
                // Apply User rotation
                if (userRotation != 0) {
                    matrix.postRotate(userRotation.toFloat())
                }
                // Apply Mirroring
                if (flipX) {
                    matrix.postScale(-1f, 1f)
                }

                // 5. Create Transformed Bitmap (Rotate/Flip FULL image first)
                // This effectively "normalizes" the image to what the user sees on screen before
                // cropping
                val transformedBitmap =
                        Bitmap.createBitmap(
                                originalBitmap,
                                0,
                                0,
                                originalBitmap.width,
                                originalBitmap.height,
                                matrix,
                                true
                        )

                if (originalBitmap != transformedBitmap) {
                    originalBitmap.recycle()
                }

                // 6. Validating Crop Coordinates against Transformed Bitmap
                // Ensure crop area is within bounds
                val safeX = scaledX.coerceIn(0, transformedBitmap.width - 1)
                val safeY = scaledY.coerceIn(0, transformedBitmap.height - 1)
                val safeWidth = scaledWidth.coerceAtMost(transformedBitmap.width - safeX)
                val safeHeight = scaledHeight.coerceAtMost(transformedBitmap.height - safeY)

                if (safeWidth <= 0 || safeHeight <= 0) {
                    Handler(Looper.getMainLooper()).post {
                        result.error(
                                "CROP_ERROR",
                                "Invalid crop dimensions after transformation",
                                null
                        )
                    }
                    return@execute
                }

                // 7. Crop
                val croppedBitmap =
                        Bitmap.createBitmap(transformedBitmap, safeX, safeY, safeWidth, safeHeight)

                // 8. Save cropped image
                val croppedDir = context?.cacheDir ?: activity?.cacheDir
                if (croppedDir == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("CROP_ERROR", "Cache dir unavailable", null)
                    }
                    return@execute
                }
                val croppedFile = File(croppedDir, "cropped_${java.util.UUID.randomUUID()}.jpg")
                val out = FileOutputStream(croppedFile)
                croppedBitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
                out.flush()
                out.close()

                // Recycle bitmaps
                if (transformedBitmap != croppedBitmap) {
                    transformedBitmap.recycle()
                }
                // croppedBitmap is not recycled here if we return it via channel? No, we save to
                // file.
                // We can recycle croppedBitmap after saving.
                croppedBitmap.recycle()

                Handler(Looper.getMainLooper()).post { result.success(croppedFile.absolutePath) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("CROP_ERROR", "Cropping failed: ${e.message}", null)
                }
            }
        }
    }

    private fun pickImage(result: Result) {
        val activity = activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }
        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "Image picker is already active", null)
            return
        }
        pendingResult = result
        isMultiPick = false

        val intent = Intent(Intent.ACTION_GET_CONTENT)
        intent.type = "image/*"
        activity.startActivityForResult(intent, PICK_IMAGE_REQUEST_CODE)
    }

    private fun pickImages(result: Result) {
        val activity = activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }
        if (pendingResult != null) {
            result.error("ALREADY_ACTIVE", "Image picker is already active", null)
            return
        }
        pendingResult = result
        isMultiPick = true

        val intent = Intent(Intent.ACTION_GET_CONTENT)
        intent.type = "image/*"
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        activity.startActivityForResult(intent, PICK_IMAGE_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == PICK_IMAGE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val context = context
                if (context != null) {
                    try {
                        val paths = ArrayList<String>()

                        // Handle ClipData (Multiple Images)
                        if (data.clipData != null) {
                            val count = data.clipData!!.itemCount
                            for (i in 0 until count) {
                                val uri = data.clipData!!.getItemAt(i).uri
                                val path = copyToTemp(context, uri, i)
                                if (path != null) paths.add(path)
                            }
                        }
                        // Handle Single URI
                        else if (data.data != null) {
                            val uri = data.data!!
                            val path = copyToTemp(context, uri, 0)
                            if (path != null) paths.add(path)
                        }

                        if (isMultiPick) {
                            pendingResult?.success(paths)
                        } else {
                            if (paths.isNotEmpty()) {
                                pendingResult?.success(paths[0])
                            } else {
                                pendingResult?.success(null)
                            }
                        }
                    } catch (e: Exception) {
                        pendingResult?.error(
                                "PICK_ERROR",
                                "Failed to copy image: ${e.message}",
                                null
                        )
                    }
                } else {
                    pendingResult?.error("CONTEXT_ERROR", "Context is null", null)
                }
            } else {
                // User cancelled or failed
                if (isMultiPick) {
                    pendingResult?.success(ArrayList<String>())
                } else {
                    pendingResult?.success(null)
                }
            }
            pendingResult = null
            return true
        }
        return false
    }

    override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<out String>,
            grantResults: IntArray
    ): Boolean {
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            requestingCameraPermission = false
            val granted =
                    grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                val call = pendingStartCall
                val result = pendingStartResult
                pendingStartCall = null
                pendingStartResult = null
                if (call != null) {
                    startCamera(call, result)
                } else {
                    result?.success(null)
                }
            } else {
                pendingStartResult?.error(
                        "CAMERA_PERMISSION",
                        "Camera permission denied",
                        null
                )
                pendingStartCall = null
                pendingStartResult = null
            }
            return true
        }
        return false
    }

    private fun copyToTemp(context: Context, uri: android.net.Uri, index: Int): String? {
        return try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val mimeType = context.contentResolver.getType(uri)
            val ext =
                    android.webkit.MimeTypeMap.getSingleton()
                            .getExtensionFromMimeType(mimeType)
                            ?: "jpg"
            val dir = context.cacheDir
            val file = File(dir, "picked_${System.currentTimeMillis()}_$index.$ext")
            FileOutputStream(file).use { outputStream ->
                inputStream.use { it.copyTo(outputStream) }
            }
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun stopCamera() {
        cameraProvider?.unbindAll()
        cameraEntry?.release()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }
}
