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
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
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

  Future<void> _uploadToDrive() async {
    final photoController = context.read<PhotoController>();
    final authController = context.read<AuthController>();
    
    final guideName = authController.currentUser?.fullName ?? 'Unknown Guide';

    final success = await photoController.uploadPhotos(
      guideName: guideName,
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
            title: const Text(
              'Photo Upload',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF0A0A23),
            foregroundColor: Colors.white,
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
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            'Uploading photos to Google Drive...',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            '${(photoController.uploadProgress * 100).toInt()}% complete',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(photoController.uploadProgress * photoController.selectedPhotos.length).toInt()} of ${photoController.selectedPhotos.length} photos uploaded',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 300,
            child: LinearProgressIndicator(
              value: photoController.uploadProgress,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_upload,
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Target: Norðurljósamyndir/${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
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
                color: Colors.orange.withOpacity(0.2),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Google Sign-In Required',
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You need to sign in with Google to upload photos to Drive.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange),
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
          const Text(
            'Date', 
            style: TextStyle(
              fontSize: 16, 
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _selectDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('EEEE, MMMM d, y').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const Icon(Icons.calendar_today, color: Colors.white),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Photo Selection Buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Photo Selection',
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect your camera to the tablet and select photos to upload directly to Google Drive',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Select Photos from Camera/Tablet'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () => photoController.clearPhotos(),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(color: Colors.red),
                  ),
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
            const Text(
              'Guide Name', 
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Text(
                guideName,
                style: const TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
} 