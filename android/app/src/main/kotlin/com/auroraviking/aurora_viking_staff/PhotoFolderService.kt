package com.auroraviking.aurora_viking_staff

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PhotoFolderService {
    companion object {
        private const val CHANNEL_NAME = "com.auroraviking.aurora_viking_staff/photo_folder"
        
        @JvmStatic
        fun setupChannels(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "listFilesInFolder" -> {
                        val folderUriString = call.argument<String>("folderUri")
                        val hoursAgo = call.argument<Long>("hoursAgo") ?: 20L
                        
                        if (folderUriString != null) {
                            try {
                                val folderUri = Uri.parse(folderUriString)
                                val files = listFilesInFolder(context, folderUri, hoursAgo)
                                result.success(files)
                            } catch (e: Exception) {
                                result.error("LIST_ERROR", "Failed to list files: ${e.message}", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "folderUri is required", null)
                        }
                    }
                    "requestFolderSelection" -> {
                        // Request folder selection via SAF Intent
                        // This will be handled by MainActivity
                        result.error("NOT_IMPLEMENTED", "Use Flutter file_picker or implement Intent in MainActivity", null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
        }
        
        private fun listFilesInFolder(context: Context, folderUri: Uri, hoursAgo: Long): List<Map<String, Any?>> {
            val files = mutableListOf<Map<String, Any?>>()
            val cutoffTime = System.currentTimeMillis() - (hoursAgo * 60 * 60 * 1000)
            
            try {
                val folder = DocumentFile.fromTreeUri(context, folderUri)
                if (folder != null && folder.exists() && folder.isDirectory) {
                    listFilesRecursive(context, folder, files, cutoffTime)
                }
            } catch (e: Exception) {
                android.util.Log.e("PhotoFolderService", "Error listing files: ${e.message}", e)
            }
            
            return files
        }
        
        private fun listFilesRecursive(
            context: Context,
            folder: DocumentFile,
            files: MutableList<Map<String, Any?>>,
            cutoffTime: Long
        ) {
            val children: Array<DocumentFile> = folder.listFiles()
            
            for (child in children) {
                if (child.isDirectory) {
                    // Recursively scan subdirectories
                    listFilesRecursive(context, child, files, cutoffTime)
                } else if (child.isFile) {
                    // Check if it's an image file
                    val name = child.name?.lowercase() ?: ""
                    val imageExtensions = listOf(".jpg", ".jpeg", ".png", ".heic", ".raw", ".cr2", ".nef", ".arw", ".orf", ".rw2")
                    
                    if (imageExtensions.any { name.endsWith(it) }) {
                        val lastModified = child.lastModified()
                        
                        // Filter by time (lastModified is in milliseconds)
                        if (lastModified >= cutoffTime) {
                            // Get the file URI
                            val fileUri = child.uri
                            
                            // Try to get a file path if possible
                            val filePath = getFilePathFromUri(context, fileUri)
                            
                            files.add(mapOf(
                                "uri" to fileUri.toString(),
                                "path" to filePath,
                                "name" to child.name,
                                "lastModified" to lastModified,
                                "size" to child.length()
                            ))
                        }
                    }
                }
            }
        }
        
        private fun getFilePathFromUri(context: Context, uri: Uri): String? {
            return try {
                // Try to get the file path from the URI
                if (DocumentsContract.isDocumentUri(context, uri)) {
                    val docId = DocumentsContract.getDocumentId(uri)
                    if (docId.startsWith("primary:")) {
                        // Primary storage
                        val split = docId.split(":")
                        if (split.size > 1) {
                            val path = "/storage/emulated/0/${split[1]}"
                            if (File(path).exists()) {
                                return path
                            }
                        }
                    } else if (docId.contains(":")) {
                        // External storage
                        val split = docId.split(":")
                        if (split.size >= 2) {
                            // Try common external storage paths
                            val possiblePaths = listOf(
                                "/storage/${split[0]}/${split[1]}",
                                "/mnt/media_rw/${split[0]}/${split[1]}",
                                "/storage/${split[0]}/Android/data/${split[1]}"
                            )
                            for (path in possiblePaths) {
                                if (File(path).exists()) {
                                    return path
                                }
                            }
                        }
                    }
                }
                
                // Fallback: return null and use URI directly
                null
            } catch (e: Exception) {
                android.util.Log.e("PhotoFolderService", "Error getting file path: ${e.message}", e)
                null
            }
        }
    }
}

