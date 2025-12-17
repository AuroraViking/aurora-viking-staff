// Photo upload screen - Uses SAF with streaming file copy (no memory crashes)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/auth/auth_controller.dart';
import 'photo_controller.dart';

const _channel = MethodChannel('com.auroraviking.aurora_viking_staff/saf');

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  bool _isScanning = false;
  int _hoursToScan = 20;
  String _scanStatus = '';
  int _copyProgress = 0;
  int _copyTotal = 0;

  String? _savedFolderUri;
  String? _savedFolderName;

  final List<int> _hourOptions = [6, 12, 20, 24, 48, 72];

  @override
  void initState() {
    super.initState();
    _loadSavedFolder();
    _restorePhotosIfExists();
  }

  /// Restore photos from previous session if app was closed
  Future<void> _restorePhotosIfExists() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDocDir.path}/camera_photos');
      
      if (await photosDir.exists()) {
        final files = await photosDir.list().toList();
        final imageFiles = files.whereType<File>().where((f) {
          final ext = f.path.toLowerCase();
          return ext.endsWith('.jpg') || ext.endsWith('.jpeg') || 
                 ext.endsWith('.arw') || ext.endsWith('.raw') || 
                 ext.endsWith('.cr2') || ext.endsWith('.cr3') || 
                 ext.endsWith('.nef') || ext.endsWith('.heic') || 
                 ext.endsWith('.png');
        }).toList();
        
        if (imageFiles.isNotEmpty) {
          // Wait a bit for the widget tree to be ready
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (mounted) {
            final photoController = context.read<PhotoController>();
            // Only restore if no photos are currently selected
            if (photoController.selectedPhotos.isEmpty) {
              photoController.addPhotos(imageFiles);
              print('✅ Restored ${imageFiles.length} photos from previous session');
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error restoring photos: $e');
    }
  }

  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedFolderUri = prefs.getString('saf_folder_uri');
      _savedFolderName = prefs.getString('saf_folder_name');
    });
  }

  Future<void> _saveFolder(String uri, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saf_folder_uri', uri);
    await prefs.setString('saf_folder_name', name);
    setState(() {
      _savedFolderUri = uri;
      _savedFolderName = name;
    });
  }

  Future<void> _selectCameraFolder() async {
    try {
      setState(() => _scanStatus = 'Opening folder picker...');

      final result = await _channel.invokeMethod<Map>('pickFolder');

      if (result != null) {
        final uri = result['uri'] as String;
        final name = result['name'] as String? ?? 'Selected Folder';
        await _saveFolder(uri, name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Selected: $name'), backgroundColor: Colors.green),
          );
        }
      }
    } on PlatformException catch (e) {
      _showAlert('Error: ${e.message}');
    } finally {
      setState(() => _scanStatus = '');
    }
  }

  Future<void> _autoSelectRecentPhotos() async {
    if (_savedFolderUri == null) {
      _showAlert('Please select the camera folder first.\n\nTap "Select Camera Folder" and navigate to your camera\'s DCIM folder.');
      return;
    }

    setState(() {
      _isScanning = true;
      _scanStatus = 'Scanning folder...';
      _copyProgress = 0;
      _copyTotal = 0;
    });

    try {
      // Step 1: List files
      final cutoffMs = DateTime.now()
          .subtract(Duration(hours: _hoursToScan))
          .millisecondsSinceEpoch;

      final result = await _channel.invokeMethod<List>('listFiles', {
        'uri': _savedFolderUri,
        'cutoffTime': cutoffMs,
        'extensions': ['jpg', 'jpeg', 'arw', 'raw', 'cr2', 'cr3', 'nef', 'heic', 'png'],
      });

      if (result == null || result.isEmpty) {
        setState(() {
          _isScanning = false;
          _scanStatus = '';
        });
        _showAlert('No photos found from the last $_hoursToScan hours.');
        return;
      }

      // Step 2: Get application documents directory (persists across app restarts)
      final appDocDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDocDir.path}/camera_photos');

      // Only clean up if starting a new scan (don't delete existing photos)
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      setState(() {
        _copyTotal = result.length;
        _scanStatus = 'Copying 0/${result.length}...';
      });

      // Step 3: Copy files ONE AT A TIME using streaming
      final List<File> photoFiles = [];

      for (int i = 0; i < result.length; i++) {
        final fileInfo = result[i] as Map;
        final fileUri = fileInfo['uri'] as String;
        final fileName = fileInfo['name'] as String;
        final destPath = '${photosDir.path}/$fileName';

        try {
          // Update progress before copy
          setState(() {
            _copyProgress = i;
            _scanStatus = 'Copying ${i + 1}/${result.length}...';
          });
          
          // Allow UI to update
          await Future.delayed(const Duration(milliseconds: 50));

          // Use native streaming copy - doesn't load file into memory
          final copyResult = await _channel.invokeMethod<Map>('copyFileToPath', {
            'sourceUri': fileUri,
            'destPath': destPath,
          });

          print('📋 Copy result for $fileName: $copyResult');
          
          if (copyResult != null) {
            // Check both boolean and int success values (Kotlin might return int)
            final success = copyResult['success'];
            final isSuccess = success == true || success == 1;
            
            if (isSuccess) {
              final file = File(destPath);
              if (await file.exists()) {
                final size = await file.length();
                if (size > 0) {
                  print('✅ Copied $fileName (${(size / 1024 / 1024).toStringAsFixed(1)}MB)');
                  photoFiles.add(file);
                } else {
                  print('❌ File exists but is empty: $destPath');
                }
              } else {
                print('❌ File copied but not found at: $destPath');
              }
            } else {
              print('❌ Copy failed for $fileName: success=$success, result=$copyResult');
            }
          } else {
            print('❌ Copy result is null for $fileName');
          }
          
          // Update progress after copy
          setState(() {
            _copyProgress = i + 1;
          });
        } catch (e, stackTrace) {
          print('⚠️ Error copying $fileName: $e');
          print('Stack: $stackTrace');
          // Continue with next file
        }
      }

      setState(() {
        _isScanning = false;
        _scanStatus = '';
        _copyProgress = 0;
        _copyTotal = 0;
      });

      print('📊 Copy complete: ${photoFiles.length} files successfully copied out of ${result.length}');

      if (photoFiles.isNotEmpty) {
        final photoController = context.read<PhotoController>();
        photoController.addPhotos(photoFiles);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Loaded ${photoFiles.length} photo${photoFiles.length == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showAlert(
          'Failed to copy photos.\n\n'
          'Found ${result.length} photos but none were copied successfully.\n\n'
          'Please check:\n'
          '• Camera is still connected\n'
          '• Try selecting the folder again\n'
          '• Check device storage space'
        );
      }
    } on PlatformException catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = '';
      });
      _showAlert('Error: ${e.message}');
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = '';
      });
      _showAlert('Error: $e');
    }
  }

  Future<void> _pickImagesManually() async {
    try {
      final images = await _picker.pickMultiImage();
      if (images.isEmpty) return;

      final files = images.map((x) => File(x.path)).toList();
      context.read<PhotoController>().addPhotos(files);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected ${files.length} photos')),
      );
    } catch (e) {
      _showAlert('Error: $e');
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload Successful'),
          content: const Text('Photos uploaded to Google Drive!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                photoController.clearPhotos();
                // Clean up temp files
                _cleanupTempFiles();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      _showAlert('Upload failed: ${photoController.uploadError}');
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      // Only clean up after successful upload
      final appDocDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDocDir.path}/camera_photos');
      if (await photosDir.exists()) {
        await photosDir.delete(recursive: true);
        print('✅ Cleaned up photo cache');
      }
    } catch (e) {
      print('Cleanup error: $e');
    }
  }

  void _showAlert(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhotoController>(
      builder: (context, photoController, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Photo Upload', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF0A0A23),
            foregroundColor: Colors.white,
            actions: [_buildAccountButton(photoController)],
          ),
          body: photoController.isUploading
              ? _buildUploadProgress(photoController)
              : _buildMainContent(photoController),
        );
      },
    );
  }

  Widget _buildAccountButton(PhotoController ctrl) {
    if (ctrl.isSignedIn) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.account_circle, color: Colors.green),
        onSelected: (v) { if (v == 'signout') ctrl.signOut(); },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'info', enabled: false, child: Text(ctrl.currentUserEmail ?? '')),
          const PopupMenuItem(value: 'signout', child: Text('Sign Out')),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.account_circle, color: Colors.grey),
      onPressed: () => ctrl.signInWithGoogle(),
    );
  }

  Widget _buildUploadProgress(PhotoController ctrl) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white)),
          const SizedBox(height: 24),
          Text('${(ctrl.uploadProgress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          Text('${(ctrl.uploadProgress * ctrl.selectedPhotos.length).toInt()} / ${ctrl.selectedPhotos.length}',
              style: TextStyle(color: Colors.white.withOpacity(0.7))),
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
          if (!photoController.isSignedIn) _buildSignInWarning(photoController),
          _buildCameraFolderSection(),
          const SizedBox(height: 16),
          _buildGuideAndDate(),
          const SizedBox(height: 20),
          _buildPhotoSelectionSection(),
          const SizedBox(height: 20),
          if (photoController.selectedPhotos.isNotEmpty) ...[
            _buildSelectedPhotos(photoController),
            const SizedBox(height: 20),
          ],
          _buildUploadButton(photoController),
        ],
      ),
    );
  }

  Widget _buildSignInWarning(PhotoController ctrl) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => ctrl.signInWithGoogle(),
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraFolderSection() {
    final hasFolder = _savedFolderUri != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasFolder ? Colors.green.withOpacity(0.15) : Colors.blue.withOpacity(0.15),
        border: Border.all(color: hasFolder ? Colors.green : Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasFolder ? Icons.folder_open : Icons.usb,
                  color: hasFolder ? Colors.green : Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasFolder ? 'Camera Folder Selected' : 'Select Camera Folder',
                      style: TextStyle(
                        color: hasFolder ? Colors.green : Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (hasFolder)
                      Text(_savedFolderName ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectCameraFolder,
              icon: const Icon(Icons.folder_open),
              label: Text(hasFolder ? 'Change Folder' : 'Select Camera Folder (DCIM)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasFolder ? Colors.grey[700] : Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (!hasFolder)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Navigate to: Disk → DCIM → 100MSDCF',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGuideAndDate() {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70),
                  const SizedBox(width: 12),
                  Text(auth.currentUser?.fullName ?? 'Unknown',
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white70),
                    const SizedBox(width: 12),
                    Text(DateFormat('EEE, MMM d, y').format(_selectedDate),
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time range
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Last ', style: TextStyle(color: Colors.white70)),
              ..._hourOptions.map((h) {
                final sel = _hoursToScan == h;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${h}h'),
                    selected: sel,
                    onSelected: (_) => setState(() => _hoursToScan = h),
                    selectedColor: Colors.green,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.white70,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Colors.white.withOpacity(0.1),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Auto-select button with progress
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _autoSelectRecentPhotos,
            icon: _isScanning
                ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.auto_awesome),
            label: Text(_isScanning ? _scanStatus : 'Auto-Select from Camera'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),

        // Progress bar when copying
        if (_isScanning && _copyTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _copyProgress / _copyTotal,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.green),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_copyProgress / $_copyTotal files',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Manual
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickImagesManually,
            icon: const Icon(Icons.photo_library),
            label: const Text('Manual Selection'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.blue),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedPhotos(PhotoController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${ctrl.selectedPhotos.length} Photos',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () {
                ctrl.clearPhotos();
                _cleanupTempFiles();
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6,
          ),
          itemCount: ctrl.selectedPhotos.length,
          itemBuilder: (_, i) => Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(ctrl.selectedPhotos[i],
                    width: double.infinity, height: double.infinity,
                    fit: BoxFit.cover, cacheWidth: 200),
              ),
              Positioned(
                top: 2, right: 2,
                child: GestureDetector(
                  onTap: () => ctrl.removePhoto(i),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton(PhotoController ctrl) {
    final ok = ctrl.selectedPhotos.isNotEmpty && ctrl.isSignedIn;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: ok ? _uploadToDrive : null,
        icon: const Icon(Icons.cloud_upload),
        label: Text(ctrl.selectedPhotos.isEmpty
            ? 'Select Photos First'
            : 'Upload ${ctrl.selectedPhotos.length} Photos'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
        ),
      ),
    );
  }
}