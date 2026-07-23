#include "flutter_crop_camera_plugin.h"

// Windows system headers
#include <shlobj.h>       // SHGetKnownFolderPath
#include <strsafe.h>

// Standard library
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <sstream>
#include <stdexcept>

// Flutter
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

namespace flutter_crop_camera {

namespace fs  = std::filesystem;
namespace wmc = winrt::Windows::Media::Capture;
namespace wmf = winrt::Windows::Media::Capture::Frames;
namespace wmd = winrt::Windows::Media::Devices;
namespace wgi = winrt::Windows::Graphics::Imaging;
namespace wss = winrt::Windows::Storage::Streams;
namespace ws  = winrt::Windows::Storage;
namespace wde = winrt::Windows::Devices::Enumeration;

using namespace winrt::Windows::Foundation;
using flutter::EncodableMap;
using flutter::EncodableValue;

// ── Helpers ────────────────────────────────────────────────────────────────

static std::string WStringToString(const std::wstring& wstr) {
    if (wstr.empty()) return {};
    int sz = WideCharToMultiByte(CP_UTF8, 0, wstr.data(),
        static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    std::string result(sz, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(),
        static_cast<int>(wstr.size()), result.data(), sz, nullptr, nullptr);
    return result;
}

static std::string GetTempDir() {
    PWSTR path = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) {
        std::wstring wpath(path);
        CoTaskMemFree(path);
        return WStringToString(wpath) + "\\Temp";
    }
    return "C:\\Temp";
}

static std::string MakeTimestampedPath(const std::string& dir, const std::string& prefix, const std::string& ext) {
    auto now = std::chrono::system_clock::now().time_since_epoch();
    auto ms  = std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
    std::ostringstream ss;
    ss << dir << "\\" << prefix << ms << ext;
    return ss.str();
}

// ── Registration ───────────────────────────────────────────────────────────

void FlutterCropCameraPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<FlutterCropCameraPlugin>(
        registrar, registrar->texture_registrar());

    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(),
        "flutter_crop_camera",
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [plugin_ptr = plugin.get()](const auto& call, auto result) {
            plugin_ptr->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
}

// ── Constructor / Destructor ───────────────────────────────────────────────

FlutterCropCameraPlugin::FlutterCropCameraPlugin(
    flutter::PluginRegistrarWindows* registrar,
    flutter::TextureRegistrar*       texture_registrar)
    : registrar_(registrar),
      texture_registrar_(texture_registrar) {
    // Initialise WinRT apartment for this thread
    winrt::init_apartment();
}

FlutterCropCameraPlugin::~FlutterCropCameraPlugin() {
    StopCameraAsync().get();
}

// ── Method channel dispatcher ──────────────────────────────────────────────

void FlutterCropCameraPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

    const auto& method = call.method_name();

    if (method == "getPlatformVersion") {
        result->Success(EncodableValue(std::string("Windows")));

    } else if (method == "startCamera") {
        bool prefer_front = false;
        if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
            auto it = args->find(EncodableValue(std::string("frontCamera")));
            if (it != args->end()) {
                if (const auto* v = std::get_if<bool>(&it->second)) {
                    prefer_front = *v;
                }
            }
        }
        auto shared_result = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        // Run async on a background thread so we don't block the UI thread
        std::thread([this, prefer_front, shared_result]() {
            StartCameraAsync(prefer_front, shared_result).get();
        }).detach();

    } else if (method == "stopCamera") {
        std::thread([this, r = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
                std::move(result))]() {
            StopCameraAsync().get();
            r->Success();
        }).detach();

    } else if (method == "switchCamera") {
        is_front_camera_ = !is_front_camera_;
        auto shared_result = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        std::thread([this, shared_result]() {
            StopCameraAsync().get();
            StartCameraAsync(is_front_camera_, shared_result).get();
        }).detach();

    } else if (method == "takePicture") {
        auto shared_result = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        std::thread([this, shared_result]() {
            TakePictureAsync(shared_result).get();
        }).detach();

    } else if (method == "getMaxZoom") {
        result->Success(EncodableValue(1.0));

    } else if (method == "setZoom") {
        // No-op — most webcams do not expose WinRT zoom control
        result->Success();

    } else if (method == "setFlashMode") {
        // No-op — webcams typically don't have flash
        result->Success();

    } else {
        result->NotImplemented();
    }
}

// ── Pixel buffer callback (called by Flutter to render texture) ────────────

const FlutterDesktopPixelBuffer* FlutterCropCameraPlugin::CopyPixelBuffer(
    size_t /*width*/, size_t /*height*/) {
    std::lock_guard<std::mutex> lock(buffer_mutex_);
    if (pixel_data_.empty()) return nullptr;

    flutter_pixel_buffer_.buffer = pixel_data_.data();
    flutter_pixel_buffer_.width  = static_cast<size_t>(pixel_width_);
    flutter_pixel_buffer_.height = static_cast<size_t>(pixel_height_);
    return &flutter_pixel_buffer_;
}

// ── Camera lifecycle ───────────────────────────────────────────────────────

IAsyncAction FlutterCropCameraPlugin::StopCameraAsync() {
    if (frame_reader_) {
        co_await frame_reader_.StopAsync();
        frame_reader_ = nullptr;
    }
    if (media_capture_) {
        co_await media_capture_.StopRecordAsync();
        media_capture_ = nullptr;
    }
    if (texture_id_ >= 0) {
        texture_registrar_->UnregisterTexture(texture_id_);
        texture_id_ = -1;
    }
    {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        pixel_data_.clear();
        pixel_width_ = pixel_height_ = 0;
    }
}

IAsyncAction FlutterCropCameraPlugin::StartCameraAsync(
    bool prefer_front,
    std::shared_ptr<flutter::MethodResult<EncodableValue>> result) {

    try {
        // ── Enumerate video devices ──────────────────────────────────────────
        auto devices = co_await wde::DeviceInformation::FindAllAsync(
            wde::DeviceClass::VideoCapture);

        if (devices.Size() == 0) {
            result->Error("CAMERA_UNAVAILABLE",
                          "No camera found. Please connect a webcam.",
                          nullptr);
            co_return;
        }

        // Simple heuristic: iterate through devices; prefer "front" by name
        // (many built-in cameras advertise "front" or "integrated" in name).
        int idx = 0;
        if (devices.Size() > 1) {
            for (uint32_t i = 0; i < devices.Size(); i++) {
                auto name = winrt::to_string(devices.GetAt(i).Name());
                std::transform(name.begin(), name.end(), name.begin(), ::tolower);
                bool is_front_name = name.find("front") != std::string::npos
                                  || name.find("integrated") != std::string::npos
                                  || name.find("facetime") != std::string::npos;
                if (prefer_front == is_front_name) {
                    idx = static_cast<int>(i);
                    break;
                }
            }
        }
        // Clamp to available count
        idx = std::min(idx, static_cast<int>(devices.Size()) - 1);

        // ── Initialise MediaCapture ──────────────────────────────────────────
        auto capture = wmc::MediaCapture();
        wmc::MediaCaptureInitializationSettings settings;
        settings.VideoDeviceId(devices.GetAt(idx).Id());
        settings.StreamingCaptureMode(wmc::StreamingCaptureMode::Video);
        settings.MemoryPreference(wmc::MediaCaptureMemoryPreference::Cpu);

        co_await capture.InitializeAsync(settings);
        media_capture_ = capture;

        // ── Find a video frame source ────────────────────────────────────────
        wmf::MediaFrameSource video_source{ nullptr };
        for (auto const& [id, src] : capture.FrameSources()) {
            if (src.Info().SourceKind() == wmf::MediaFrameSourceKind::Color) {
                video_source = src;
                break;
            }
        }
        if (!video_source) {
            result->Error("CAMERA_ERROR", "No color frame source found.", nullptr);
            co_return;
        }
        frame_source_ = video_source;

        // ── Determine initial frame dimensions from preferred format ──────────
        auto formats = video_source.SupportedFormats();
        uint32_t best_w = 640, best_h = 480;
        for (auto const& fmt : formats) {
            uint32_t w = fmt.VideoFormat().Width();
            uint32_t h = fmt.VideoFormat().Height();
            if (w <= 1920 && h <= 1080 && w > best_w) {
                best_w = w; best_h = h;
            }
        }

        // ── Register Flutter pixel-buffer texture ────────────────────────────
        auto texture_info = std::make_unique<FlutterDesktopTextureInfo>();
        texture_info->type = kFlutterDesktopPixelBufferTexture;
        texture_info->pixel_buffer_config.callback =
            [](size_t w, size_t h, void* user_data) -> const FlutterDesktopPixelBuffer* {
                auto* plugin = reinterpret_cast<FlutterCropCameraPlugin*>(user_data);
                return plugin->CopyPixelBuffer(w, h);
            };
        texture_info->pixel_buffer_config.user_data = this;

        int64_t tid = texture_registrar_->RegisterTexture(texture_info.get());
        texture_id_ = tid;
        texture_info_ = std::move(texture_info);

        // Initialise pixel buffer to black frame
        {
            std::lock_guard<std::mutex> lock(buffer_mutex_);
            pixel_width_  = static_cast<int32_t>(best_w);
            pixel_height_ = static_cast<int32_t>(best_h);
            pixel_data_.assign(static_cast<size_t>(best_w * best_h * 4), 0);
        }

        // ── Start frame reader ───────────────────────────────────────────────
        auto reader = co_await capture.CreateFrameReaderAsync(
            video_source,
            winrt::hstring(L"BGRA8"));
        frame_reader_ = reader;

        frame_reader_.FrameArrived(
            [this](wmf::MediaFrameReader const& sender,
                   wmf::MediaFrameArrivedEventArgs const& /*args*/) {
                auto ref = sender.TryAcquireLatestFrame();
                if (!ref) return;

                auto video_frame = ref.VideoMediaFrame();
                if (!video_frame) return;

                auto sb = video_frame.SoftwareBitmap();
                if (!sb) return;

                // Convert to BGRA8 if needed
                wgi::SoftwareBitmap bgra = wgi::SoftwareBitmap::Convert(
                    sb, wgi::BitmapPixelFormat::Bgra8,
                    wgi::BitmapAlphaMode::Premultiplied);

                uint32_t w = static_cast<uint32_t>(bgra.PixelWidth());
                uint32_t h = static_cast<uint32_t>(bgra.PixelHeight());
                size_t   sz = w * h * 4;

                wgi::BitmapBuffer buf = bgra.LockBuffer(wgi::BitmapBufferAccessMode::Read);
                auto ref2 = buf.CreateReference();
                auto bytes = ref2.data();

                {
                    std::lock_guard<std::mutex> lock(buffer_mutex_);
                    pixel_width_  = static_cast<int32_t>(w);
                    pixel_height_ = static_cast<int32_t>(h);
                    pixel_data_.assign(bytes, bytes + sz);
                }

                // Notify Flutter engine that the texture changed
                texture_registrar_->MarkTextureFrameAvailable(texture_id_);
            });

        co_await frame_reader_.StartAsync();

        // Return texture id to Dart
        result->Success(EncodableValue(static_cast<int32_t>(tid)));

    } catch (winrt::hresult_error const& ex) {
        result->Error("CAMERA_ERROR",
                      WStringToString(ex.message().c_str()),
                      nullptr);
    } catch (std::exception const& ex) {
        result->Error("CAMERA_ERROR", ex.what(), nullptr);
    }
}

// ── Photo capture ──────────────────────────────────────────────────────────

IAsyncAction FlutterCropCameraPlugin::TakePictureAsync(
    std::shared_ptr<flutter::MethodResult<EncodableValue>> result) {
    try {
        if (!media_capture_) {
            result->Error("CAMERA_NOT_INITIALIZED",
                          "Call startCamera() before takePicture().", nullptr);
            co_return;
        }

        // Capture a JPEG to an in-memory stream
        auto stream = wss::InMemoryRandomAccessStream();
        wmc::MediaCapturePhotoSettings photo_settings;
        // Use JPEG encoding for wide compatibility
        photo_settings.Format(wmc::MediaCaptureVideoFormat::Jpeg);

        co_await media_capture_.CapturePhotoToStreamAsync(photo_settings, stream);

        // Read raw bytes from stream
        stream.Seek(0);
        auto reader = wss::DataReader(stream);
        co_await reader.LoadAsync(static_cast<uint32_t>(stream.Size()));

        std::vector<uint8_t> jpeg_bytes(stream.Size());
        reader.ReadBytes(winrt::array_view<uint8_t>(jpeg_bytes));

        // Write to temp directory
        std::string temp_dir = GetTempDir();
        fs::create_directories(temp_dir);
        std::string out_path = MakeTimestampedPath(temp_dir, "captured_", ".jpg");

        std::ofstream file(out_path, std::ios::binary);
        if (!file.is_open()) {
            result->Error("CAPTURE_FAILED", "Cannot create temp file: " + out_path, nullptr);
            co_return;
        }
        file.write(reinterpret_cast<const char*>(jpeg_bytes.data()),
                   static_cast<std::streamsize>(jpeg_bytes.size()));
        file.close();

        result->Success(EncodableValue(out_path));

    } catch (winrt::hresult_error const& ex) {
        result->Error("CAPTURE_FAILED",
                      WStringToString(ex.message().c_str()),
                      nullptr);
    } catch (std::exception const& ex) {
        result->Error("CAPTURE_FAILED", ex.what(), nullptr);
    }
}

}  // namespace flutter_crop_camera
