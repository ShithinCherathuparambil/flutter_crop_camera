#ifndef FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>

G_BEGIN_DECLS

#define FLUTTER_CROP_CAMERA_PLUGIN_TYPE (flutter_crop_camera_plugin_get_type())
G_DECLARE_FINAL_TYPE(FlutterCropCameraPlugin, flutter_crop_camera_plugin,
                     FLUTTER_CROP_CAMERA, PLUGIN, GObject)

void flutter_crop_camera_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FLUTTER_CROP_CAMERA_PLUGIN_H_
