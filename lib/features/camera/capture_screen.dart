import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.english = false});
  final bool english;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  XFile? photo;
  String? error;
  bool busy = false;
  bool flash = false;
  bool handedOff = false;
  int generation = 0;
  double zoom = 1, maxZoom = 1;
  String tr(String vi, String en) => widget.english ? en : vi;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  Future<void> initialize() async {
    final attempt = ++generation;
    try {
      final cameras = await availableCameras();
      if (!mounted || attempt != generation) return;
      if (cameras.isEmpty) throw CameraException('NoCamera', '');
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      camera = controller;
      await controller.initialize();
      if (!mounted || attempt != generation) {
        await controller.dispose();
        return;
      }
      zoom = 1;
      flash = false;
      maxZoom = (await controller.getMaxZoomLevel()).clamp(1, 8);
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            'Không mở được camera. Cấp quyền trong Cài đặt hoặc nhập ảnh từ thư viện.',
            'Camera unavailable. Allow camera permission in Settings or import from Photos.',
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      generation++;
      camera?.dispose();
      camera = null;
    } else if (state == AppLifecycleState.resumed && photo == null) {
      initialize();
    }
  }

  Future<void> capture() async {
    if (busy || camera?.value.isInitialized != true) return;
    setState(() => busy = true);
    try {
      final result = await camera!.takePicture();
      if (mounted) {
        setState(() => photo = result);
      } else {
        try {
          await File(result.path).delete();
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            'Chụp thất bại. Thử lại.',
            'Capture failed. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    camera?.dispose();
    if (!handedOff && photo != null) {
      File(photo!.path).delete().catchError((_) => File(photo!.path));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(tr('Chụp X-quang', 'Scan X-ray')),
      actions: [
        if (photo == null)
          IconButton(
            tooltip: tr('Đèn flash', 'Flash'),
            onPressed: () async {
              try {
                await camera?.setFlashMode(
                  flash ? FlashMode.off : FlashMode.torch,
                );
                if (mounted) setState(() => flash = !flash);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr(
                          'Camera không hỗ trợ đèn flash.',
                          'Flash unavailable.',
                        ),
                      ),
                    ),
                  );
                }
              }
            },
            icon: Icon(flash ? Icons.flash_on : Icons.flash_off),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(
                'Giữ điện thoại song song phim, tránh phản chiếu. Ảnh chụp không tương đương phim gốc.',
                'Keep the phone parallel to the film and avoid reflections. Photos do not equal original radiographs.',
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: Center(
              child: photo != null
                  ? Image.file(File(photo!.path))
                  : error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : camera?.value.isInitialized == true
                  ? CameraPreview(camera!)
                  : const CircularProgressIndicator(),
            ),
          ),
          if (photo == null && camera?.value.isInitialized == true)
            Slider(
              value: zoom,
              min: 1,
              max: maxZoom,
              onChanged: (v) async {
                try {
                  await camera!.setZoomLevel(v);
                  if (mounted) setState(() => zoom = v);
                } catch (_) {}
              },
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: photo == null
                ? FilledButton.icon(
                    onPressed: busy || camera?.value.isInitialized != true
                        ? null
                        : capture,
                    icon: const Icon(Icons.camera),
                    label: Text(tr('Chụp', 'Capture')),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            await File(photo!.path).delete();
                          } catch (_) {}
                          if (mounted) {
                            setState(() => photo = null);
                            if (camera == null) await initialize();
                          }
                        },
                        child: Text(tr('Chụp lại', 'Retake')),
                      ),
                      FilledButton(
                        onPressed: () {
                          handedOff = true;
                          Navigator.pop(context, photo);
                        },
                        child: Text(tr('Dùng ảnh', 'Use photo')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}
