import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_crop_camera/flutter_crop_camera.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Stores the file references of the images returned by the plugin.
  List<File> _capturedImages = [];

  /// User-controlled setting to enable or disable the crop editor step.
  bool _enableEdit = true;

  /// User-controlled setting to toggle the grid in the crop editor.

  /// User-controlled setting to hide/show aspect ratio options in the cropper.
  bool _lockAspectRatio = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Cam Cropper Example')),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            SwitchListTile(
              title: const Text("Enable Cropping"),
              value: _enableEdit,
              onChanged: (val) {
                setState(() {
                  _enableEdit = val;
                });
              },
            ),

            SwitchListTile(
              title: const Text("Lock Aspect Ratio (Show Options)"),
              value: _lockAspectRatio,
              onChanged: (val) {
                setState(() {
                  _lockAspectRatio = val;
                });
              },
            ),
            if (_capturedImages.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  // gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  //   crossAxisCount: 3,
                  //   crossAxisSpacing: 8,
                  //   mainAxisSpacing: 8,
                  // ),
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    return Image.file(
                      _capturedImages[index],
                      fit: BoxFit.cover,
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                ),
              )
            else
              const Expanded(child: Center(child: Text("No images captured"))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                spacing: 5,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // 1. Check current permission status
                        var status = await Permission.camera.status;

                        // 2. If permission is not granted, request it
                        if (!status.isGranted) {
                          status = await Permission.camera.request();
                        }

                        // 3. Handle the permission result
                        if (status.isGranted) {
                          if (context.mounted) {
                            final ImageSourcePicker picker =
                                ImageSourcePicker();
                            // Navigate to camera screen
                            final file = await picker.openCamera(
                              context: context,
                              enableEdit: _enableEdit,
                              initialCamera: CamPreference.rear,
                              quality: 1,
                              aspectRatio: CamRatio.ratio3x4,
                              lockAspectRatio: _lockAspectRatio,
                              editorStyle: const EditorStyle(
                                cropHandleColor: Colors.greenAccent,
                                cropHandleSize: 14.0,
                                cropBorderColor: Colors.green,
                                gridColor: Colors.white24,
                                bottomNavSelectedItemColor: Colors.blue,
                              ),
                              screenOrientations: const [
                                DeviceOrientation.portraitUp,
                              ],
                            );
                            log('file - ${file?.path}');
                            if (file != null) {
                              setState(() {
                                _capturedImages = [file];
                              });
                            }
                          }
                        } else if (status.isDenied) {
                          // Permission denied, but can request again
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Camera permission is required to use this feature',
                                ),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        } else if (status.isPermanentlyDenied) {
                          // Permission permanently denied, guide user to settings
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Camera permission is permanently denied. Please enable it in settings.',
                                ),
                                duration: const Duration(seconds: 5),
                                action: SnackBarAction(
                                  label: 'Open Settings',
                                  onPressed: () {
                                    openAppSettings();
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text(
                        "Open Camera",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (context.mounted) {
                          // Navigate to gallery picker
                          final ImageSourcePicker picker = ImageSourcePicker();
                          final files = await picker.pickMultipleImages(
                            context: context,
                            enableEdit: _enableEdit,
                            quality: 1,
                            appBarStyle: const EditorAppBarStyle(
                              title: Text("Multi Crop Editor"),
                              backgroundColor: Colors.white,
                            ),
                            editorStyle: const EditorStyle(
                              cropHandleColor: Colors.blue,
                              cropHandleSize: 12.0,
                              cropBorderColor: Colors.blue,
                              cropBorderWidth: 1.0,
                              gridColor: Colors.red,
                              bottomNavSelectedItemColor: Colors.blue,
                              bottomNavUnSelectedItemColor: Colors.white54,
                            ),
                            screenOrientations: const [
                              DeviceOrientation.portraitUp,
                            ],
                          );

                          if (files.isNotEmpty) {
                            setState(() {
                              _capturedImages = files;
                            });
                          }
                        }
                      },
                      child: const Text(
                        "Open Gallery (Multi)",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (context.mounted) {
                          // Navigate to gallery picker
                          final ImageSourcePicker picker = ImageSourcePicker();
                          final file = await picker.pickImage(
                            context: context,
                            enableEdit: _enableEdit,
                            appBarStyle: const EditorAppBarStyle(
                              title: Text("Single Crop Editor"),
                              backgroundColor: Colors.white,
                            ),
                            editorStyle: const EditorStyle(
                              cropHandleColor: Colors.blueAccent,
                              cropHandleSize: 10.0,
                              cropBorderColor: Colors.blue,
                              gridColor: Colors.blueGrey,
                              bottomNavSelectedItemColor: Colors.blueAccent,
                            ),
                            quality: 1,
                            screenOrientations: const [
                              DeviceOrientation.portraitUp,
                            ],
                          );

                          if (file != null) {
                            setState(() {
                              _capturedImages = [file];
                            });
                          }
                        }
                      },
                      child: const Text(
                        "Open Gallery (Single)",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
