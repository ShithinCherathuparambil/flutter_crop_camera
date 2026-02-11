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
    return const MaterialApp(home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Stores the file reference of the image returned by the plugin.
  File? _capturedImage;

  /// User-controlled setting to enable or disable the crop editor step.
  bool _cropEnabled = true;

  /// User-controlled setting to toggle the grid in the crop editor.
  bool _showGrid = true;

  /// User-controlled setting to hide/show aspect ratio options in the cropper.
  bool _lockAspectRatio = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Cam Cropper Example')),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("Enable Cropping"),
            value: _cropEnabled,
            onChanged: (val) {
              setState(() {
                _cropEnabled = val;
              });
            },
          ),
          SwitchListTile(
            title: const Text("Show Grid in Cropper"),
            value: _showGrid,
            onChanged: (val) {
              setState(() {
                _showGrid = val;
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
          if (_capturedImage != null)
            Expanded(child: Center(child: Image.file(_capturedImage!)))
          else
            const Expanded(child: Center(child: Text("No image captured"))),
          ElevatedButton(
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
                  // Navigate to camera screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        body: FlutterCropCamera(
                          cropEnabled: _cropEnabled,
                          initialCamera: CamPreference.rear,
                          quality: 1, // 1.0 = Original quality
                          aspectRatio: CamRatio.ratio3x4, // Starting ratio
                          showGrid: _showGrid,
                          lockAspectRatio: _lockAspectRatio,
                          screenOrientations: const [
                            DeviceOrientation.portraitUp,
                          ], // Lock to portrait
                          onImageCaptured: (file) {
                            setState(() {
                              _capturedImage = file;
                            });
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                  );
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
            child: const Text("Open Camera"),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
