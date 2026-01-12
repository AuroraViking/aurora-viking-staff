// USB Storage Finder - Run this to find where your camera is mounted
// Add this screen temporarily to diagnose mount location

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class UsbFinderScreen extends StatefulWidget {
  const UsbFinderScreen({super.key});

  @override
  State<UsbFinderScreen> createState() => _UsbFinderScreenState();
}

class _UsbFinderScreenState extends State<UsbFinderScreen> {
  final List<String> _logs = [];
  bool _isScanning = false;
  String? _foundCameraPath;

  void _log(String msg) {
    print(msg);
    setState(() => _logs.add(msg));
  }

  Future<void> _scanEverything() async {
    setState(() {
      _logs.clear();
      _isScanning = true;
      _foundCameraPath = null;
    });

    _log('🔍 USB Camera Finder');
    _log('═══════════════════════════════════════');
    _log('');

    // Check permissions
    _log('📋 PERMISSIONS:');
    final perms = {
      'manageExternalStorage': await Permission.manageExternalStorage.status,
      'storage': await Permission.storage.status,
    };
    perms.forEach((name, status) {
      final icon = status.isGranted ? '✅' : '❌';
      _log('  $icon $name: $status');
    });
    _log('');

    // Read /proc/mounts to see actual mount points
    _log('📋 SYSTEM MOUNTS (/proc/mounts):');
    try {
      final mountsFile = File('/proc/mounts');
      if (await mountsFile.exists()) {
        final contents = await mountsFile.readAsString();
        final lines = contents.split('\n');
        
        // Filter for interesting mounts (storage-related)
        final storageKeywords = ['storage', 'usb', 'sdcard', 'media', 'external', 'disk', 'mnt'];
        for (final line in lines) {
          if (storageKeywords.any((kw) => line.toLowerCase().contains(kw))) {
            final parts = line.split(' ');
            if (parts.length >= 2) {
              _log('  ${parts[1]}');
            }
          }
        }
      } else {
        _log('  ⚠️ Cannot read /proc/mounts');
      }
    } catch (e) {
      _log('  ❌ Error: $e');
    }
    _log('');

    // Scan ALL possible mount locations
    final pathsToCheck = [
      '/storage',
      '/mnt',
      '/mnt/media_rw',
      '/mnt/usb',
      '/mnt/external',
      '/mnt/sdcard',
      '/mnt/runtime',
      '/mnt/user',
      '/mnt/expand',
      '/data/media',
      '/sdcard',
      '/external_sd',
      '/usb_storage',
      '/usbdisk',
    ];

    _log('📁 SCANNING MOUNT LOCATIONS:');
    for (final basePath in pathsToCheck) {
      await _scanDirectory(basePath, depth: 0, maxDepth: 3);
    }
    _log('');

    // Specifically look for DCIM folders anywhere
    _log('📷 SEARCHING FOR DCIM FOLDERS:');
    final dcimLocations = <String>[];
    
    for (final basePath in ['/storage', '/mnt']) {
      try {
        final dir = Directory(basePath);
        if (await dir.exists()) {
          await _findDcimFolders(dir, dcimLocations, depth: 0, maxDepth: 4);
        }
      } catch (e) {
        // Skip
      }
    }

    if (dcimLocations.isEmpty) {
      _log('  ❌ No DCIM folders found!');
    } else {
      for (final path in dcimLocations) {
        _log('  ✅ FOUND: $path');
        _foundCameraPath = path;
      }
    }
    _log('');

    // Check environment variables
    _log('📋 ENVIRONMENT:');
    try {
      final env = Platform.environment;
      final storageVars = ['EXTERNAL_STORAGE', 'SECONDARY_STORAGE', 'ANDROID_STORAGE'];
      for (final varName in storageVars) {
        final value = env[varName];
        if (value != null) {
          _log('  $varName = $value');
        }
      }
    } catch (e) {
      _log('  ⚠️ Cannot read environment: $e');
    }
    _log('');

    // Summary
    _log('═══════════════════════════════════════');
    if (_foundCameraPath != null) {
      _log('✅ CAMERA FOUND AT: $_foundCameraPath');
      _log('');
      _log('Copy this path to use in the photo upload screen.');
    } else {
      _log('❌ NO CAMERA FOUND');
      _log('');
      _log('Possible issues:');
      _log('1. MANAGE_EXTERNAL_STORAGE permission not granted');
      _log('2. Camera mounted in unexpected location');
      _log('3. Android blocking direct USB access');
      _log('');
      _log('Try: Open Files app and note the exact path to the camera');
    }

    setState(() => _isScanning = false);
  }

  Future<void> _scanDirectory(String path, {required int depth, required int maxDepth}) async {
    if (depth > maxDepth) return;
    
    final indent = '  ' * (depth + 1);
    final dir = Directory(path);
    
    try {
      final exists = await dir.exists();
      if (!exists) {
        if (depth == 0) _log('$indent❌ $path (not found)');
        return;
      }

      // Check if we can list it
      try {
        final contents = await dir.list().toList();
        
        if (depth == 0) {
          _log('$indent📂 $path (${contents.length} items)');
        }
        
        for (final item in contents) {
          final name = item.path.split('/').last;
          
          // Skip hidden and system folders at deeper levels
          if (depth > 0 && name.startsWith('.')) continue;
          if (name == 'emulated' || name == 'self') {
            if (depth == 1) _log('$indent  ⏭️ $name (internal, skipping)');
            continue;
          }
          
          if (item is Directory) {
            // Check if this might be our USB drive
            final hasDcim = await Directory('${item.path}/DCIM').exists();
            final icon = hasDcim ? '📷' : '📁';
            
            if (depth < 2 || hasDcim) {
              _log('$indent  $icon $name${hasDcim ? ' ← HAS DCIM!' : ''}');
            }
            
            // Recurse into non-emulated directories
            if (hasDcim || (depth < 2 && !['emulated', 'self', 'Android'].contains(name))) {
              await _scanDirectory(item.path, depth: depth + 1, maxDepth: maxDepth);
            }
          }
        }
      } catch (e) {
        _log('$indent⚠️ $path (cannot list: $e)');
      }
    } catch (e) {
      if (depth == 0) _log('$indent❌ $path (error: $e)');
    }
  }

  Future<void> _findDcimFolders(Directory dir, List<String> results, {required int depth, required int maxDepth}) async {
    if (depth > maxDepth) return;
    
    try {
      await for (final item in dir.list()) {
        if (item is Directory) {
          final name = item.path.split('/').last;
          
          // Skip internal storage and hidden folders
          if (name == 'emulated' || name == 'self' || name.startsWith('.')) continue;
          
          if (name == 'DCIM') {
            results.add(item.path);
            // Count photos
            int count = 0;
            try {
              await for (final file in item.list(recursive: true)) {
                if (file is File) {
                  final ext = file.path.toLowerCase();
                  if (ext.endsWith('.jpg') || ext.endsWith('.arw') || ext.endsWith('.jpeg')) {
                    count++;
                    if (count >= 10) break;
                  }
                }
              }
            } catch (_) {}
            _log('  📷 ${item.path} (${count}+ photos)');
          } else {
            // Recurse
            await _findDcimFolders(item, results, depth: depth + 1, maxDepth: maxDepth);
          }
        }
      }
    } catch (e) {
      // Permission denied - skip
    }
  }

  Future<void> _requestPermission() async {
    _log('🔑 Requesting MANAGE_EXTERNAL_STORAGE...');
    final status = await Permission.manageExternalStorage.request();
    _log('   Result: $status');
    
    if (status.isDenied || status.isPermanentlyDenied) {
      _log('   Opening app settings...');
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB Camera Finder'),
        backgroundColor: const Color(0xFF1a1a2e),
      ),
      backgroundColor: const Color(0xFF0f0f1a),
      body: Column(
        children: [
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanEverything,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan for Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.security),
                  label: const Text('Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Found camera path (if any)
          if (_foundCameraPath != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Camera Found!',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _foundCameraPath!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.green),
                    onPressed: () {
                      // Copy to clipboard would go here
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Path: $_foundCameraPath')),
                      );
                    },
                  ),
                ],
              ),
            ),

          // Log output
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color color = Colors.white70;
                  if (log.contains('✅')) color = Colors.green;
                  if (log.contains('❌')) color = Colors.red;
                  if (log.contains('⚠️')) color = Colors.orange;
                  if (log.contains('📷')) color = Colors.lightBlue;
                  if (log.contains('HAS DCIM')) color = Colors.green;
                  
                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: color,
                      height: 1.4,
                    ),
                  );
                },
              ),
            ),
          ),

          // Help text
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.1),
            child: const Text(
              'This tool scans all possible mount locations to find your USB camera. '
              'Make sure the camera is connected and set to Mass Storage mode. '
              'Grant "All files access" permission if prompted.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}


