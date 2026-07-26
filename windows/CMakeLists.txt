cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "flutter_crop_camera")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "flutter_crop_camera_plugin")

list(APPEND PLUGIN_SOURCES
  "flutter_crop_camera_plugin.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/flutter_crop_camera/flutter_crop_camera_plugin_c_api.h"
  "flutter_crop_camera_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# C++/WinRT requires this flag for coroutine support
target_compile_options(${PLUGIN_NAME} PRIVATE /await:strict /FS)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  windowsapp  # WinRT APIs (Windows.Media.Capture, etc.)
)

set(flutter_crop_camera_bundled_libraries
  ""
  PARENT_SCOPE
)
