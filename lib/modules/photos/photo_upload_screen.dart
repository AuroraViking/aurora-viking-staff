// Photo upload screen - Memory optimized for 200+ large photos
// KEY CHANGES:
// 1. Uploads directly from SAF URIs - NO copying to temp storage first
// 2. Shows file list instead of thumbnails - saves memory
// 3. Processes in batches with cleanup

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import '../../core/auth/auth_controller.dart';
import 'photo_service.dart';

const _channel = MethodChannel('com.auroraviking.aurora_viking_staff/saf');

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final PhotoService _photoService = PhotoService();
  
  DateTime _selectedDate = DateTime.now();
  bool _isScanning = false;
  bool _isUploading = false;
  int _hoursToScan = 20;
  String _statusMessage = '';
  int _currentProgress = 0;
  int _totalFiles = 0;
  
  // Store file metadata only - NOT file bytes!
  List<PhotoFileInfo> _selectedPhotos = [];
  
  String? _savedFolderUri;
  String? _savedFolderName;
  
  final List<int> _hourOptions = [6, 12, 20, 24, 48, 72];

  @override
  void initState() {
    super.initState();
    _loadSavedFolder();
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
      setState(() => _statusMessage = 'Opening folder picker...');
      
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
      setState(() => _statusMessage = '');
    }
  }

  /// Scan for photos - stores metadata only, NOT file bytes
  Future<void> _scanForPhotos() async {
    if (_savedFolderUri == null) {
      _showAlert('Please select the camera folder first.');
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning folder...';
      _selectedPhotos.clear();
    });

    try {
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
          _statusMessage = '';
        });
        _showAlert('No photos found from the last $_hoursToScan hours.');
        return;
      }

      // Store ONLY metadata - no file bytes loaded!
      final photos = result.map((item) {
        final map = item as Map;
        return PhotoFileInfo(
          uri: map['uri'] as String,
          name: map['name'] as String,
          size: (map['size'] as num?)?.toInt() ?? 0,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            (map['lastModified'] as num?)?.toInt() ?? 0,
          ),
        );
      }).toList();

      // Sort by date (newest first)
      photos.sort((a, b) => b.lastModified.compareTo(a.lastModified));

      setState(() {
        _selectedPhotos = photos;
        _isScanning = false;
        _statusMessage = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Found ${photos.length} photos (${_formatTotalSize(photos)})'),
          backgroundColor: Colors.green,
        ),
      );
    } on PlatformException catch (e) {
      setState(() {
        _isScanning = false;
        _statusMessage = '';
      });
      _showAlert('Error scanning: ${e.message}');
    }
  }

  String _formatTotalSize(List<PhotoFileInfo> photos) {
    final totalBytes = photos.fold<int>(0, (sum, p) => sum + p.size);
    final mb = totalBytes / (1024 * 1024);
    if (mb > 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _formatFileSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Upload photos directly from SAF URIs - NO copying first!
  Future<void> _uploadPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final authController = context.read<AuthController>();
    final guideName = authController.currentUser?.fullName ?? 'Unknown Guide';

    // Sign in if needed
    if (!_photoService.isSignedIn) {
      final signedIn = await _photoService.signInWithGoogle();
      if (!signedIn) {
        _showAlert('Please sign in with Google to upload photos.');
        return;
      }
    }

    // Initialize Drive API
    final initialized = await _photoService.initialize();
    if (!initialized) {
      _showAlert('Failed to connect to Google Drive. Please try again.');
      return;
    }

    setState(() {
      _isUploading = true;
      _currentProgress = 0;
      _totalFiles = _selectedPhotos.length;
      _statusMessage = 'Preparing upload...';
    });

    try {
      // Create folder structure first
      final year = _selectedDate.year.toString();
      final month = _getMonthName(_selectedDate.month);
      final day = _selectedDate.day.toString();
      final dateFolder = '$day $month';
      final folderPath = 'Norðurljósamyndir/$year/$month/$dateFolder/$guideName';

      setState(() => _statusMessage = 'Creating folder: $folderPath');

      final folderId = await _photoService.createFolderStructurePublic(folderPath);
      if (folderId == null) {
        throw Exception('Failed to create folder in Drive');
      }

      // Upload in batches of 10 to manage memory
      const batchSize = 10;
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < _selectedPhotos.length; i += batchSize) {
        final batchEnd = (i + batchSize).clamp(0, _selectedPhotos.length);
        final batch = _selectedPhotos.sublist(i, batchEnd);

        for (int j = 0; j < batch.length; j++) {
          final photo = batch[j];
          final fileIndex = i + j;
          
          setState(() {
            _currentProgress = fileIndex + 1;
            _statusMessage = 'Uploading ${fileIndex + 1}/${_selectedPhotos.length}: ${photo.name}';
          });

          try {
            // Read file bytes via SAF and upload directly
            final success = await _uploadSinglePhoto(photo, fileIndex + 1, folderId);
            if (success) {
              successCount++;
            } else {
              failCount++;
              print('⚠️ Failed to upload: ${photo.name}');
            }
          } catch (e) {
            failCount++;
            print('❌ Error uploading ${photo.name}: $e');
          }

          // Small delay to prevent overwhelming the system
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // Force garbage collection between batches
        await Future.delayed(const Duration(milliseconds: 100));
      }

      setState(() {
        _isUploading = false;
        _statusMessage = '';
      });

      if (failCount == 0) {
        _showSuccessDialog(successCount);
      } else {
        _showAlert('Upload complete.\n\n✅ Success: $successCount\n❌ Failed: $failCount');
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = '';
      });
      _showAlert('Upload failed: $e');
    }
  }

  /// Upload a single photo directly from SAF URI
  Future<bool> _uploadSinglePhoto(PhotoFileInfo photo, int index, String folderId) async {
    try {
      // Read bytes via SAF - streaming
      final bytes = await _channel.invokeMethod<Uint8List>('readFileStreaming', {
        'uri': photo.uri,
      });

      if (bytes == null || bytes.isEmpty) {
        print('❌ Could not read file: ${photo.name}');
        return false;
      }

      // Generate filename with index
      final fileName = '${index.toString().padLeft(3, '0')}_${photo.name}';

      // Upload to Drive
      final success = await _photoService.uploadBytesToDrive(
        bytes: bytes,
        fileName: fileName,
        folderId: folderId,
        mimeType: _getMimeType(photo.name),
      );

      return success;
    } catch (e) {
      print('❌ Upload error for ${photo.name}: $e');
      return false;
    }
  }

  String _getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'arw':
        return 'image/x-sony-arw';
      case 'raw':
        return 'image/raw';
      case 'cr2':
      case 'cr3':
        return 'image/x-canon-cr2';
      case 'nef':
        return 'image/x-nikon-nef';
      default:
        return 'application/octet-stream';
    }
  }

  String _getMonthName(int month) {
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return months[month];
  }

  void _showSuccessDialog(int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Successful! 🎉'),
        content: Text('Successfully uploaded $count photos to Google Drive!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _selectedPhotos.clear());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Upload', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0A0A23),
        foregroundColor: Colors.white,
        actions: [_buildAccountButton()],
      ),
      body: _isUploading ? _buildUploadProgress() : _buildMainContent(),
    );
  }

  Widget _buildAccountButton() {
    final isSignedIn = _photoService.isSignedIn;
    if (isSignedIn) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.account_circle, color: Colors.green),
        onSelected: (v) async {
          if (v == 'signout') {
            await _photoService.signOut();
            setState(() {});
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'info', 
            enabled: false, 
            child: Text(_photoService.currentUserEmail ?? ''),
          ),
          const PopupMenuItem(value: 'signout', child: Text('Sign Out')),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.account_circle, color: Colors.grey),
      onPressed: () async {
        await _photoService.signInWithGoogle();
        setState(() {});
      },
    );
  }

  Widget _buildUploadProgress() {
    final progress = _totalFiles > 0 ? _currentProgress / _totalFiles : 0.0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.green)),
            const SizedBox(height: 24),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$_currentProgress / $_totalFiles photos',
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 18),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 300,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.green),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            // Tour information for photo requests
            Consumer<AuthController>(
              builder: (context, auth, _) {
                final guideName = auth.currentUser?.fullName ?? 'Unknown Guide';
                final formattedDate = DateFormat('EEE, MMM d, y').format(_selectedDate);
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            formattedDate,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            guideName,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.email, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'photo@auroraviking.com',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Request photos using this email',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_photoService.isSignedIn) _buildSignInWarning(),
          _buildCameraFolderSection(),
          const SizedBox(height: 16),
          _buildGuideAndDate(),
          const SizedBox(height: 20),
          _buildScanSection(),
          const SizedBox(height: 20),
          if (_selectedPhotos.isNotEmpty) ...[
            _buildPhotoList(),
            const SizedBox(height: 20),
          ],
          _buildUploadButton(),
        ],
      ),
    );
  }

  Widget _buildSignInWarning() {
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
            onPressed: () async {
              await _photoService.signInWithGoogle();
              setState(() {});
            },
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
              label: Text(hasFolder ? 'Change Folder' : 'Select Camera Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasFolder ? Colors.grey[700] : Colors.blue,
              ),
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

  Widget _buildScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time range chips
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

        // Scan button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _scanForPhotos,
            icon: _isScanning
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.search),
            label: Text(_isScanning ? _statusMessage : 'Scan for Photos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
            ),
          ),
        ),
      ],
    );
  }

  /// Shows a lightweight list of files - NO thumbnails to save memory!
  Widget _buildPhotoList() {
    final totalSize = _formatTotalSize(_selectedPhotos);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedPhotos.length} Photos Selected',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Total size: $totalSize',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
            TextButton(
              onPressed: () => setState(() => _selectedPhotos.clear()),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Show list of file names - NOT thumbnails (saves memory!)
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _selectedPhotos.length,
            itemBuilder: (_, i) {
              final photo = _selectedPhotos[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  photo.name.toLowerCase().endsWith('.arw') ? Icons.raw_on : Icons.image,
                  color: Colors.white54,
                  size: 20,
                ),
                title: Text(
                  photo.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_formatFileSize(photo.size)} • ${DateFormat('HH:mm').format(photo.lastModified)}',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                  onPressed: () => setState(() => _selectedPhotos.removeAt(i)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    final canUpload = _selectedPhotos.isNotEmpty && _photoService.isSignedIn;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canUpload ? _uploadPhotos : null,
        icon: const Icon(Icons.cloud_upload),
        label: Text(_selectedPhotos.isEmpty
            ? 'Scan for Photos First'
            : 'Upload ${_selectedPhotos.length} Photos'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: Colors.blue,
          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
        ),
      ),
    );
  }
}

/// Lightweight photo info - stores metadata only, NOT file bytes!
class PhotoFileInfo {
  final String uri;
  final String name;
  final int size;
  final DateTime lastModified;

  PhotoFileInfo({
    required this.uri,
    required this.name,
    required this.size,
    required this.lastModified,
  });
}
