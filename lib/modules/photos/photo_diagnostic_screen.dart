// Diagnostic version - add this temporarily to debug photo detection
// Add a button in your app to call this, or replace the auto-select function

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PhotoDiagnosticScreen extends StatefulWidget {
  const PhotoDiagnosticScreen({super.key});

  @override
  State<PhotoDiagnosticScreen> createState() => _PhotoDiagnosticScreenState();
}

class _PhotoDiagnosticScreenState extends State<PhotoDiagnosticScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;

  void _log(String message) {
    print(message);
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)} $message');
    });
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _logs.clear();
      _isRunning = true;
    });

    try {
      // Step 1: Check Android version
      _log('📱 Checking Android version...');
      _log('   Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

      // Step 2: Check permission status
      _log('');
      _log('🔐 Checking permissions...');
      
      final photoPermission = await Permission.photos.status;
      _log('   photos: $photoPermission');
      
      final storagePermission = await Permission.storage.status;
      _log('   storage: $storagePermission');
      
      final mediaPermission = await Permission.mediaLibrary.status;
      _log('   mediaLibrary: $mediaPermission');
      
      final manageStoragePermission = await Permission.manageExternalStorage.status;
      _log('   manageExternalStorage: $manageStoragePermission');

      // Step 3: Request photo_manager permission
      _log('');
      _log('🔑 Requesting photo_manager permission...');
      final pmPermission = await PhotoManager.requestPermissionExtend();
      _log('   Result: ${pmPermission.name}');
      _log('   isAuth: ${pmPermission.isAuth}');
      _log('   hasAccess: ${pmPermission.hasAccess}');

      if (!pmPermission.isAuth) {
        _log('');
        _log('❌ Permission NOT granted!');
        _log('   Opening settings...');
        await PhotoManager.openSetting();
        return;
      }

      // Step 4: Get all albums
      _log('');
      _log('📁 Fetching all albums (no date filter)...');
      
      final allAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      
      _log('   Found ${allAlbums.length} albums');

      int totalAssets = 0;
      for (final album in allAlbums) {
        final count = await album.assetCountAsync;
        totalAssets += count;
        _log('   📂 "${album.name}": $count photos');
        
        // Show first 3 photos from each album
        if (count > 0) {
          final assets = await album.getAssetListRange(start: 0, end: 3);
          for (final asset in assets) {
            final date = asset.createDateTime;
            _log('      - ${asset.title ?? 'untitled'} (${date.toString().substring(0, 16)})');
          }
        }
      }
      
      _log('');
      _log('📊 Total photos in MediaStore: $totalAssets');

      // Step 5: Check for recent photos
      _log('');
      _log('🕐 Checking for photos in last 24 hours...');
      
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));
      
      final filterOption = FilterOptionGroup(
        createTimeCond: DateTimeCond(
          min: yesterday,
          max: now,
        ),
      );
      
      final recentAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: filterOption,
      );
      
      int recentCount = 0;
      for (final album in recentAlbums) {
        final count = await album.assetCountAsync;
        recentCount += count;
      }
      
      _log('   Photos from last 24h: $recentCount');

      // Step 6: Check for external storage / USB
      _log('');
      _log('💾 Checking storage paths...');
      
      final externalDirs = await _getExternalStoragePaths();
      for (final dir in externalDirs) {
        _log('   📁 $dir');
        final exists = await Directory(dir).exists();
        _log('      exists: $exists');
        
        if (exists) {
          try {
            final contents = Directory(dir).listSync(recursive: false);
            _log('      contents: ${contents.length} items');
            for (final item in contents.take(5)) {
              _log('        - ${item.path.split('/').last}');
            }
          } catch (e) {
            _log('      ❌ Cannot list: $e');
          }
        }
      }

      // Step 7: Look for DCIM folders specifically
      _log('');
      _log('📷 Looking for DCIM folders...');
      
      for (final basePath in externalDirs) {
        final dcimPath = '$basePath/DCIM';
        final dcimDir = Directory(dcimPath);
        
        if (await dcimDir.exists()) {
          _log('   ✅ Found: $dcimPath');
          try {
            final subDirs = dcimDir.listSync();
            for (final subDir in subDirs) {
              if (subDir is Directory) {
                _log('      📁 ${subDir.path.split('/').last}');
                try {
                  final files = subDir.listSync().take(3);
                  for (final file in files) {
                    if (file is File) {
                      final stat = await file.stat();
                      _log('         - ${file.path.split('/').last} (${stat.modified.toString().substring(0, 16)})');
                    }
                  }
                } catch (e) {
                  _log('         ❌ Cannot list: $e');
                }
              }
            }
          } catch (e) {
            _log('      ❌ Cannot access: $e');
          }
        }
      }

      _log('');
      _log('✅ Diagnostics complete!');
      
      if (totalAssets == 0) {
        _log('');
        _log('⚠️ PROBLEM: No photos found in MediaStore');
        _log('   Possible causes:');
        _log('   1. Permission not fully granted');
        _log('   2. USB camera not indexed (common issue)');
        _log('   3. No photos on device');
        _log('');
        _log('💡 TRY: Open the default Photos/Gallery app');
        _log('   and see if photos appear there.');
      }

    } catch (e, stack) {
      _log('');
      _log('❌ Error during diagnostics:');
      _log('   $e');
      _log('   $stack');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<List<String>> _getExternalStoragePaths() async {
    final paths = <String>[];
    
    // Common paths to check
    paths.add('/storage/emulated/0');
    paths.add('/storage/self/primary');
    paths.add('/sdcard');
    
    // Check for mounted USB/SD storage
    final storageDir = Directory('/storage');
    if (await storageDir.exists()) {
      try {
        final mounts = storageDir.listSync();
        for (final mount in mounts) {
          if (mount is Directory && 
              !mount.path.contains('emulated') && 
              !mount.path.contains('self')) {
            paths.add(mount.path);
          }
        }
      } catch (e) {
        print('Could not list /storage: $e');
      }
    }
    
    // Check /mnt/media_rw for USB devices
    final mediaRw = Directory('/mnt/media_rw');
    if (await mediaRw.exists()) {
      try {
        final mounts = mediaRw.listSync();
        for (final mount in mounts) {
          if (mount is Directory) {
            paths.add(mount.path);
          }
        }
      } catch (e) {
        print('Could not list /mnt/media_rw: $e');
      }
    }
    
    return paths;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Diagnostics'),
        backgroundColor: const Color(0xFF0A0A23),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0A0A23),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runDiagnostics,
                icon: _isRunning 
                    ? const SizedBox(
                        width: 20, 
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bug_report),
                label: Text(_isRunning ? 'Running...' : 'Run Diagnostics'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.orange,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color color = Colors.green;
                  if (log.contains('❌')) color = Colors.red;
                  if (log.contains('⚠️')) color = Colors.orange;
                  if (log.contains('💡')) color = Colors.yellow;
                  
                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
                    ),
                  );
                },
              ),
            ),
          ),
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.2),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What to look for:',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '• If "Total photos in MediaStore: 0" → Permission issue\n'
                  '• If photos exist but none recent → USB camera not indexed\n'
                  '• If DCIM found but photos there → Need direct file access',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


