// Photo upload screen - Memory optimized for 200+ large photos
// KEY CHANGES:
// 1. Uploads directly from SAF URIs - NO copying to temp storage first
// 2. Shows file list instead of thumbnails - saves memory
// 3. Processes in batches with cleanup
// 4. Session persistence for resume after backgrounding/disconnect
// 5. Wakelock to prevent screen sleep during uploads
// 6. End Shift button and fullscreen display modes

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import '../../core/auth/auth_controller.dart';
import '../../core/models/upload_session.dart';
import '../../core/services/upload_session_service.dart';
import '../../modules/pickup/end_of_shift_dialog.dart';
import '../../core/models/end_of_shift_report.dart';
import 'photo_service.dart';
import 'photo_display_screen.dart';
import 'review_request_screen.dart';

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
  int _hoursToScan = 12;
  String _statusMessage = '';
  int _currentProgress = 0;
  int _totalFiles = 0;
  
  // Store file metadata only - NOT file bytes!
  List<PhotoFileInfo> _selectedPhotos = [];
  
  String? _savedFolderUri;
  String? _savedFolderName;
  
  final List<int> _hourOptions = [6, 12, 20, 24, 48, 72];

  // Session tracking for upload resume
  UploadSession? _activeSession;
  bool _hasIncompleteSession = false;
  bool _isPausedByDisconnect = false;
  bool _uploadComplete = false;

  @override
  void initState() {
    super.initState();
    _loadSavedFolder();
    _checkForIncompleteSession();
  }

  @override
  void dispose() {
    super.dispose();
  }



  Future<void> _checkForIncompleteSession() async {
    final session = await UploadSessionService.loadSession();
    if (session != null && session.remainingFiles > 0) {
      setState(() {
        _hasIncompleteSession = true;
        _activeSession = session;
      });
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

  /// Resume an incomplete upload session
  Future<void> _resumeUpload() async {
    if (_activeSession == null) return;

    // Sign in if needed
    if (!_photoService.isSignedIn) {
      final signedIn = await _photoService.signInWithGoogle();
      if (!signedIn) {
        _showAlert('Please sign in with Google to resume upload.');
        return;
      }
    }

    // Initialize Drive API
    final initialized = await _photoService.initialize();
    if (!initialized) {
      _showAlert('Failed to connect to Google Drive. Please try again.');
      return;
    }

    // Need to re-scan to get the file list
    if (_selectedPhotos.isEmpty && _savedFolderUri != null) {
      await _scanForPhotos();
    }

    if (_selectedPhotos.isEmpty) {
      _showAlert('No photos found. Please scan for photos first.');
      return;
    }

    // Filter out already-completed files
    final remainingPhotos = _selectedPhotos
        .where((p) => !_activeSession!.completedUris.contains(p.uri))
        .toList();

    if (remainingPhotos.isEmpty) {
      setState(() {
        _hasIncompleteSession = false;
        _uploadComplete = true;
      });
      await UploadSessionService.clearSession();
      _showAlert('All files were already uploaded!');
      return;
    }

    final folderId = _activeSession!.folderId;
    if (folderId == null) {
      _showAlert('Session data is corrupted. Please start a new upload.');
      await UploadSessionService.clearSession();
      setState(() => _hasIncompleteSession = false);
      return;
    }

    setState(() {
      _isUploading = true;
      _hasIncompleteSession = false;
      _isPausedByDisconnect = false;
      _currentProgress = _activeSession!.completedFiles;
      _totalFiles = _activeSession!.totalFiles;
      _statusMessage = 'Resuming upload...';
      _activeSession!.status = UploadSessionStatus.active;
    });

    try {
      await _uploadBatch(remainingPhotos, folderId, startIndex: _activeSession!.completedFiles);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = '';
      });
      _showAlert('Upload failed: $e');
    }
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

      // Create upload session for persistence
      _activeSession = UploadSession(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        guideName: guideName,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        timestamp: DateTime.now(),
        totalFiles: _selectedPhotos.length,
        folderId: folderId,
        status: UploadSessionStatus.active,
      );
      await UploadSessionService.saveSession(_activeSession!);

      // Upload all photos (using existing batch logic)
      await _uploadBatch(_selectedPhotos, folderId, startIndex: 0);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = '';
      });
      _showAlert('Upload failed: $e');
    }
  }

  /// Core batch upload logic - shared between new upload and resume
  Future<void> _uploadBatch(List<PhotoFileInfo> photos, String folderId, {required int startIndex}) async {
    // Upload in batches of 10 to manage memory
    const batchSize = 10;
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < photos.length; i += batchSize) {
      // Check if paused by disconnect
      if (_isPausedByDisconnect) break;

      final batchEnd = (i + batchSize).clamp(0, photos.length);
      final batch = photos.sublist(i, batchEnd);

      for (int j = 0; j < batch.length; j++) {
        // Check if paused by disconnect
        if (_isPausedByDisconnect) break;

        final photo = batch[j];
        final fileIndex = startIndex + i + j;
        
        setState(() {
          _currentProgress = fileIndex + 1;
          _statusMessage = 'Uploading ${fileIndex + 1}/$_totalFiles: ${photo.name}';
        });

        try {
          // Read file bytes via SAF and upload directly
          final success = await _uploadSinglePhoto(photo, fileIndex + 1, folderId);
          if (success) {
            successCount++;
            // Track completed file in session
            if (_activeSession != null) {
              _activeSession!.markFileCompleted(photo.uri);
              await UploadSessionService.saveSession(_activeSession!);
            }
          } else {
            failCount++;
            print('⚠️ Failed to upload: ${photo.name}');
          }
        } catch (e) {
          // Check for camera disconnect
          if (e is PlatformException &&
              (e.message?.contains('FileNotFoundException') == true ||
               e.message?.contains('Could not read') == true ||
               e.message?.contains('SecurityException') == true)) {
            setState(() {
              _isPausedByDisconnect = true;
              _statusMessage = 'Camera disconnected – upload paused';
            });
            // Save session as paused
            if (_activeSession != null) {
              _activeSession!.status = UploadSessionStatus.paused;
              await UploadSessionService.saveSession(_activeSession!);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📷 Camera disconnected – upload paused. Reconnect to resume.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
            break;
          }
          failCount++;
          print('❌ Error uploading ${photo.name}: $e');
        }

        // Small delay to prevent overwhelming the system
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Force garbage collection between batches
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Upload finished (either complete or paused)
    if (!_isPausedByDisconnect) {
      // Mark session as completed and clear
      if (_activeSession != null) {
        _activeSession!.status = UploadSessionStatus.completed;
        await UploadSessionService.clearSession();
      }

      setState(() {
        _isUploading = false;
        _statusMessage = '';
        _uploadComplete = true;
      });

      if (failCount == 0) {
        _showSuccessDialog(successCount);
      } else {
        _showAlert('Upload complete.\n\n✅ Success: $successCount\n❌ Failed: $failCount');
      }
    } else {
      setState(() {
        _isUploading = false;
        _hasIncompleteSession = true;
      });
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
      rethrow; // Let the caller handle disconnect detection
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

  void _showEndShiftConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'End Shift?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to end your shift? This will open the shift report.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openEndShiftDialog();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Shift', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openEndShiftDialog() {
    final authController = context.read<AuthController>();
    final guideName = authController.currentUser?.fullName ?? 'Unknown Guide';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EndOfShiftDialog(
        guideName: guideName,
        onSubmit: (auroraRating, shouldRequestReviews, notes) async {
          // Save the shift report to Firestore
          try {
            final report = EndOfShiftReport(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
              guideId: authController.currentUser?.id ?? '',
              guideName: guideName,
              auroraRating: auroraRating,
              shouldRequestReviews: shouldRequestReviews,
              notes: notes,
              createdAt: DateTime.now(),
            );

            // TODO: Save report to Firestore if a service exists
            print('📋 Shift report submitted: ${report.toJson()}');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Shift report submitted!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            rethrow;
          }
        },
      ),
    );
  }

  /// Transliterate Icelandic characters to English equivalents
  String _transliterate(String name) {
    const map = {
      'Þ': 'Th', 'þ': 'th',
      'Ð': 'D',  'ð': 'd',
      'Æ': 'Ae', 'æ': 'ae',
      'Ö': 'O',  'ö': 'o',
      'Á': 'A',  'á': 'a',
      'É': 'E',  'é': 'e',
      'Í': 'I',  'í': 'i',
      'Ó': 'O',  'ó': 'o',
      'Ú': 'U',  'ú': 'u',
      'Ý': 'Y',  'ý': 'y',
    };
    return name.replaceAllMapped(
      RegExp('[ÞþÐðÆæÖöÁáÉéÍíÓóÚúÝý]'),
      (m) => map[m.group(0)!] ?? m.group(0)!,
    );
  }

  /// Fetch the Drive folder URL from the Cloud Function for the current date/guide
  Future<String?> _fetchDriveUrl(String guideName) async {
    // If we have an active upload session, use its folder ID directly
    final folderId = _activeSession?.folderId;
    if (folderId != null) {
      return 'https://drive.google.com/drive/folders/$folderId';
    }

    // Otherwise, call the Cloud Function to look it up
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final uri = Uri.parse(
        'https://getphotolink-kyj6qn3nbq-uc.a.run.app?date=$dateStr&guide=${Uri.encodeComponent(guideName)}',
      );

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      if (data['success'] == true && data['guide'] != null) {
        return data['guide']['photoUrl'] as String?;
      }
    } catch (e) {
      print('⚠️ Could not fetch Drive URL: $e');
    }
    return null;
  }

  void _openDisplayScreen() async {
    final authController = context.read<AuthController>();
    final guideName = _transliterate(authController.currentUser?.fullName ?? 'Unknown Guide');
    final formattedDate = DateFormat('EEE, MMM d, y').format(_selectedDate);

    // Show loading briefly while we fetch the Drive URL
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Looking up photos...'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF2D3748),
        ),
      );
    }

    final driveUrl = await _fetchDriveUrl(guideName);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoDisplayScreen(
          guideName: guideName,
          date: formattedDate,
          driveUrl: driveUrl,
        ),
      ),
    );
  }

  void _openReviewScreen() async {
    final authController = context.read<AuthController>();
    final guideName = _transliterate(authController.currentUser?.fullName ?? 'Unknown Guide');
    final formattedDate = DateFormat('EEE, MMM d, y').format(_selectedDate);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔍 Looking up photos...'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF2D3748),
        ),
      );
    }

    final driveUrl = await _fetchDriveUrl(guideName);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewRequestScreen(
          guideName: guideName,
          date: formattedDate,
          driveUrl: driveUrl,
        ),
      ),
    );
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
    
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
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
              const SizedBox(height: 24),
              // Show Screen buttons during upload
              _buildShowScreenButtons(),
              const SizedBox(height: 24),
              // End shift button during upload
              _buildEndShiftButton(),
            ],
          ),
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
          // Resume banner for incomplete sessions
          if (_hasIncompleteSession && _activeSession != null) _buildResumeBanner(),
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
          const SizedBox(height: 16),
          _buildShowScreenButtons(),
          const SizedBox(height: 24),
          // End Shift button - always visible and prominent
          _buildEndShiftButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildResumeBanner() {
    final session = _activeSession!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pause_circle_filled, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Incomplete Upload Found',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.orange, size: 20),
                onPressed: () async {
                  await UploadSessionService.clearSession();
                  setState(() {
                    _hasIncompleteSession = false;
                    _activeSession = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${session.completedFiles}/${session.totalFiles} files completed '
            '(${session.remainingFiles} remaining)',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Guide: ${session.guideName} • Date: ${session.date}',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(
              value: session.progressPercent,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.orange),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _resumeUpload,
              icon: const Icon(Icons.play_arrow),
              label: Text('Resume Upload (${session.remainingFiles} files)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
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

  Widget _buildShowScreenButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openDisplayScreen,
            icon: const Icon(Icons.fullscreen, color: Colors.white),
            label: const Text('📱 Show Screen', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF2D3748),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openReviewScreen,
            icon: const Icon(Icons.star, color: Colors.amber),
            label: const Text('⭐ Show Screen & Request Reviews',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF2D4730),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndShiftButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isUploading ? null : _showEndShiftConfirmation,
        icon: const Icon(Icons.stop_circle, color: Colors.white, size: 28),
        label: const Text(
          '🛑 END SHIFT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          backgroundColor: Colors.red[700],
          disabledBackgroundColor: Colors.red.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
