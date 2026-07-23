cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "flutter_crop_camera")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter_crop_camera_plugin")

find_package(PkgConfig REQUIRED)

# GStreamer libraries required for camera access
pkg_check_modules(GSTREAMER      REQUIRED gstreamer-1.0)
pkg_check_modules(GSTREAMER_APP  REQUIRED gstreamer-app-1.0)
pkg_check_modules(GSTREAMER_VIDEO REQUIRED gstreamer-video-1.0)

add_library(${PLUGIN_NAME} SHARED
  "flutter_crop_camera_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  ${GSTREAMER_INCLUDE_DIRS}
  ${GSTREAMER_APP_INCLUDE_DIRS}
  ${GSTREAMER_VIDEO_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  ${GSTREAMER_LIBRARIES}
  ${GSTREAMER_APP_LIBRARIES}
  ${GSTREAMER_VIDEO_LIBRARIES}
  PkgConfig::GSTREAMER
  PkgConfig::GSTREAMER_APP
  PkgConfig::GSTREAMER_VIDEO
)

set(flutter_crop_camera_bundled_libraries
  ""
  PARENT_SCOPE
)
