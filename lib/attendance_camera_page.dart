import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'api_config.dart';

class AttendanceCameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final List<Map<String, dynamic>> employees;

  const AttendanceCameraPage({
    super.key,
    required this.cameras,
    required this.employees,
  });

  @override
  State<AttendanceCameraPage> createState() => _AttendanceCameraPageState();
}

class _AttendanceCameraPageState extends State<AttendanceCameraPage> {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  
  FaceDetector? _faceDetector;
  bool _isProcessingImage = false;
  bool _isFaceDetected = false;
  int _blinkState = 0;

  bool _initialCameraSet = false;
  bool _isVerifying = false;

  // Verification results
  String? _verifiedName;
  String? _punchAction;
  String? _punchTime;
  bool _isRecognized = false;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    
    if (!_initialCameraSet) {
      final frontIdx = widget.cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (frontIdx != -1) _selectedCameraIndex = frontIdx;
      _initialCameraSet = true;
    }

    if (_controller != null) {
      // Camera already initialized, just restart stream if needed
      if (!_controller!.value.isStreamingImages) {
        try {
          await _controller!.startImageStream(_processCameraImage);
        } catch (e) {
          debugPrint('Error restarting stream: $e');
        }
      }
      return;
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
      if (_faceDetector != null) {
        controller.startImageStream(_processCameraImage);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _swapCamera() async {
    final oldController = _controller;
    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
        await oldController.dispose();
      } catch (e) {
        debugPrint('Error disposing old controller: $e');
      }
      _controller = null;
    }

    if (mounted) {
      setState(() {
        _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
      });
      _initCamera();
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || _faceDetector == null || !mounted || _isVerifying || _isRecognized) return;
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
            if (left > 0.7 && right > 0.7) {
              _blinkState = 3;
              _isFaceDetected = true;
              _triggerVerification(); // Liveness passed! Send to backend
            }
          }
          
          if (_blinkState != 3) {
             setState(() {});
          }
        } else {
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

  Future<void> _triggerVerification() async {
    setState(() {
      _isVerifying = true;
    });

    final controller = _controller;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        try {
          await controller.stopImageStream();
        } catch (e) {
          debugPrint('Error stopping image stream: $e');
        }
      }
      // Add a small delay to let the camera session stabilize
      await Future.delayed(const Duration(milliseconds: 300));
    }
    
    try {
      final XFile file = await controller!.takePicture();
      
      // Hit the real backend face-recognize endpoint
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        throw Exception('Not logged in');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/face-recognize'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath('image', file.path),
      );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final data = jsonDecode(responseBody);

      if (data['matched'] == true && mounted) {
        final employee = data['employee'];
        final name = (employee['name']?.toString() ?? 'UNKNOWN').toUpperCase();
        final action = data['action'] == 'punch_out' ? 'Punch Out' : 'Punch In';

        setState(() {
          _isRecognized = true;
          _isVerifying = false;
          _verifiedName = name;
          _punchAction = action;
          _punchTime = DateFormat('hh:mm a').format(DateTime.now());
        });
        
        // Auto reset after 4 seconds
        Future.delayed(const Duration(seconds: 4), () {
           if (mounted) {
             setState(() {
               _isRecognized = false;
               _blinkState = 0;
               _isFaceDetected = false;
             });
             _initCamera(); // restart stream for next person
           }
        });
      } else if (mounted) {
        // No match found
        final errorMsg = data['error']?.toString() ?? 'Face not recognized';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
        setState(() {
          _isVerifying = false;
          _blinkState = 0;
          _isFaceDetected = false;
        });
        await Future.delayed(const Duration(seconds: 1));
        _initCamera();
      }
    } catch (e) {
      debugPrint('Verification error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isVerifying = false;
        _blinkState = 0;
      });
      if (controller != null) await _initCamera();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().whenComplete(() {
          controller.dispose();
        });
      } else {
        controller.dispose();
      }
    }
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: scale,
                child: Center(
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),

          // Face Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _AttendanceOverlayPainter(
                borderColor: _isRecognized ? Colors.greenAccent : Colors.redAccent,
                blinkState: _blinkState,
                isVerifying: _isVerifying,
                isRecognized: _isRecognized,
              ),
            ),
          ),
          
          // Result Card
          if (_isRecognized)
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _verifiedName ?? '',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _punchAction == 'Punch In' ? Icons.login : Icons.logout,
                          color: _punchAction == 'Punch In' ? Colors.green : Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_punchAction \u2714',
                          style: TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.bold,
                            color: _punchAction == 'Punch In' ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _punchTime ?? '',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

          // Top Back Button
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          // Verifying Spinner
          if (_isVerifying)
             const Center(
               child: CircularProgressIndicator(color: Colors.white),
             ),
        ],
      ),
    );
  }
}

class _AttendanceOverlayPainter extends CustomPainter {
  final Color borderColor;
  final int blinkState;
  final bool isVerifying;
  final bool isRecognized;

  _AttendanceOverlayPainter({
    required this.borderColor,
    required this.blinkState,
    required this.isVerifying,
    required this.isRecognized,
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
      ..strokeWidth = 4.0;

    canvas.drawOval(rect, borderPaint);

    String message = 'Align Face in Oval';
    if (isRecognized) {
       message = 'Access Granted!';
    } else if (isVerifying) {
       message = 'Identifying...';
    } else {
       if (blinkState == 1) message = 'Please blink your eyes';
       if (blinkState == 2) message = 'Open eyes...';
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: TextStyle(
          color: borderColor,
          fontSize: 24,
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
  bool shouldRepaint(covariant _AttendanceOverlayPainter oldDelegate) {
    return true; // repaint frequently during stream
  }
}
