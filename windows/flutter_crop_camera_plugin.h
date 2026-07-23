#ifndef FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_

// Standard library
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include <functional>
#include <optional>
#include <atomic>

// Windows / WinRT
#include <windows.h>
#include <unknwn.h>

// Disable warnings that C++/WinRT generates on MSVC
#pragma warning(push)
#pragma warning(disable: 4265 4625 4626 5026 5027)
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Capture.h>
#include <winrt/Windows.Media.Capture.Frames.h>
#include <winrt/Windows.Media.Devices.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Devices.Enumeration.h>
#pragma warning(pop)

// Flutter
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

namespace flutter_crop_camera {

/// Pixel buffer populated by the WinRT frame reader and consumed by Flutter.
struct CameraPixelBuffer {
    std::vector<uint8_t> data;
    int32_t width  = 0;
    int32_t height = 0;
};

/// Windows implementation of the flutter_crop_camera plugin.
///
/// Responsibilities:
///   - startCamera  → enumerate video devices, init MediaCapture, start
///                    MediaFrameReader, register FlutterDesktopPixelBuffer
///   - stopCamera   → stop frame reader, close MediaCapture, unregister texture
///   - switchCamera → cycle to next device index, restart pipeline
///   - takePicture  → capture to temp JPEG file, return path
///   - getMaxZoom / setZoom / setFlashMode → no-op / return 1.0
///
/// Gallery picking and crop are handled entirely in Dart (file_selector +
/// dart:ui) so this class has no involvement in those operations.
class FlutterCropCameraPlugin final : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlutterCropCameraPlugin(
      flutter::PluginRegistrarWindows* registrar,
      flutter::TextureRegistrar*       texture_registrar);

  ~FlutterCropCameraPlugin() override;

  // Disallow copy / move
  FlutterCropCameraPlugin(const FlutterCropCameraPlugin&) = delete;
  FlutterCropCameraPlugin& operator=(const FlutterCropCameraPlugin&) = delete;

 private:
  // ── Method channel dispatcher ─────────────────────────────────────────────
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── Camera operations ─────────────────────────────────────────────────────
  winrt::Windows::Foundation::IAsyncAction StartCameraAsync(
      bool prefer_front,
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  winrt::Windows::Foundation::IAsyncAction StopCameraAsync();

  winrt::Windows::Foundation::IAsyncAction TakePictureAsync(
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── Texture helpers ───────────────────────────────────────────────────────
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);

  // ── State ─────────────────────────────────────────────────────────────────
  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar*       texture_registrar_;

  winrt::Windows::Media::Capture::MediaCapture              media_capture_{ nullptr };
  winrt::Windows::Media::Capture::Frames::MediaFrameReader  frame_reader_  { nullptr };
  winrt::Windows::Media::Capture::Frames::MediaFrameSource  frame_source_  { nullptr };

  int64_t     texture_id_      = -1;
  int         device_index_    = 0;   // cycles on switchCamera
  bool        is_front_camera_ = false;

  std::mutex                    buffer_mutex_;
  std::vector<uint8_t>          pixel_data_;
  int32_t                       pixel_width_  = 0;
  int32_t                       pixel_height_ = 0;

  FlutterDesktopPixelBuffer     flutter_pixel_buffer_{};
  std::unique_ptr<FlutterDesktopTextureInfo> texture_info_;
};

}  // namespace flutter_crop_camera

#endif  // FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_
