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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
      appBar: AppBar(
        title: const Text('Flutter Cam Cropper Example'),
        actions: [
          if (_capturedImages.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _capturedImages.clear()),
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
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

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _FeatureCard(
                      title: 'Crop Camera',
                      subtitle: 'Capture and crop instantly',
                      icon: Icons.camera_alt_rounded,
                      gradient: const [Color(0xFF6366F1), Color(0xFFA855F7)],
                      onTap: _openCamera,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _FeatureCard(
                      title: 'Single Picker',
                      subtitle: 'Pick & Crop',
                      icon: Icons.photo_library_rounded,
                      gradient: const [Color(0xFF3B82F6), Color(0xFF2DD4BF)],
                      onTap: _pickSingle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FeatureCard(
                      title: 'Multi Picker',
                      subtitle: 'Batch Process',
                      icon: Icons.collections_rounded,
                      gradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                      onTap: _pickMulti,
                    ),
                  ),
                ],
              ),
              if (_capturedImages.isNotEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8),
                  // gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  //   crossAxisCount: 3,
                  //   crossAxisSpacing: 8,
                  //   mainAxisSpacing: 8,
                  // ),
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(
                        _capturedImages[index],
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text("No images captured")),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSingle() async {
    if (context.mounted) {
      // Navigate to gallery picker
      final ImageSourcePicker picker = ImageSourcePicker();
      final file = await picker.pickImage(
        context: context,
        enableEdit: _enableEdit,
        appBarStyle: const EditorAppBarStyle(
          title: Text("Single Crop Editor"),
          backgroundColor: Colors.black,
        ),
        editorStyle: const EditorStyle(
          cropHandleColor: Colors.blueAccent,
          cropHandleSize: 10.0,
          cropBorderColor: Colors.blue,
          gridColor: Colors.blueGrey,
          bottomNavSelectedItemColor: Colors.blueAccent,
        ),
        quality: 1,
        screenOrientations: const [DeviceOrientation.portraitUp],
      );

      if (file != null) {
        setState(() {
          _capturedImages = [file];
        });
      }
    }
  }

  Future<void> _pickMulti() async {
    // Navigate to gallery picker
    final ImageSourcePicker picker = ImageSourcePicker();
    final files = await picker.pickMultipleImages(
      context: context,
      enableEdit: _enableEdit,
      quality: 1,
      appBarStyle: const EditorAppBarStyle(
        title: Text("Multi Crop Editor"),
        backgroundColor: Colors.black,
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
      screenOrientations: const [DeviceOrientation.portraitUp],
    );

    if (files.isNotEmpty) {
      setState(() {
        _capturedImages = files;
      });
    }
  }

  Future<void> _openCamera() async {
    // 1. Check current permission status
    var status = await Permission.camera.status;

    // 2. If permission is not granted, request it
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    // 3. Handle the permission result
    if (status.isGranted) {
      if (context.mounted) {
        final ImageSourcePicker picker = ImageSourcePicker();
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
          screenOrientations: const [DeviceOrientation.portraitUp],
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
            content: Text('Camera permission is required to use this feature'),
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
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
