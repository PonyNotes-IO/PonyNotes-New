import 'dart:convert';
import 'dart:typed_data';
import 'package:appflowy_backend/log.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../../import_page/file_upload_service.dart';

/// Whiteboard image upload service
/// Handles uploading images to cloud storage and managing image URLs
class WhiteboardImageUploadService {
  /// Maximum image size for direct upload (10MB)
  /// Larger images should be compressed before upload
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10MB

  /// Upload image and return the URL
  /// Returns the uploaded URL or throws an exception
  static Future<String> uploadImage(Uint8List imageBytes, String fileName) async {
    try {
      Log.info('[WhiteboardImage] Uploading image: $fileName (${_getFileSizeString(imageBytes.length)})');

      // Check file size
      if (imageBytes.length > maxImageSizeBytes) {
        Log.warn('[WhiteboardImage] Image size ${imageBytes.length} exceeds $maxImageSizeBytes, trying to upload anyway');
      }

      // Use existing FileUploadService to upload
      final fileUrl = await FileUploadService.uploadFile(imageBytes, fileName);
      Log.info('[WhiteboardImage] ✅ Image uploaded successfully: $fileUrl');
      return fileUrl;
    } catch (e) {
      Log.error('[WhiteboardImage] ❌ Upload failed: $e');
      rethrow;
    }
  }

  /// Upload image and return file metadata including URL
  /// This is useful for tracking uploaded images
  static Future<UploadedImageMetadata> uploadImageWithMetadata(
    Uint8List imageBytes,
    String originalFileName,
  ) async {
    final fileName = _generateUniqueFileName(originalFileName);
    final fileUrl = await uploadImage(imageBytes, fileName);
    final fileHash = _calculateFileHash(imageBytes);

    return UploadedImageMetadata(
      id: const Uuid().v4(),
      url: fileUrl,
      fileName: fileName,
      fileSize: imageBytes.length,
      fileHash: fileHash,
      uploadedAt: DateTime.now().toIso8601String(),
    );
  }

  /// Convert dataURL to image bytes
  /// Returns (bytes, mimeType, originalFileName)
  static ({Uint8List bytes, String mimeType, String? originalFileName})?
      parseDataURL(String dataURL) {
    try {
      if (!dataURL.startsWith('data:')) {
        return null;
      }

      final mimeTypeEnd = dataURL.indexOf(';');
      if (mimeTypeEnd == -1) {
        return null;
      }

      final mimeType = dataURL.substring(5, mimeTypeEnd);
      final base64Data = dataURL.substring(mimeTypeEnd + 1);
      if (!base64Data.startsWith('base64,')) {
        return null;
      }

      final base64Content = base64Data.substring(7);
      final bytes = base64Decode(base64Content);

      // Extract original filename from mimeType if available
      String? originalFileName;
      if (mimeType.contains('filename=')) {
        final filenameMatch = RegExp(r'filename=([^;]+)').firstMatch(mimeType);
        if (filenameMatch != null) {
          originalFileName = filenameMatch.group(1);
        }
      }

      return (bytes: bytes, mimeType: mimeType.split(';').first, originalFileName: originalFileName);
    } catch (e) {
      Log.error('[WhiteboardImage] Failed to parse dataURL: $e');
      return null;
    }
  }

  /// Check if a URL is already an uploaded cloud URL
  static bool isCloudUrl(String url) {
    // Check if it's not a dataURL
    if (url.startsWith('data:')) {
      return false;
    }
    // Check if it's a http/https URL (cloud storage)
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// Process files map - upload any dataURL images to cloud
  /// Returns a new files map with cloud URLs
  static Future<Map<String, dynamic>> processFilesForUpload(
    Map<String, dynamic> files, {
    bool forceUpload = false,
  }) async {
    final result = <String, dynamic>{};
    final uploadTasks = <String, Future<void>>{};

    for (final entry in files.entries) {
      final fileId = entry.key;
      final fileData = entry.value;

      if (fileData is! Map) {
        result[fileId] = fileData;
        continue;
      }

      final fileDataMap = fileData as Map<String, dynamic>;
      final dataURL = fileDataMap['data'] as String?;

      if (dataURL != null && (dataURL.startsWith('data:') || forceUpload)) {
        // Need to upload this image
        final parsed = parseDataURL(dataURL);
        if (parsed != null) {
          final task = _uploadAndReplace(
            fileId: fileId,
            dataURL: dataURL,
            parsed: parsed,
            result: result,
          );
          uploadTasks[fileId] = task;
        } else {
          result[fileId] = fileDataMap;
        }
      } else if (isCloudUrl(dataURL ?? '')) {
        // Already a cloud URL, keep as is
        result[fileId] = fileDataMap;
      } else {
        result[fileId] = fileDataMap;
      }
    }

    // Wait for all uploads to complete
    if (uploadTasks.isNotEmpty) {
      Log.info('[WhiteboardImage] Waiting for ${uploadTasks.length} image uploads...');
      await Future.wait(uploadTasks.values);
      Log.info('[WhiteboardImage] ✅ All images uploaded');
    }

    return result;
  }

  static Future<void> _uploadAndReplace({
    required String fileId,
    required String dataURL,
    required ({Uint8List bytes, String mimeType, String? originalFileName}) parsed,
    required Map<String, dynamic> result,
  }) async {
    try {
      final originalFileName = parsed.originalFileName ?? 'image_$fileId.png';
      final metadata = await uploadImageWithMetadata(parsed.bytes, originalFileName);

      // Replace dataURL with cloud URL
      result[fileId] = {
        'id': fileId,
        'url': metadata.url,
        'data': metadata.url, // Use URL as data for Excalidraw
        'mimeType': parsed.mimeType,
        'fileName': metadata.fileName,
        'fileSize': metadata.fileSize,
        'fileHash': metadata.fileHash,
        'uploadedAt': metadata.uploadedAt,
        'source': 'cloud',
        'dataURL': dataURL, // Keep original for fallback
      };
      Log.info('[WhiteboardImage] ✅ Uploaded $fileId -> ${metadata.url}');
    } catch (e) {
      Log.error('[WhiteboardImage] ❌ Failed to upload $fileId: $e');
      // Keep original dataURL as fallback
      result[fileId] = {
        'id': fileId,
        'data': dataURL,
        'mimeType': parsed.mimeType,
        'uploadError': e.toString(),
      };
    }
  }

  /// Generate unique file name
  static String _generateUniqueFileName(String originalName) {
    final ext = originalName.contains('.')
        ? originalName.substring(originalName.lastIndexOf('.'))
        : '.png';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid().v4().substring(0, 8);
    final baseName = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.'))
        : originalName;
    // Sanitize filename
    final sanitized = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').substring(0, 30);
    return 'whiteboard_${sanitized}_${timestamp}_$uuid$ext';
  }

  /// Calculate file hash for deduplication
  static String _calculateFileHash(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Get human readable file size
  static String _getFileSizeString(int fileSizeInBytes) {
    if (fileSizeInBytes < 1024) {
      return '${fileSizeInBytes}B';
    } else if (fileSizeInBytes < 1024 * 1024) {
      return '${(fileSizeInBytes / 1024).toStringAsFixed(1)}KB';
    } else if (fileSizeInBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(fileSizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}

/// Metadata for uploaded images
class UploadedImageMetadata {
  final String id;
  final String url;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String uploadedAt;

  UploadedImageMetadata({
    required this.id,
    required this.url,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileHash': fileHash,
        'uploadedAt': uploadedAt,
      };

  factory UploadedImageMetadata.fromJson(Map<String, dynamic> json) =>
      UploadedImageMetadata(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        fileHash: json['fileHash'] as String,
        uploadedAt: json['uploadedAt'] as String,
      );
}
