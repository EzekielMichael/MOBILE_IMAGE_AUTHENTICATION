// lib/offline_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class OfflineService {
  static const String _manifestFile = 'manifest.json';

  // ============================================================
  // ROOT FOLDERS
  // ============================================================

  /// Root folder: <app_docs>/forensix_offline/
  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/forensix_offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Folder for one user: <root>/users/<userId>/
  static Future<Directory> _userDir(String userId) async {
    final root = await _root();
    final dir = Directory('${root.path}/users/$userId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Folder for one specific image of a user:
  /// <root>/users/<userId>/images/<hashId>/
  static Future<Directory> _imageDir(String userId, String hashId) async {
    final userDir = await _userDir(userId);
    final dir = Directory('${userDir.path}/images/$hashId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ============================================================
  // MANIFEST (per user)
  // ============================================================

  static Future<File> _manifest(String userId) async {
    final dir = await _userDir(userId);
    return File('${dir.path}/$_manifestFile');
  }

  /// Returns the list of saved items **for the given user only**.
  static Future<List<Map<String, dynamic>>> listSaved(String userId) async {
    final f = await _manifest(userId);
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString());
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeManifest(
      String userId, List<Map<String, dynamic>> items) async {
    final f = await _manifest(userId);
    await f.writeAsString(jsonEncode(items));
  }

  /// Check if this user has an offline copy of the image.
  static Future<bool> isSaved(String userId, String hashId) async {
    final items = await listSaved(userId);
    return items.any((i) => i['hash_id'] == hashId);
  }

  // ============================================================
  // SAVE FULL RESULT (per user)
  // ============================================================

  static Future<void> saveImageResult(
      String userId, String hashId, Map<String, dynamic> data) async {
    final dir = await _imageDir(userId, hashId);

    // 1. Copy the whole JSON payload (we'll swap in local image paths)
    final saved = Map<String, dynamic>.from(data);

    // 2. Download & save each image referenced in the JSON
    saved['image_url'] = await _downloadOrNull(
      data['image_url'],
      '${dir.path}/original.jpg',
    );

    final edit = saved['human_edit_detection'];
    if (edit != null) {
      if (edit['heatmap_url'] != null) {
        edit['heatmap_url'] = await _downloadOrNull(
          edit['heatmap_url'],
          '${dir.path}/heatmap.png',
        );
      }
      if (edit['overlay_url'] != null) {
        edit['overlay_url'] = await _downloadOrNull(
          edit['overlay_url'],
          '${dir.path}/overlay.png',
        );
      }
    }

    // 3. Save metadata JSON
    final jsonFile = File('${dir.path}/data.json');
    await jsonFile.writeAsString(jsonEncode(saved));

    // 4. Update this user's manifest
    final items = await listSaved(userId);
    items.removeWhere((i) => i['hash_id'] == hashId);
    items.insert(0, {
      'hash_id': hashId,
      'filename': data['filename'] ?? 'Unknown',
      'verdict': data['verdict']?['verdict'] ?? 'Not Analyzed',
      'saved_at': DateTime.now().toIso8601String(),
      'path': dir.path,
    });
    await _writeManifest(userId, items);
  }

  /// Returns local path if download succeeded, else null.
  static Future<String?> _downloadOrNull(
      String? url, String destPath) async {
    if (url == null || url.isEmpty) return null;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await File(destPath).writeAsBytes(resp.bodyBytes);
        return destPath;
      }
    } catch (_) {}
    return null;
  }

  // ============================================================
  // LOAD A SAVED RESULT (per user)
  // ============================================================

  static Future<Map<String, dynamic>?> loadImageResult(
      String userId, String hashId) async {
    try {
      final dir = await _imageDir(userId, hashId);
      final f = File('${dir.path}/data.json');
      if (!await f.exists()) return null;
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // DELETE (per user)
  // ============================================================

  static Future<void> deleteSaved(String userId, String hashId) async {
    final dir = await _imageDir(userId, hashId);
    if (await dir.exists()) await dir.delete(recursive: true);

    final items = await listSaved(userId);
    items.removeWhere((i) => i['hash_id'] == hashId);
    await _writeManifest(userId, items);
  }

  // ============================================================
  // OPTIONAL: CLEAR EVERYTHING FOR A USER (e.g., on logout)
  // ============================================================

  static Future<void> clearUserData(String userId) async {
    final dir = await _userDir(userId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}