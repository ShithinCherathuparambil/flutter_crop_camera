#include "include/flutter_crop_camera/flutter_crop_camera_plugin.h"

// Windows system headers
#include <shlobj.h>       // SHGetKnownFolderPath
#include <strsafe.h>

// Standard library
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
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

const UINT WM_FLUTTER_CROP_CAMERA_CALLBACK = WM_USER + 1024;

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

void FlutterCropCameraPlugin::RunOnMainThread(std::function<void()> callback) {
    auto* callback_ptr = new std::function<void()>(std::move(callback));
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    if (hwnd) {
        PostMessage(hwnd, WM_FLUTTER_CROP_CAMERA_CALLBACK, 0, reinterpret_cast<LPARAM>(callback_ptr));
    } else {
        delete callback_ptr;
    }
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
    // Initialise WinRT apartment for this thread safely
    try {
        winrt::init_apartment();
    } catch (...) {
        // COM/WinRT might already be initialized on the main thread.
    }

    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
            if (message == WM_FLUTTER_CROP_CAMERA_CALLBACK) {
                auto* callback = reinterpret_cast<std::function<void()>*>(lparam);
                if (callback) {
                    (*callback)();
                    delete callback;
                }
                return std::optional<LRESULT>(0);
            }
            return std::optional<LRESULT>();
        });
}

FlutterCropCameraPlugin::~FlutterCropCameraPlugin() {
    StopCamera();
    if (window_proc_id_ >= 0) {
        registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    }
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
        StartCamera(prefer_front, shared_result);

    } else if (method == "stopCamera") {
        StopCamera();
        result->Success();

    } else if (method == "switchCamera") {
        is_front_camera_ = !is_front_camera_;
        auto shared_result = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        StopCamera();
        StartCamera(is_front_camera_, shared_result);

    } else if (method == "takePicture") {
        auto shared_result = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        TakePicture(shared_result);

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

void FlutterCropCameraPlugin::StopCamera() {
    try {
        if (frame_reader_) {
            frame_reader_.StopAsync().get();
            frame_reader_ = nullptr;
        }
        if (media_capture_) {
            // Null out the capture session (StopRecordAsync is not used as we don't record video).
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
    } catch (...) {
        // Suppress any errors on stop/cleanup to avoid crashes.
    }
}

void FlutterCropCameraPlugin::StartCamera(
    bool prefer_front,
    std::shared_ptr<flutter::MethodResult<EncodableValue>> result) {

    std::thread([this, prefer_front, result]() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
        } catch (...) {}

        try {
            // ── Enumerate video devices ──────────────────────────────────────────
            auto devices = wde::DeviceInformation::FindAllAsync(
                wde::DeviceClass::VideoCapture).get();

            if (devices.Size() == 0) {
                RunOnMainThread([result]() {
                    result->Error("CAMERA_UNAVAILABLE",
                                  "No camera found. Please connect a webcam.",
                                  nullptr);
                });
                return;
            }

            // Simple heuristic: iterate through devices; prefer "front" by name
            int idx = 0;
            if (devices.Size() > 1) {
                for (uint32_t i = 0; i < devices.Size(); i++) {
                    auto name = winrt::to_string(devices.GetAt(i).Name());
                    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) {
                        return static_cast<char>(std::tolower(c));
                    });
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
            idx = (std::min)(idx, static_cast<int>(devices.Size()) - 1);

            // ── Initialise MediaCapture ──────────────────────────────────────────
            auto capture = wmc::MediaCapture();
            wmc::MediaCaptureInitializationSettings settings;
            settings.VideoDeviceId(devices.GetAt(idx).Id());
            settings.StreamingCaptureMode(wmc::StreamingCaptureMode::Video);
            settings.MemoryPreference(wmc::MediaCaptureMemoryPreference::Cpu);

            capture.InitializeAsync(settings).get();
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
                RunOnMainThread([result]() {
                    result->Error("CAMERA_ERROR", "No color frame source found.", nullptr);
                });
                return;
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

            // We do texture registration on the UI thread to be completely safe
            RunOnMainThread([this, best_w, best_h, video_source, capture, result]() {
                // ── Register Flutter pixel-buffer texture ────────────────────────────
                auto pixel_buffer_texture = flutter::PixelBufferTexture(
                    [this](size_t w, size_t h) -> const FlutterDesktopPixelBuffer* {
                        return this->CopyPixelBuffer(w, h);
                    });
                texture_ = std::make_unique<flutter::TextureVariant>(std::move(pixel_buffer_texture));

                int64_t tid = texture_registrar_->RegisterTexture(texture_.get());
                texture_id_ = tid;

                // Initialise pixel buffer to black frame
                {
                    std::lock_guard<std::mutex> lock(buffer_mutex_);
                    pixel_width_  = static_cast<int32_t>(best_w);
                    pixel_height_ = static_cast<int32_t>(best_h);
                    pixel_data_.assign(static_cast<size_t>(best_w * best_h * 4), 0);
                }

                // Now start the frame reader in a background thread again to avoid blocking the main thread
                std::thread([this, video_source, capture, tid, result]() {
                    try {
                        winrt::init_apartment(winrt::apartment_type::multi_threaded);
                    } catch (...) {}

                    try {
                        // ── Start frame reader ───────────────────────────────────────────────
                        auto reader = capture.CreateFrameReaderAsync(
                            video_source,
                            winrt::hstring(L"BGRA8")).get();
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

                        frame_reader_.StartAsync().get();

                        // Return texture id to Dart on the main thread
                        RunOnMainThread([result, tid]() {
                            result->Success(EncodableValue(static_cast<int32_t>(tid)));
                        });
                    } catch (winrt::hresult_error const& ex) {
                        std::string msg = WStringToString(ex.message().c_str());
                        RunOnMainThread([result, msg]() {
                            result->Error("CAMERA_ERROR", msg, nullptr);
                        });
                    } catch (std::exception const& ex) {
                        std::string msg = ex.what();
                        RunOnMainThread([result, msg]() {
                            result->Error("CAMERA_ERROR", msg, nullptr);
                        });
                    }
                }).detach();
            });

        } catch (winrt::hresult_error const& ex) {
            std::string msg = WStringToString(ex.message().c_str());
            RunOnMainThread([result, msg]() {
                result->Error("CAMERA_ERROR", msg, nullptr);
            });
        } catch (std::exception const& ex) {
            std::string msg = ex.what();
            RunOnMainThread([result, msg]() {
                result->Error("CAMERA_ERROR", msg, nullptr);
            });
        }
    }).detach();
}

// ── Photo capture ──────────────────────────────────────────────────────────

void FlutterCropCameraPlugin::TakePicture(
    std::shared_ptr<flutter::MethodResult<EncodableValue>> result) {
    std::thread([this, result]() {
        try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
        } catch (...) {}

        try {
            if (!media_capture_) {
                RunOnMainThread([result]() {
                    result->Error("CAMERA_NOT_INITIALIZED",
                                  "Call startCamera() before takePicture().", nullptr);
                });
                return;
            }

            // Capture a JPEG to an in-memory stream
            auto stream = wss::InMemoryRandomAccessStream();
            namespace wmp = winrt::Windows::Media::MediaProperties;
            wmp::ImageEncodingProperties photo_settings = wmp::ImageEncodingProperties::CreateJpeg();

            media_capture_.CapturePhotoToStreamAsync(photo_settings, stream).get();

            // Read raw bytes from stream
            stream.Seek(0);
            auto reader = wss::DataReader(stream);
            reader.LoadAsync(static_cast<uint32_t>(stream.Size())).get();

            std::vector<uint8_t> jpeg_bytes(stream.Size());
            reader.ReadBytes(winrt::array_view<uint8_t>(jpeg_bytes));

            // Write to temp directory
            std::string temp_dir = GetTempDir();
            fs::create_directories(temp_dir);
            std::string out_path = MakeTimestampedPath(temp_dir, "captured_", ".jpg");

            std::ofstream file(out_path, std::ios::binary);
            if (!file.is_open()) {
                RunOnMainThread([result, out_path]() {
                    result->Error("CAPTURE_FAILED", "Cannot create temp file: " + out_path, nullptr);
                });
                return;
            }
            file.write(reinterpret_cast<const char*>(jpeg_bytes.data()),
                       static_cast<std::streamsize>(jpeg_bytes.size()));
            file.close();

            RunOnMainThread([result, out_path]() {
                result->Success(EncodableValue(out_path));
            });

        } catch (winrt::hresult_error const& ex) {
            std::string msg = WStringToString(ex.message().c_str());
            RunOnMainThread([result, msg]() {
                result->Error("CAPTURE_FAILED", msg, nullptr);
            });
        } catch (std::exception const& ex) {
            std::string msg = ex.what();
            RunOnMainThread([result, msg]() {
                result->Error("CAPTURE_FAILED", msg, nullptr);
            });
        }
    }).detach();
}

}  // namespace flutter_crop_camera
