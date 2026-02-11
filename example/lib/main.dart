import 'dart:io';
import 'package:flutter/material.dart';
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
  File? _capturedImage;
  bool _cropEnabled = true;
  bool _showGrid = true;
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
              // Request camera permission
              final status = await Permission.camera.request();
              if (status.isGranted) {
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        body: FlutterCropCamera(
                          cropEnabled: _cropEnabled,
                          initialCamera: CamPreference.rear,
                          quality: 1,
                          aspectRatio: CamRatio.ratio3x4,
                          showGrid: _showGrid,
                          lockAspectRatio: _lockAspectRatio,
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
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Camera permission is required'),
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
