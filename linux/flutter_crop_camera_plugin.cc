/**
 * flutter_crop_camera_plugin.cc
 *
 * Linux camera implementation using GStreamer + V4L2.
 *
 * Pipeline:
 *   v4l2src ! videoconvert ! video/x-raw,format=BGRA ! appsink
 *
 * Frames from appsink are copied into a FlPixelBufferTexture that Flutter
 * renders via the Texture widget. Gallery picking and crop baking are done
 * entirely in Dart (file_selector + dart:ui) — this file only handles the
 * camera feed and photo capture.
 *
 * Dependencies: gstreamer-1.0, gstreamer-app-1.0, gstreamer-video-1.0
 */

#include "flutter_crop_camera_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <gtk/gtk.h>

#include <cassert>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define FLUTTER_CROP_CAMERA_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), FLUTTER_CROP_CAMERA_PLUGIN_TYPE, \
                               FlutterCropCameraPlugin))

// ── Plugin struct ─────────────────────────────────────────────────────────

struct _FlutterCropCameraPlugin {
    GObject parent_instance;

    FlTextureRegistrar*  texture_registrar;
    FlPixelBufferTexture* pixel_texture;
    int64_t              texture_id;

    GstElement* pipeline;     // full gst pipeline
    GstElement* appsink;      // appsink element

    std::mutex       frame_mutex;
    std::vector<uint8_t> frame_data;  // BGRA pixels
    int32_t          frame_width;
    int32_t          frame_height;

    bool running;
    std::string last_error;

    // Per-device index (for switch camera)
    int device_index;
};

G_DEFINE_TYPE(FlutterCropCameraPlugin, flutter_crop_camera_plugin, G_TYPE_OBJECT)

// ── Forward declarations ──────────────────────────────────────────────────
static const FlPixelBufferTextureVTable* get_vtable();

// ── GObject lifecycle ──────────────────────────────────────────────────────

static void flutter_crop_camera_plugin_dispose(GObject* object) {
    auto* self = FLUTTER_CROP_CAMERA_PLUGIN(object);
    if (self->pipeline) {
        gst_element_set_state(self->pipeline, GST_STATE_NULL);
        gst_object_unref(self->pipeline);
        self->pipeline = nullptr;
    }
    if (self->pixel_texture) {
        fl_texture_registrar_unregister_texture(
            self->texture_registrar,
            FL_TEXTURE(self->pixel_texture));
        g_object_unref(self->pixel_texture);
        self->pixel_texture = nullptr;
    }
    G_OBJECT_CLASS(flutter_crop_camera_plugin_parent_class)->dispose(object);
}

static void flutter_crop_camera_plugin_class_init(FlutterCropCameraPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = flutter_crop_camera_plugin_dispose;
}

static void flutter_crop_camera_plugin_init(FlutterCropCameraPlugin* self) {
    self->pipeline       = nullptr;
    self->appsink        = nullptr;
    self->pixel_texture  = nullptr;
    self->texture_id     = -1;
    self->frame_width    = 0;
    self->frame_height   = 0;
    self->running        = false;
    self->device_index   = 0;

    // Initialise GStreamer (idempotent)
    if (!gst_is_initialized()) {
        gst_init(nullptr, nullptr);
    }
}

// ── Pixel buffer texture callback ─────────────────────────────────────────

static gboolean copy_pixels(FlPixelBufferTexture* texture,
                              const uint8_t**       out_buffer,
                              uint32_t*             out_width,
                              uint32_t*             out_height,
                              GError**              error) {
    // Retrieve plugin pointer stored as GObject data
    auto* self = static_cast<FlutterCropCameraPlugin*>(
        g_object_get_data(G_OBJECT(texture), "plugin"));
    if (!self) return FALSE;

    std::lock_guard<std::mutex> lock(self->frame_mutex);
    if (self->frame_data.empty()) return FALSE;

    *out_buffer = self->frame_data.data();
    *out_width  = static_cast<uint32_t>(self->frame_width);
    *out_height = static_cast<uint32_t>(self->frame_height);
    return TRUE;
}

static const FlPixelBufferTextureVTable kVTable = {
    copy_pixels,
};

// ── GStreamer helpers ──────────────────────────────────────────────────────

/**
 * Stop and destroy the current GStreamer pipeline (if any).
 */
static void stop_pipeline(FlutterCropCameraPlugin* self) {
    if (self->pipeline) {
        gst_element_set_state(self->pipeline, GST_STATE_NULL);
        gst_object_unref(self->pipeline);
        self->pipeline = nullptr;
        self->appsink  = nullptr;
    }
    self->running = false;
}

/**
 * Determine the V4L2 device path for the given device index.
 * Falls back to /dev/video0 if the indexed device is not found.
 */
static std::string get_device_path(int index) {
    // Simple enumeration — /dev/video0, /dev/video1, ...
    std::string path = "/dev/video" + std::to_string(index);
    // Check if it exists; if not, fall back to /dev/video0
    if (access(path.c_str(), F_OK) != 0) {
        return "/dev/video0";
    }
    return path;
}

/**
 * Build and start a GStreamer pipeline:
 *   v4l2src device=/dev/videoN ! videoconvert !
 *   video/x-raw,format=BGRA,width=W,height=H ! appsink
 */
static bool start_pipeline(FlutterCropCameraPlugin* self,
                            const std::string& device,
                            int width, int height) {
    stop_pipeline(self);

    std::string pipeline_str =
        "v4l2src device=" + device + " ! "
        "videoconvert ! "
        "video/x-raw,format=BGRA,width=" + std::to_string(width) +
        ",height=" + std::to_string(height) + ",framerate=30/1 ! "
        "appsink name=sink emit-signals=true max-buffers=2 drop=true "
        "sync=false";

    GError* error = nullptr;
    self->pipeline = gst_parse_launch(pipeline_str.c_str(), &error);
    if (error) {
        self->last_error = std::string(error->message);
        g_error_free(error);
        return false;
    }

    self->appsink = gst_bin_get_by_name(GST_BIN(self->pipeline), "sink");

    // Connect the new-sample signal so we get frames
    g_signal_connect(self->appsink, "new-sample",
        G_CALLBACK(+[](GstElement* sink, gpointer user_data) -> GstFlowReturn {
            auto* plugin = static_cast<FlutterCropCameraPlugin*>(user_data);

            GstSample* sample = gst_app_sink_pull_sample(GST_APP_SINK(sink));
            if (!sample) return GST_FLOW_ERROR;

            GstBuffer* buffer = gst_sample_get_buffer(sample);
            GstCaps*   caps   = gst_sample_get_caps(sample);

            GstVideoInfo info;
            if (gst_video_info_from_caps(&info, caps)) {
                GstMapInfo map;
                if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
                    int w = GST_VIDEO_INFO_WIDTH(&info);
                    int h = GST_VIDEO_INFO_HEIGHT(&info);

                    {
                        std::lock_guard<std::mutex> lock(plugin->frame_mutex);
                        plugin->frame_width  = w;
                        plugin->frame_height = h;
                        plugin->frame_data.assign(map.data, map.data + map.size);
                    }

                    // Mark the Flutter texture as dirty
                    fl_texture_registrar_mark_texture_frame_available(
                        plugin->texture_registrar,
                        FL_TEXTURE(plugin->pixel_texture));

                    gst_buffer_unmap(buffer, &map);
                }
            }
            gst_sample_unref(sample);
            return GST_FLOW_OK;
        }), self);

    GstStateChangeReturn ret = gst_element_set_state(
        self->pipeline, GST_STATE_PLAYING);
    if (ret == GST_STATE_CHANGE_FAILURE) {
        self->last_error = "Failed to start GStreamer pipeline (GST_STATE_CHANGE_FAILURE)";
        stop_pipeline(self);
        return false;
    }

    self->running = true;
    return true;
}

// ── Temp directory ────────────────────────────────────────────────────────

static std::string get_temp_dir() {
    const char* tmp = g_get_tmp_dir();
    return tmp ? std::string(tmp) : "/tmp";
}

// ── Method channel handler ────────────────────────────────────────────────

static void method_call_cb(FlMethodChannel*   channel,
                            FlMethodCall*      method_call,
                            gpointer           user_data) {
    auto* self = FLUTTER_CROP_CAMERA_PLUGIN(user_data);
    const gchar* method = fl_method_call_get_name(method_call);
    g_autoptr(FlMethodResponse) response = nullptr;

    if (strcmp(method, "getPlatformVersion") == 0) {
        g_autoptr(FlValue) result = fl_value_new_string("Linux");
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

    } else if (strcmp(method, "startCamera") == 0) {
        FlValue* args = fl_method_call_get_args(method_call);
        bool front_camera = false;
        if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
            FlValue* fc = fl_value_lookup_string(args, "frontCamera");
            if (fc && fl_value_get_type(fc) == FL_VALUE_TYPE_BOOL) {
                front_camera = fl_value_get_bool(fc);
            }
        }

        // For Linux: front cameras are often /dev/video1
        int dev_idx = front_camera ? 1 : 0;
        std::string device = get_device_path(dev_idx);
        self->device_index = dev_idx;

        // Register pixel-buffer texture if not already done
        if (!self->pixel_texture) {
            self->pixel_texture = fl_pixel_buffer_texture_new(&kVTable);
            g_object_set_data(G_OBJECT(self->pixel_texture), "plugin", self);
            int64_t tid = fl_texture_registrar_register_texture(
                self->texture_registrar,
                FL_TEXTURE(self->pixel_texture));
            self->texture_id = tid;
        }

        // Pre-fill buffer so Flutter doesn't render garbage
        {
            std::lock_guard<std::mutex> lock(self->frame_mutex);
            self->frame_width  = 640;
            self->frame_height = 480;
            self->frame_data.assign(640 * 480 * 4, 0);
        }

        if (!start_pipeline(self, device, 640, 480)) {
            g_autoptr(FlValue) err_msg = fl_value_new_string(
                self->last_error.empty()
                    ? "Failed to open camera. Is /dev/videoN accessible?"
                    : self->last_error.c_str());
            response = FL_METHOD_RESPONSE(
                fl_method_error_response_new("CAMERA_ERROR",
                    self->last_error.c_str(), nullptr));
        } else {
            g_autoptr(FlValue) result = fl_value_new_int(
                static_cast<int64_t>(self->texture_id));
            response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
        }

    } else if (strcmp(method, "stopCamera") == 0) {
        stop_pipeline(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

    } else if (strcmp(method, "switchCamera") == 0) {
        self->device_index = (self->device_index == 0) ? 1 : 0;
        std::string device = get_device_path(self->device_index);
        start_pipeline(self, device, 640, 480);
        g_autoptr(FlValue) result = fl_value_new_int(self->texture_id);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

    } else if (strcmp(method, "takePicture") == 0) {
        if (!self->running) {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                "CAMERA_NOT_INITIALIZED",
                "Call startCamera() before takePicture().", nullptr));
        } else {
            // Grab the latest frame and save it as PPM → PNG via GStreamer encode
            std::lock_guard<std::mutex> lock(self->frame_mutex);
            if (self->frame_data.empty()) {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                    "CAPTURE_FAILED", "No frame available yet.", nullptr));
            } else {
                // Save raw BGRA as PNG using GdkPixbuf
                int w = self->frame_width;
                int h = self->frame_height;

                // Build a timestamp filename
                gint64 ts = g_get_real_time() / 1000;
                std::string out_path = get_temp_dir() + "/captured_" +
                    std::to_string(ts) + ".png";

                // Use GdkPixbuf to save as PNG
                GdkPixbuf* pixbuf = gdk_pixbuf_new_from_data(
                    self->frame_data.data(),
                    GDK_COLORSPACE_RGB,
                    TRUE,          // has_alpha
                    8,             // bits_per_sample
                    w, h,
                    w * 4,         // rowstride
                    nullptr, nullptr);

                GError* save_err = nullptr;
                bool saved = gdk_pixbuf_save(pixbuf, out_path.c_str(),
                    "png", &save_err, nullptr);
                g_object_unref(pixbuf);

                if (!saved) {
                    std::string msg = save_err ? save_err->message : "Unknown error";
                    if (save_err) g_error_free(save_err);
                    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                        "CAPTURE_FAILED", msg.c_str(), nullptr));
                } else {
                    g_autoptr(FlValue) result = fl_value_new_string(out_path.c_str());
                    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
                }
            }
        }

    } else if (strcmp(method, "getMaxZoom") == 0) {
        g_autoptr(FlValue) result = fl_value_new_float(1.0);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

    } else if (strcmp(method, "setZoom") == 0 ||
               strcmp(method, "setFlashMode") == 0) {
        // No-op on Linux — V4L2 zoom/flash is highly device-dependent
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    g_autoptr(GError) error = nullptr;
    fl_method_call_respond(method_call, response, &error);
}

// ── Plugin registration ───────────────────────────────────────────────────

void flutter_crop_camera_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {

    FlutterCropCameraPlugin* plugin = FLUTTER_CROP_CAMERA_PLUGIN(
        g_object_new(FLUTTER_CROP_CAMERA_PLUGIN_TYPE, nullptr));

    plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(registrar),
        "flutter_crop_camera",
        FL_METHOD_CODEC(codec));

    fl_method_channel_set_method_call_handler(
        channel, method_call_cb, g_object_ref(plugin), g_object_unref);

    g_object_unref(plugin);
}
