import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img_lib;
import 'package:http_parser/http_parser.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'api_config.dart';
import 'camera_page.dart';
import 'common_scaffold.dart';
import 'attendance_camera_page.dart';

class EmployeePhotoPage extends StatefulWidget {
  const EmployeePhotoPage({super.key});

  @override
  State<EmployeePhotoPage> createState() => _EmployeePhotoPageState();
}

class _EmployeePhotoPageState extends State<EmployeePhotoPage> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  Map<String, dynamic>? _employeeDoc;
  List<Map<String, dynamic>> _allEmployees = [];
  bool _isFetchingEmployees = true;

  @override
  void initState() {
    super.initState();
    _fetchAllEmployees();
  }

  Future<void> _fetchAllEmployees() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('Not logged in');

      // Fetch all employees (up to 500) for local search
      final url = '${ApiConfig.baseUrl}/employees?depth=1&limit=500';
      final response = await http.get(
        Uri.parse(url),
        headers: ApiConfig.getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data['docs'] as List?;
        if (docs != null) {
          if (mounted) {
            setState(() {
              _allEmployees = docs.cast<Map<String, dynamic>>();
              _isFetchingEmployees = false;
            });
          }
        }
      } else {
        if (mounted) {
           setState(() {
             _errorMessage = 'Failed to load employees list.';
             _isFetchingEmployees = false;
           });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading employees: $e';
          _isFetchingEmployees = false;
        });
      }
    }
  }

  String? _getEmployeePhotoUrl() {
    if (_employeeDoc == null) return null;
    final photo = _employeeDoc!['photo'] ?? _employeeDoc!['image'] ?? _employeeDoc!['Photo'];
    if (photo == null) return null;

    if (photo is Map) {
      final url = photo['url']?.toString();
      if (url != null && url.isNotEmpty) {
        if (url.startsWith('http')) return url;
        return '${ApiConfig.domain}$url';
      }
    } else if (photo is String) {
      if (photo.startsWith('http')) return photo;
      if (photo.startsWith('/')) return '${ApiConfig.domain}$photo';
    }
    return null;
  }

  String _extractRole(Map<String, dynamic> doc) {
    final role = doc['role'];
    if (role != null && role.toString().isNotEmpty) return role.toString();
    
    final team = doc['team'];
    if (team != null) {
      if (team is String) return team;
      if (team is Map) return team['name']?.toString() ?? 'N/A';
      if (team is List && team.isNotEmpty) {
        final first = team.first;
        if (first is String) return first;
        if (first is Map) return first['name']?.toString() ?? 'N/A';
      }
    }
    return 'N/A';
  }

  String _getRole() {
    if (_employeeDoc == null) return 'N/A';
    return _extractRole(_employeeDoc!);
  }

  Future<File> _prepareImageForUpload(File originalFile) async {
    try {
      if (!await originalFile.exists()) return originalFile;
      final length = await originalFile.length();
      if (length < 1500 * 1024) return originalFile;

      final bytes = await originalFile.readAsBytes();
      final image = img_lib.decodeImage(bytes);
      if (image == null) return originalFile;

      img_lib.Image resized = image;
      if (image.width > 1280 || image.height > 1280) {
        if (image.width > image.height) {
          resized = img_lib.copyResize(image, width: 1280);
        } else {
          resized = img_lib.copyResize(image, height: 1280);
        }
      }
      final compressedBytes = img_lib.encodeJpg(resized, quality: 70);
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/opt_employee_$timestamp.jpg');
      await tempFile.writeAsBytes(compressedBytes);
      return tempFile;
    } catch (_) {
      return originalFile;
    }
  }

  Future<String?> _uploadMedia(File file) async {
    final uploadFile = await _prepareImageForUpload(file);
    if (!await uploadFile.exists()) return null;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return null;

    final filename = 'employee_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final urlsToTry = [
      '${ApiConfig.baseUrl}/media?prefix=employee',
      '${ApiConfig.baseUrl}/media/?prefix=employee',
    ];

    for (final urlStr in urlsToTry) {
      try {
        final request = http.MultipartRequest('POST', Uri.parse(urlStr));
        request.followRedirects = false;
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['_payload'] = jsonEncode({
          'alt': 'Employee Photo',
          'prefix': 'employee',
        });
        request.fields['alt'] = 'Employee Photo';
        request.fields['prefix'] = 'employee';

        final multipartFile = await http.MultipartFile.fromPath(
          'file',
          uploadFile.path,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);

        final response = await request.send();
        final body = await response.stream.bytesToString();

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(body);
          final doc = data['doc'] ?? data;
          return doc['id']?.toString();
        }
      } catch (e) {
        debugPrint('Upload error: $e');
      }
    }
    return null;
  }

  Future<void> _updateEmployeePhoto(String mediaId) async {
    if (_employeeDoc == null) return;
    
    final docId = _employeeDoc!['id'];
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      
      final url = '${ApiConfig.baseUrl}/employees/$docId';
      final response = await http.patch(
        Uri.parse(url),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode({
          'photo': mediaId,
        }),
      );

      if (response.statusCode == 200) {
        // Re-fetch to get populated photo URL
        final fetchUrl = '${ApiConfig.baseUrl}/employees/$docId?depth=1';
        final fetchResp = await http.get(Uri.parse(fetchUrl), headers: ApiConfig.getHeaders(token));
        
        setState(() {
          _successMessage = 'Photo updated successfully!';
          if (fetchResp.statusCode == 200) {
            _employeeDoc = jsonDecode(fetchResp.body);
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to update employee record: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No camera found on this device')),
        );
      }
      return;
    }

    final XFile? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(cameras: cameras, isFaceCapture: true),
      ),
    );

    if (capturedFile != null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _successMessage = null;
      });

      // Validate Face Using ML Kit
      try {
        final inputImage = InputImage.fromFilePath(capturedFile.path);
        final faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: false,
            enableClassification: false,
            performanceMode: FaceDetectorMode.fast,
          ),
        );
        final faces = await faceDetector.processImage(inputImage);
        faceDetector.close();

        if (faces.isEmpty) {
          setState(() {
            _errorMessage = 'No human face detected! Please take the photo again, ensuring the face is clearly visible.';
            _isLoading = false;
          });
          return;
        }
        
        if (faces.length > 1) {
          setState(() {
            _errorMessage = 'Multiple faces detected! Please ensure only the employee is in the photo.';
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('Face detection error: $e');
        setState(() {
          _errorMessage = 'Face detection failed (Requires App Rebuild): $e';
          _isLoading = false;
        });
        return; // Block upload on error
      }

      final mediaId = await _uploadMedia(File(capturedFile.path));
      if (mediaId != null) {
        await _updateEmployeePhoto(mediaId);
      } else {
        setState(() {
          _errorMessage = 'Failed to upload photo';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'Employee Photo',
      pageType: PageType.employee, // No cart icon will be shown
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final cameras = await availableCameras();
                if (cameras.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No camera found on this device')),
                    );
                  }
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AttendanceCameraPage(
                      cameras: cameras,
                      employees: _allEmployees,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.fingerprint), // or face icon
              label: const Text('Take Attendance (Face Scan)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            
            const Text(
              'Search for an Employee to update their photo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
               Autocomplete<Map<String, dynamic>>(
                 optionsBuilder: (TextEditingValue textEditingValue) {
                   if (textEditingValue.text.isEmpty) {
                     return _allEmployees;
                   }
                   final search = textEditingValue.text.toLowerCase();
                   return _allEmployees.where((employee) {
                     final name = (employee['name'] ?? '').toString().toLowerCase();
                     final empId = (employee['employeeId'] ?? employee['employeeID'] ?? '').toString().toLowerCase();
                     return name.contains(search) || empId.contains(search);
                   });
                 },
                 displayStringForOption: (option) {
                   final name = (option['name']?.toString() ?? 'UNKNOWN').toUpperCase();
                   final role = _extractRole(option);
                   final id = option['employeeId'] ?? option['employeeID'] ?? 'N/A';
                   return '$name - $role ($id)';
                 },
                 fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                   return ValueListenableBuilder<TextEditingValue>(
                     valueListenable: controller,
                     builder: (context, value, child) {
                       return TextField(
                         controller: controller,
                         focusNode: focusNode,
                         onEditingComplete: onEditingComplete,
                         decoration: InputDecoration(
                           labelText: 'Search by Name or ID',
                           border: const OutlineInputBorder(),
                           prefixIcon: const Icon(Icons.search),
                           suffixIcon: value.text.isNotEmpty
                               ? IconButton(
                                   icon: const Icon(Icons.clear),
                                   onPressed: () {
                                     controller.clear();
                                     setState(() {
                                       _employeeDoc = null;
                                     });
                                   },
                                 )
                               : null,
                         ),
                       );
                     },
                   );
                 },
                 optionsViewBuilder: (context, onSelected, options) {
                   return Align(
                     alignment: Alignment.topLeft,
                     child: Material(
                       elevation: 4.0,
                       borderRadius: BorderRadius.circular(8.0),
                       child: ConstrainedBox(
                         constraints: const BoxConstraints(maxHeight: 250),
                         child: ListView.builder(
                           padding: EdgeInsets.zero,
                           shrinkWrap: true,
                           itemCount: options.length,
                           itemBuilder: (context, index) {
                             final option = options.elementAt(index);
                             final name = (option['name']?.toString() ?? 'UNKNOWN').toUpperCase();
                             final role = _extractRole(option);
                             final id = option['employeeId'] ?? option['employeeID'] ?? 'N/A';
                             final hasPhoto = option['photo'] != null && option['photo'].toString().isNotEmpty;
                             return InkWell(
                               onTap: () => onSelected(option),
                               child: Padding(
                                 padding: const EdgeInsets.all(16.0),
                                 child: Row(
                                   children: [
                                     Icon(
                                       Icons.check_circle,
                                       color: hasPhoto ? Colors.green : Colors.grey,
                                       size: 20,
                                     ),
                                     const SizedBox(width: 8),
                                     Expanded(
                                       child: RichText(
                                         text: TextSpan(
                                           style: const TextStyle(color: Colors.black, fontSize: 13), // reduced font size
                                           children: [
                                             TextSpan(
                                               text: name,
                                               style: const TextStyle(fontWeight: FontWeight.bold),
                                             ),
                                             TextSpan(
                                               text: ' - $role ($id)',
                                             ),
                                           ],
                                         ),
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                             );
                           },
                         ),
                       ),
                     ),
                   );
                 },
                 onSelected: (option) {
                   setState(() {
                     _employeeDoc = option;
                     _errorMessage = null;
                     _successMessage = null;
                   });
                 },
               ),
            const SizedBox(height: 24),
            
            if (_isLoading && !_isFetchingEmployees)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade50,
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.green.shade50,
                  child: Text(
                    _successMessage!,
                    style: TextStyle(color: Colors.green.shade900),
                  ),
                ),
                
              if (_employeeDoc != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee Details',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Divider(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_getEmployeePhotoUrl() != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 16.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.network(
                                    _getEmployeePhotoUrl()!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 100,
                                      height: 100,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(right: 16.0),
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: const Icon(Icons.person, size: 50, color: Colors.grey),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Name: ${_employeeDoc!['name'] ?? 'N/A'}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Role: ${_getRole()}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Take/Update Photo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
