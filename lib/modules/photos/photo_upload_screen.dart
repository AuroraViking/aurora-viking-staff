// Photo upload screen for pulling from USB-C camera or gallery and auto-organizing to Drive 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import '../../core/auth/auth_controller.dart';
import 'photo_controller.dart';

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _customBusController = TextEditingController();
  String? _selectedBus;
  DateTime _selectedDate = DateTime.now();
  bool _isCustomBus = false;

  @override
  void dispose() {
    _customBusController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        final photoController = context.read<PhotoController>();
        final photos = images.map((xFile) => File(xFile.path)).toList();
        photoController.addPhotos(photos);
      }
    } catch (e) {
      print('Error picking images: $e');
    }
  }

  Future<void> _pickImagesFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        final photoController = context.read<PhotoController>();
        photoController.addPhotos([File(image.path)]);
      }
    } catch (e) {
      print('Error picking image from camera: $e');
    }
  }

  Future<void> _uploadToDrive() async {
    final photoController = context.read<PhotoController>();
    final authController = context.read<AuthController>();
    
    final guideName = authController.currentUser?.fullName ?? 'Unknown Guide';
    final busName = _isCustomBus ? _customBusController.text.trim() : _selectedBus ?? '';

    if (busName.isEmpty) {
      _showAlert('Please select or enter bus name.');
      return;
    }

    final success = await photoController.uploadPhotos(
      guideName: guideName,
      busName: busName,
      date: _selectedDate,
      context: context,
    );

    if (success) {
      _showSuccessDialog();
    } else {
      _showAlert('Upload failed: ${photoController.uploadError}');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Successful'),
        content: const Text('Successfully uploaded photos to Google Drive!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final photoController = context.read<PhotoController>();
              photoController.clearPhotos();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showAlert(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoController>(
      builder: (context, photoController, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Photo Upload'),
            actions: [
              // Google Sign-In Status
              Consumer<PhotoController>(
                builder: (context, controller, child) {
                  if (controller.isSignedIn) {
                    return PopupMenuButton<String>(
                      icon: const Icon(Icons.account_circle, color: Colors.green),
                      onSelected: (value) {
                        if (value == 'signout') {
                          controller.signOut();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'info',
                          enabled: false,
                          child: Text('Signed in as: ${controller.currentUserEmail ?? 'Unknown'}'),
                        ),
                        const PopupMenuItem(
                          value: 'signout',
                          child: Text('Sign Out'),
                        ),
                      ],
                    );
                  } else {
                    return IconButton(
                      icon: const Icon(Icons.account_circle, color: Colors.grey),
                      onPressed: () async {
                        final success = await controller.signInWithGoogle();
                        if (!success) {
                          _showAlert('Failed to sign in with Google. Please try again.');
                        }
                      },
                      tooltip: 'Sign in with Google',
                    );
                  }
                },
              ),
            ],
          ),
          body: photoController.isUploading ? _buildUploadProgress(photoController) : _buildMainContent(photoController),
        );
      },
    );
  }

  Widget _buildUploadProgress(PhotoController photoController) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Uploading photos...',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            '${(photoController.uploadProgress * 100).toInt()}% complete',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: photoController.uploadProgress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(PhotoController photoController) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Google Sign-In Status
          if (!photoController.isSignedIn) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Google Sign-In Required',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You need to sign in with Google to upload photos to Drive.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final success = await photoController.signInWithGoogle();
                      if (!success) {
                        _showAlert('Failed to sign in with Google. Please try again.');
                      }
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Guide Name Display
          _buildGuideNameDisplay(),

          const SizedBox(height: 20),

          // Date Selection
          const Text('Date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _selectDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('EEEE, MMMM d, y').format(_selectedDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Bus Selection
          const Text('Bus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _isCustomBus ? null : _selectedBus,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('Select bus'),
                  items: [
                    'Bus 1',
                    'Bus 2',
                    'Bus 3',
                    'Bus 4',
                    'Bus 5',
                  ].map((String bus) {
                    return DropdownMenuItem<String>(
                      value: bus,
                      child: Text(bus),
                    );
                  }).toList(),
                  onChanged: _isCustomBus ? null : (String? newValue) {
                    setState(() {
                      _selectedBus = newValue;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: _isCustomBus,
                onChanged: (bool? value) {
                  setState(() {
                    _isCustomBus = value ?? false;
                    if (_isCustomBus) {
                      _selectedBus = null;
                    }
                  });
                },
              ),
              const Text('Custom'),
            ],
          ),

          if (_isCustomBus) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customBusController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter bus name',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Photo Selection Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: photoController.isSignedIn ? _pickImagesFromCamera : null,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Selected Photos
          if (photoController.selectedPhotos.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selected Photos (${photoController.selectedPhotos.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => photoController.clearPhotos(),
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photoController.selectedPhotos.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        photoController.selectedPhotos[index],
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => photoController.removePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
          ],

          // Upload Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: photoController.selectedPhotos.isNotEmpty && photoController.isSignedIn ? _uploadToDrive : null,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload to Drive'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideNameDisplay() {
    return Consumer<AuthController>(
      builder: (context, authController, child) {
        final guideName = authController.currentUser?.fullName ?? 'Unknown Guide';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Guide Name', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: Text(
                guideName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      },
    );
  }
} 