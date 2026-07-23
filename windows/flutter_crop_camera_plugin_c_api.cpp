// C API shim required by Flutter's plugin registrar
#include "include/flutter_crop_camera/flutter_crop_camera_plugin_c_api.h"
#include "flutter_crop_camera_plugin.h"

void FlutterCropCameraPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_crop_camera::FlutterCropCameraPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
