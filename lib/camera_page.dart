import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final bool isFaceCapture;

  const CameraPage({
    super.key,
    required this.cameras,
    this.isFaceCapture = false,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  XFile? _capturedFile;
  bool _isTakingPicture = false;

  FaceDetector? _faceDetector;
  bool _isProcessingImage = false;
  bool _isFaceDetected = false;
  int _blinkState = 0;

  bool _initialCameraSet = false;

  @override
  void initState() {
    super.initState();
    if (widget.isFaceCapture) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    }
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    
    // Default to front camera if face capture only on first load
    if (widget.isFaceCapture && !_initialCameraSet) {
      final frontIdx = widget.cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (frontIdx != -1) _selectedCameraIndex = frontIdx;
      _initialCameraSet = true;
    }

    // Dispose old controller if exists to free resources before initializing new one
    final oldController = _controller;
    if (oldController != null) {
      _controller = null;
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (e) {
        debugPrint('Error stopping image stream: $e');
      }
      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint('Error disposing old controller: $e');
      }
    }

    final controller = CameraController(
      widget.cameras[_selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    
    try {
      await controller.initialize();
      if (mounted) setState(() {});

      if (widget.isFaceCapture && _faceDetector != null) {
        controller.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || _faceDetector == null || !mounted) return;
    _isProcessingImage = true;

    try {
      final camera = widget.cameras[_selectedCameraIndex];
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final InputImageFormat inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);
      
      if (mounted) {
        if (faces.length == 1) {
          final face = faces.first;
          final left = face.leftEyeOpenProbability ?? 1.0;
          final right = face.rightEyeOpenProbability ?? 1.0;

          if (_blinkState == 0) {
            if (left > 0.7 && right > 0.7) _blinkState = 1;
          } else if (_blinkState == 1) {
            if (left < 0.4 && right < 0.4) _blinkState = 2;
          } else if (_blinkState == 2) {
            if (left > 0.7 && right > 0.7) _blinkState = 3;
          }

          final detected = _blinkState == 3;
          if (_isFaceDetected != detected) {
            setState(() {
              _isFaceDetected = detected;
            });
          }
        } else {
          // Face lost or multiple faces, reset
          if (_blinkState != 0 || _isFaceDetected) {
            setState(() {
              _blinkState = 0;
              _isFaceDetected = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Live face detect error: $e');
    }

    _isProcessingImage = false;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  bool _isTogglingCamera = false;

  Future<void> _toggleCamera() async {
    if (widget.cameras.length < 2 || _isTogglingCamera) return;
    
    _isTogglingCamera = true;
    final oldController = _controller;
    
    setState(() {
      _controller = null; // triggers loading spinner
      _blinkState = 0;
      _isFaceDetected = false;
    });
    
    try {
      if (oldController != null) {
        if (widget.isFaceCapture && oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
        await oldController.dispose();
      }
      
      // small delay to let hardware release camera
      await Future.delayed(const Duration(milliseconds: 100));
      
      final currentDirection = widget.cameras[_selectedCameraIndex].lensDirection;
      final newDirection = currentDirection == CameraLensDirection.front 
          ? CameraLensDirection.back 
          : CameraLensDirection.front;
          
      int nextIndex = widget.cameras.indexWhere((c) => c.lensDirection == newDirection);
      if (nextIndex == -1) {
        // Fallback to simple cycle if opposite lens isn't found
        nextIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
      }
      
      _selectedCameraIndex = nextIndex;
      await _initCamera();
    } catch (e) {
      debugPrint('Error toggling camera: $e');
    }
    
    _isTogglingCamera = false;
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isTakingPicture) return;

    if (widget.isFaceCapture && !_isFaceDetected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please align face until oval turns green')),
      );
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      if (widget.isFaceCapture && controller.value.isStreamingImages) {
        try {
          await controller.stopImageStream();
        } catch (e) {
          debugPrint('Error stopping image stream: $e');
        }
        // Add a small delay to let the camera session stabilize
        await Future.delayed(const Duration(milliseconds: 300));
      }
      final XFile file = await controller.takePicture();
      if (mounted) {
        setState(() {
          _capturedFile = file;
          _isTakingPicture = false;
        });
      }
    } catch (e) {
      debugPrint('Take picture error: $e');
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to take picture')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
      );
    }

    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full Screen Preview / Captured Photo
          Positioned.fill(
            child: _capturedFile != null
                ? Image.file(
                    File(_capturedFile!.path),
                    fit: BoxFit.cover,
                  )
                : ClipRect(
                    child: Transform.scale(
                      scale: scale,
                      child: Center(
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
          ),

          // 1.5 Face Recognition Overlay
          if (widget.isFaceCapture && _capturedFile == null)
            Positioned.fill(
              child: CustomPaint(
                painter: _FaceOverlayPainter(
                  borderColor: _isFaceDetected ? Colors.greenAccent : Colors.redAccent,
                  blinkState: _blinkState,
                ),
              ),
            ),
            
          // 2. Overlaid Controls
          Positioned.fill(
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top controls row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                        if (_capturedFile == null && widget.cameras.length > 1)
                          IconButton(
                            icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
                            onPressed: _toggleCamera,
                          ),
                      ],
                    ),
                  ),

                  // Bottom controls row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30.0),
                    child: _capturedFile != null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _capturedFile = null;
                                  });
                                  if (widget.isFaceCapture) {
                                     _initCamera(); // restart stream
                                  }
                                },
                                icon: const Icon(Icons.refresh, color: Colors.white),
                                label: const Text('Retake', style: TextStyle(color: Colors.white, fontSize: 18)),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.pop(context, _capturedFile),
                                icon: const Icon(Icons.check),
                                label: const Text('Use Photo', style: TextStyle(fontSize: 18)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: _takePicture,
                                child: Container(
                                  height: 80,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: (widget.isFaceCapture && !_isFaceDetected) ? Colors.red : Colors.white,
                                      width: 4,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      height: 65,
                                      width: 65,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (widget.isFaceCapture && !_isFaceDetected) ? Colors.red.withOpacity(0.5) : Colors.white,
                                      ),
                                      child: _isTakingPicture
                                          ? const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.black,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceOverlayPainter extends CustomPainter {
  final Color borderColor;
  final int blinkState;

  _FaceOverlayPainter({
    this.borderColor = Colors.redAccent,
    this.blinkState = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2.2),
      width: size.width * 0.7,
      height: size.height * 0.5,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(rect)
      ..fillType = PathFillType.evenOdd;

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawOval(rect, borderPaint);

    String message = 'Align Face in Oval';
    if (blinkState == 1) message = 'Please blink your eyes';
    if (blinkState == 2) message = 'Open eyes...';
    if (blinkState == 3) message = 'Verified! Take Photo';

    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: TextStyle(
          color: borderColor,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        rect.top - 50,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FaceOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor || oldDelegate.blinkState != blinkState;
  }
}
