// Web photo & video upload screen
// Splits files into chunks, sends via Cloud Functions (callable),
// Cloud Function stores in GCS via admin SDK, then assembles and uploads to Drive.
// No Firebase Storage client SDK needed. No Google Sign-In needed.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/auth_controller.dart';
import 'photo_display_screen.dart';
import 'review_request_screen.dart';

class WebPhotoUploadScreen extends StatefulWidget {
  const WebPhotoUploadScreen({super.key});

  @override
  State<WebPhotoUploadScreen> createState() => _WebPhotoUploadScreenState();
}

class _WebPhotoUploadScreenState extends State<WebPhotoUploadScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isUploading = false;
  String _statusMessage = '';
  double _overallProgress = 0;
  int _currentFileIndex = 0;
  int _totalFiles = 0;

  List<_WebFileInfo> _selectedFiles = [];

  // 5 MB chunks = ~6.7 MB base64, well under 10 MB callable limit
  static const int _chunkSize = 5 * 1024 * 1024;

  static const _allowedExtensions = [
    'jpg', 'jpeg', 'png', 'heic', 'arw', 'raw', 'cr2', 'cr3', 'nef',
    'mp4', 'mov', 'avi', 'mkv', 'mts', 'webm',
  ];

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final newFiles = <_WebFileInfo>[];
      for (final file in result.files) {
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          newFiles.add(_WebFileInfo(name: file.name, bytes: file.bytes!, size: file.size));
        }
      }
      if (newFiles.isEmpty) { _showAlert('Could not read selected files.'); return; }

      setState(() => _selectedFiles.addAll(newFiles));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Added ${newFiles.length} file(s) (${_formatTotalSize()})'), backgroundColor: Colors.green),
        );
      }
    } catch (e) { _showAlert('Error picking files: $e'); }
  }

  Future<void> _pickFolder() async {
    try {
      // Use package:web to create an input with webkitdirectory for folder selection
      final input = web.HTMLInputElement()
        ..type = 'file'
        ..multiple = true;
      input.setAttribute('webkitdirectory', '');
      input.setAttribute('directory', '');

      input.click();

      await input.onChange.first;
      final files = input.files;
      if (files == null || files.length == 0) return;

      setState(() => _statusMessage = 'Reading folder...');

      final allowedExts = _allowedExtensions.toSet();
      final newFiles = <_WebFileInfo>[];

      for (int i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file == null) continue;

        final ext = file.name.toLowerCase().split('.').last;
        if (!allowedExts.contains(ext)) continue;
        if (file.size == 0) continue;

        // Read file data using FileReader
        final reader = web.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoadEnd.first;

        final result = reader.result;
        if (result != null) {
          final bytes = (result as JSArrayBuffer).toDart.asUint8List();
          newFiles.add(_WebFileInfo(
            name: file.name,
            bytes: bytes,
            size: file.size,
          ));
        }
      }

      if (newFiles.isEmpty) {
        _showAlert('No supported photo/video files found in the folder.');
        return;
      }

      setState(() {
        _selectedFiles.addAll(newFiles);
        _statusMessage = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📁 Added ${newFiles.length} file(s) from folder (${_formatTotalSize()})'), backgroundColor: Colors.green),
        );
      }
    } catch (e) { _showAlert('Error reading folder: $e'); }
  }

  String _formatTotalSize() {
    final mb = _selectedFiles.fold<int>(0, (s, f) => s + f.size) / (1024 * 1024);
    return mb > 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.toStringAsFixed(0)} MB';
  }

  String _formatFileSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb < 1 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${mb.toStringAsFixed(1)} MB';
  }

  bool _isVideoFile(String name) =>
      ['mp4', 'mov', 'avi', 'mkv', 'mts', 'webm'].contains(name.toLowerCase().split('.').last);

  String _transliterate(String name) {
    const map = {
      'Þ':'Th','þ':'th','Ð':'D','ð':'d','Æ':'Ae','æ':'ae','Ö':'O','ö':'o',
      'Á':'A','á':'a','É':'E','é':'e','Í':'I','í':'i','Ó':'O','ó':'o',
      'Ú':'U','ú':'u','Ý':'Y','ý':'y',
    };
    return name.replaceAllMapped(RegExp('[ÞþÐðÆæÖöÁáÉéÍíÓóÚúÝý]'), (m) => map[m.group(0)!] ?? m.group(0)!);
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty) return;

    final authController = context.read<AuthController>();
    final guideName = _transliterate(authController.currentUser?.fullName ?? 'Unknown Guide');
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');

    setState(() {
      _isUploading = true;
      _overallProgress = 0;
      _currentFileIndex = 0;
      _totalFiles = _selectedFiles.length;
      _statusMessage = 'Creating Drive folder...';
    });

    try {
      // Step 1: Create Drive folder
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final prepareResult = await functions.httpsCallable('preparePhotoUpload').call({
        'guideName': guideName, 'date': dateStr,
      });
      final folderId = (prepareResult.data as Map<String, dynamic>)['folderId'] as String;

      int successCount = 0;
      int failCount = 0;
      String lastError = '';

      // Step 2: Upload each file in chunks
      for (int i = 0; i < _selectedFiles.length; i++) {
        final file = _selectedFiles[i];
        _currentFileIndex = i + 1;

        try {
          await _uploadSingleFile(functions, file, folderId, i + 1);
          successCount++;
        } catch (e) {
          failCount++;
          lastError = e.toString();
          debugPrint('❌ Failed for ${file.name}: $lastError');
        }
      }

      setState(() { _isUploading = false; _statusMessage = ''; });

      if (failCount == 0) {
        _showSuccessDialog(successCount);
      } else {
        _showAlert('Upload complete.\n\n✅ Success: $successCount\n❌ Failed: $failCount\n\nError: $lastError');
      }
    } catch (e) {
      setState(() { _isUploading = false; _statusMessage = ''; });
      _showAlert('Upload failed: $e');
    }
  }

  Future<void> _uploadSingleFile(
    FirebaseFunctions functions, _WebFileInfo file, String folderId, int fileIndex,
  ) async {
    final bytes = file.bytes;
    final totalChunks = (bytes.length / _chunkSize).ceil();
    final uploadId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';

    debugPrint('📤 Uploading ${file.name}: ${_formatFileSize(file.size)}, $totalChunks chunks');

    // Send chunks
    for (int c = 0; c < totalChunks; c++) {
      final start = c * _chunkSize;
      final end = min(start + _chunkSize, bytes.length);
      final chunk = bytes.sublist(start, end);
      final b64 = base64Encode(chunk);

      setState(() {
        final fileProgress = (c + 1) / totalChunks;
        _overallProgress = ((_currentFileIndex - 1) + fileProgress) / _totalFiles;
        _statusMessage = 'Uploading ${file.name}\nChunk ${c + 1}/$totalChunks • File $_currentFileIndex/$_totalFiles';
      });

      await functions.httpsCallable('uploadFileChunk',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
      ).call({
        'uploadId': uploadId,
        'chunkIndex': c,
        'totalChunks': totalChunks,
        'chunkData': b64,
        'fileName': file.name,
      });
    }

    // Finalize: assemble chunks and upload to Drive
    setState(() {
      _statusMessage = 'Saving ${file.name} to Drive...\nFile $_currentFileIndex/$_totalFiles';
    });

    await functions.httpsCallable('finalizeFileUpload',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    ).call({
      'uploadId': uploadId,
      'fileName': file.name,
      'folderId': folderId,
      'fileIndex': fileIndex,
      'totalChunks': totalChunks,
    });

    debugPrint('✅ ${file.name} uploaded to Drive');
  }

  void _showSuccessDialog(int count) => showDialog(context: context, builder: (ctx) => AlertDialog(
    title: const Text('Upload Successful! 🎉'), content: Text('$count file(s) uploaded to Google Drive!'),
    actions: [TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _selectedFiles.clear()); }, child: const Text('OK'))],
  ));

  void _showAlert(String msg) => showDialog(context: context, builder: (ctx) => AlertDialog(
    content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
  ));

  Future<void> _selectDate() async {
    final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<String?> _fetchDriveUrl(String guideName) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final uri = Uri.parse('https://getphotolink-kyj6qn3nbq-uc.a.run.app?date=$dateStr&guide=${Uri.encodeComponent(guideName)}');
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final data = json.decode(r.body) as Map<String, dynamic>;
      if (data['success'] == true && data['guide'] != null) return data['guide']['photoUrl'] as String?;
    } catch (_) {}
    return null;
  }

  void _openDisplayScreen() async {
    final gn = _transliterate(context.read<AuthController>().currentUser?.fullName ?? 'Unknown');
    final fd = DateFormat('EEE, MMM d, y').format(_selectedDate);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔍 Looking up photos...'), duration: Duration(seconds: 2)));
    final url = await _fetchDriveUrl(gn);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoDisplayScreen(guideName: gn, date: fd, driveUrl: url)));
  }

  void _openReviewScreen() async {
    final gn = _transliterate(context.read<AuthController>().currentUser?.fullName ?? 'Unknown');
    final fd = DateFormat('EEE, MMM d, y').format(_selectedDate);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔍 Looking up photos...'), duration: Duration(seconds: 2)));
    final url = await _fetchDriveUrl(gn);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewRequestScreen(guideName: gn, date: fd, driveUrl: url)));
  }

  // ──────────────── UI ────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo & Video Upload', style: TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF0A0A23), foregroundColor: Colors.white),
    body: _isUploading ? _buildProgress() : _buildMain(),
  );

  Widget _buildProgress() => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 150, height: 150, child: Stack(alignment: Alignment.center, children: [
        SizedBox(width: 150, height: 150, child: CircularProgressIndicator(
          value: _overallProgress, strokeWidth: 8, backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Colors.green))),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(_overallProgress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          Text('$_currentFileIndex / $_totalFiles', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      ])),
      const SizedBox(height: 32),
      Text(_statusMessage, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      const Text('Please keep this tab open during upload', style: TextStyle(color: Colors.white38, fontSize: 12)),
    ],
  )));

  Widget _buildMain() => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildGuideAndDate(), const SizedBox(height: 20),
      _buildPickButton(), const SizedBox(height: 20),
      if (_selectedFiles.isNotEmpty) ...[_buildFileList(), const SizedBox(height: 20)],
      _buildUploadButton(), const SizedBox(height: 16),
      _buildScreenButtons(), const SizedBox(height: 20),
    ],
  ));

  Widget _buildGuideAndDate() => Consumer<AuthController>(builder: (_, auth, __) => Column(children: [
    Container(width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [const Icon(Icons.person, color: Colors.white70), const SizedBox(width: 12),
        Text(auth.currentUser?.fullName ?? 'Unknown', style: const TextStyle(color: Colors.white))])),
    const SizedBox(height: 12),
    InkWell(onTap: _selectDate, child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [const Icon(Icons.calendar_today, color: Colors.white70), const SizedBox(width: 12),
        Text(DateFormat('EEE, MMM d, y').format(_selectedDate), style: const TextStyle(color: Colors.white))]))),
  ]));

  Widget _buildPickButton() => Column(children: [
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _pickFiles, icon: const Icon(Icons.add_photo_alternate),
      label: const Text('Select Photos & Videos'),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.green))),
    const SizedBox(height: 8),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _pickFolder, icon: const Icon(Icons.folder_open),
      label: const Text('Select Folder'),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal))),
  ]);

  Widget _buildFileList() {
    final pc = _selectedFiles.where((f) => !_isVideoFile(f.name)).length;
    final vc = _selectedFiles.where((f) => _isVideoFile(f.name)).length;
    var sub = ''; if (pc > 0) sub += '$pc photo${pc > 1 ? 's' : ''}'; if (vc > 0) { if (sub.isNotEmpty) sub += ', '; sub += '$vc video${vc > 1 ? 's' : ''}'; }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_selectedFiles.length} Files Selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text('$sub • Total: ${_formatTotalSize()}', style: const TextStyle(color: Colors.white70, fontSize: 12))]),
        TextButton(onPressed: () => setState(() => _selectedFiles.clear()), child: const Text('Clear', style: TextStyle(color: Colors.red)))]),
      const SizedBox(height: 12),
      Container(constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
        child: ListView.builder(shrinkWrap: true, itemCount: _selectedFiles.length, itemBuilder: (_, i) {
          final f = _selectedFiles[i]; final v = _isVideoFile(f.name);
          return ListTile(dense: true,
            leading: Icon(v ? Icons.videocam : Icons.image, color: v ? Colors.blue : Colors.white54, size: 20),
            title: Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
            subtitle: Text(_formatFileSize(f.size), style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: () => setState(() => _selectedFiles.removeAt(i))));
        })),
    ]);
  }

  Widget _buildUploadButton() => SizedBox(width: double.infinity, child: ElevatedButton.icon(
    onPressed: _selectedFiles.isNotEmpty ? _uploadFiles : null,
    icon: const Icon(Icons.cloud_upload),
    label: Text(_selectedFiles.isEmpty ? 'Select Files First' : 'Upload ${_selectedFiles.length} File(s)'),
    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), backgroundColor: Colors.blue,
      disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3))));

  Widget _buildScreenButtons() => Column(children: [
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _openDisplayScreen, icon: const Icon(Icons.fullscreen, color: Colors.white),
      label: const Text('📱 Show Screen', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: const Color(0xFF2D3748)))),
    const SizedBox(height: 8),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _openReviewScreen, icon: const Icon(Icons.star, color: Colors.amber),
      label: const Text('⭐ Show Screen & Request Reviews', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: const Color(0xFF2D4730)))),
  ]);
}

class _WebFileInfo {
  final String name;
  final Uint8List bytes;
  final int size;
  _WebFileInfo({required this.name, required this.bytes, required this.size});
}
