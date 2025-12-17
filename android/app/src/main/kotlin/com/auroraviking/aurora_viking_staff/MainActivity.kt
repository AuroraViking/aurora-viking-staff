package com.auroraviking.aurora_viking_staff

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val SAF_CHANNEL = "com.auroraviking.aurora_viking_staff/saf"
    private val PICK_FOLDER_REQUEST = 1001
    
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up location tracking service channels
        LocationTrackingService.setupChannels(flutterEngine, this)
        
        // Set up SAF (Storage Access Framework) channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> {
                    pendingResult = result
                    openFolderPicker()
                }
                "listFiles" -> {
                    val uri = call.argument<String>("uri")
                    val cutoffTime = call.argument<Long>("cutoffTime") ?: 0L
                    val extensions = call.argument<List<String>>("extensions") ?: listOf("jpg", "jpeg")
                    
                    if (uri != null) {
                        // Run on background thread to avoid blocking UI
                        Thread {
                            listFilesInFolder(uri, cutoffTime, extensions, result)
                        }.start()
                    } else {
                        result.error("INVALID_URI", "URI is required", null)
                    }
                }
                "copyFileToPath" -> {
                    val sourceUri = call.argument<String>("sourceUri")
                    val destPath = call.argument<String>("destPath")
                    
                    if (sourceUri != null && destPath != null) {
                        // Run on background thread for file I/O
                        Thread {
                            copyFileToPath(sourceUri, destPath, result)
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "sourceUri and destPath required", null)
                    }
                }
                // Keep old method for compatibility but discourage use
                "readFile" -> {
                    result.error("DEPRECATED", "Use copyFileToPath instead to avoid memory issues", null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openFolderPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, PICK_FOLDER_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == PICK_FOLDER_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                
                // Take persistent permission
                val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                contentResolver.takePersistableUriPermission(uri, takeFlags)
                
                // Get folder name
                val docFile = DocumentFile.fromTreeUri(this, uri)
                val name = docFile?.name ?: "Unknown"
                
                pendingResult?.success(mapOf(
                    "uri" to uri.toString(),
                    "name" to name
                ))
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    private fun listFilesInFolder(
        uriString: String,
        cutoffTime: Long,
        extensions: List<String>,
        result: MethodChannel.Result
    ) {
        try {
            val uri = Uri.parse(uriString)
            val docFile = DocumentFile.fromTreeUri(this, uri)
            
            if (docFile == null || !docFile.exists()) {
                runOnUiThread {
                    result.error("FOLDER_NOT_FOUND", "Folder not found or no longer accessible", null)
                }
                return
            }

            val files = mutableListOf<Map<String, Any>>()
            scanFolder(docFile, cutoffTime, extensions, files)
            
            // Sort by date (newest first)
            files.sortByDescending { it["lastModified"] as Long }
            
            runOnUiThread {
                result.success(files)
            }
        } catch (e: Exception) {
            runOnUiThread {
                result.error("SCAN_ERROR", e.message, null)
            }
        }
    }

    private fun scanFolder(
        folder: DocumentFile,
        cutoffTime: Long,
        extensions: List<String>,
        results: MutableList<Map<String, Any>>
    ) {
        try {
            for (file in folder.listFiles()) {
                if (file.isDirectory) {
                    // Recurse into subfolders
                    scanFolder(file, cutoffTime, extensions, results)
                } else if (file.isFile) {
                    val name = file.name ?: continue
                    val ext = name.substringAfterLast('.', "").lowercase()
                    
                    if (extensions.contains(ext)) {
                        val lastModified = file.lastModified()
                        
                        // Check if within time range
                        if (lastModified >= cutoffTime) {
                            results.add(mapOf(
                                "uri" to file.uri.toString(),
                                "name" to name,
                                "lastModified" to lastModified,
                                "size" to file.length()
                            ))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Log but continue scanning other folders
            e.printStackTrace()
        }
    }

    /**
     * Copy file from content:// URI to a local file path using streaming
     * This avoids loading the entire file into memory (prevents crashes with large files)
     */
    private fun copyFileToPath(sourceUriString: String, destPath: String, result: MethodChannel.Result) {
        try {
            val sourceUri = Uri.parse(sourceUriString)
            val destFile = File(destPath)
            
            // Ensure parent directory exists
            val parentDir = destFile.parentFile
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs()
            }
            
            // Stream copy - never loads full file into memory
            val inputStream = contentResolver.openInputStream(sourceUri)
            if (inputStream == null) {
                throw Exception("Cannot open source file: $sourceUriString")
            }
            
            inputStream.use { input ->
                FileOutputStream(destFile).use { output ->
                    val buffer = ByteArray(8192) // 8KB buffer
                    var bytesRead: Int
                    var totalBytes = 0L
                    
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytes += bytesRead
                    }
                    
                    output.flush()
                }
            }
            
            // Verify file was created and has size
            if (!destFile.exists()) {
                throw Exception("Destination file was not created: $destPath")
            }
            
            val fileSize = destFile.length()
            if (fileSize == 0L) {
                throw Exception("Destination file is empty: $destPath")
            }
            
            android.util.Log.d("SAF", "Copied file: ${destFile.name} (${fileSize / 1024 / 1024}MB)")
            
            runOnUiThread {
                result.success(mapOf(
                    "success" to true,
                    "path" to destPath,
                    "size" to fileSize
                ))
            }
        } catch (e: Exception) {
            android.util.Log.e("SAF", "Copy error: ${e.message}", e)
            e.printStackTrace()
            runOnUiThread {
                result.error("COPY_ERROR", e.message ?: "Unknown error", null)
            }
        }
    }
}
