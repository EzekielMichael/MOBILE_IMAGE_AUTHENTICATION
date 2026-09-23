// lib/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

class ApiService {
  // ============================================================
  // BASE URL (dynamic — stored in SharedPreferences)
  // ============================================================
  static const String defaultBaseUrl =
      'https://earwig-puzzling-bouncy.ngrok-free.dev';

  static Future<void> downloadAndOpenReport(String reportId, {bool download = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final baseUrl = 'https://earwig-puzzling-bouncy.ngrok-free.dev'; // your base
    final path = download ? 'download' : 'view';
    final url = Uri.parse('$baseUrl/api/reports/$reportId/$path/');

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed: ${response.statusCode}');
      }

      // Save to temp
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/report_$reportId.pdf');
      await file.writeAsBytes(response.bodyBytes);

      // Open with system viewer
      await OpenFilex.open(file.path);
    } catch (e) {
      print('Error opening report: $e');
      rethrow;
    }
  }

  static String _baseUrl = defaultBaseUrl;

  /// The current base URL (no trailing slash)
  static String get baseUrl => _baseUrl;

  /// Load saved URL from SharedPreferences on app startup
  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('base_url') ?? defaultBaseUrl;
  }

  /// Save a new base URL (trims trailing slash)
  static Future<void> setBaseUrl(String url) async {
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    _baseUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', clean);
  }

  /// Reset to the default URL
  static Future<void> resetBaseUrl() async {
    await setBaseUrl(defaultBaseUrl);
  }

  /// Read the saved URL (without modifying state)
  static Future<String> getSavedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('base_url') ?? defaultBaseUrl;
  }

  // ============================================================
  // API KEY (public endpoints)
  // ============================================================
  static const String apiKey =
      'fx_HuYVWl3Ck89wiw3uz_fzN9Kz5E2fHbf1hfa_QVyR8nPv7bdO6zo3vNmrW0GUwsTm';

  // ============================================================
  // TOKENS
  // ============================================================
  static Future<void> saveTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  /// Generic helper used by `uploadImage` and `runAnalysis`
  static Future<String?> getToken() async {
    return getAccessToken();
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  // ============================================================
  // AUTHENTICATION
  // ============================================================
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        await saveTokens(data['access'], data['refresh']);
        // Persist user id for per-user offline storage
        if (data['user_id'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', data['user_id'].toString());
        }
      }
      return data;
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> googleLogin(String idToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/google/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        await saveTokens(data['access'], data['refresh']);
        if (data['user_id'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', data['user_id'].toString());
        }
      }
      return data;
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> me() async {
    final token = await getAccessToken();
    if (token == null) {
      return {'success': false, 'error': 'Not logged in'};
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  // ============================================================
  // UPLOAD + ANALYSIS
  // ============================================================

  /// Upload an image file to the backend.
  /// Returns: { success, hash_id, data }
  static Future<Map<String, dynamic>> uploadImage(File file) async {
    try {
      final uri = Uri.parse('$baseUrl/api/images/upload/');
      final request = http.MultipartRequest('POST', uri);

      final token = await getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        await http.MultipartFile.fromPath('image', file.path),
      );

      final streamed = await request.send().timeout(
            const Duration(seconds: 60),
          );
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final json = jsonDecode(resp.body);
        return {
          'success': true,
          'hash_id': json['hash_id'] ?? json['id'],
          'data': json,
        };
      }
      return {
        'success': false,
        'error': 'HTTP ${resp.statusCode}: ${resp.body}',
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  /// Run analysis on an already-uploaded image.
  static Future<Map<String, dynamic>> runAnalysis(String hashId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/images/$hashId/run-analysis/');
      final token = await getToken();

      final resp = await http.post(
        uri,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 120));

      if (resp.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(resp.body)};
      }
      return {
        'success': false,
        'error': 'HTTP ${resp.statusCode}: ${resp.body}',
      };
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ============================================================
  // PUBLIC GALLERY (X-API-Key)
  // ============================================================
  static Future<Map<String, dynamic>> getPublicImages({
    int page = 1,
    int limit = 20,
    String filter = 'all',
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/public/images/?page=$page&limit=$limit&filter=$filter',
    );

    try {
      final response = await http.get(url, headers: {'X-API-Key': apiKey});
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response from server'};
    }
  }

  static Future<Map<String, dynamic>> getPublicImageByToken(
      String token) async {
    final url = Uri.parse('$baseUrl/api/v1/public/image/$token/');

    try {
      final response = await http.get(url, headers: {'X-API-Key': apiKey});
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response from server'};
    }
  }

  // ============================================================
  // USER IMAGES (role-based, JWT)
  // ============================================================
  static Future<Map<String, dynamic>> getMyImages() async {
    final token = await getAccessToken();
    if (token == null) {
      return {'success': false, 'error': 'Not logged in'};
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/images/my/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response'};
    }
  }

  static Future<Map<String, dynamic>> getMyImageDetail(String hashId) async {
    final token = await getAccessToken();
    if (token == null) {
      return {'success': false, 'error': 'Not logged in'};
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/images/$hashId/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response'};
    }
  }

  // ============================================================
  // CHATBOT
  // ============================================================
  static Future<Map<String, dynamic>> askQuestion(
      String hashId, String question) async {
    final token = await getAccessToken();
    if (token == null) {
      return {'success': false, 'error': 'Not logged in'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/images/$hashId/ask/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'question': question}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response'};
    }
  }

  static Future<Map<String, dynamic>> getChatHistory(String hashId) async {
    final token = await getAccessToken();
    if (token == null) {
      return {'success': false, 'error': 'Not logged in'};
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/images/$hashId/chat-history/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': 'Invalid response'};
    }
  }

  // ============================================================
  // DELETE IMAGE
  // ============================================================
  static Future<Map<String, dynamic>> deleteImage(String hashId) async {
    final token = await getAccessToken();
    if (token == null) return {'success': false, 'error': 'Not logged in'};

    try {
      final resp = await http.delete(
        Uri.parse('$baseUrl/api/images/$hashId/delete/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(resp.body);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ============================================================
  // TOGGLE PUBLIC
  // ============================================================
  static Future<Map<String, dynamic>> togglePublic(
      String hashId, {bool? makePublic}) async {
    final token = await getAccessToken();
    if (token == null) return {'success': false, 'error': 'Not logged in'};

    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/images/$hashId/toggle-public/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(
          makePublic == null ? {} : {'public': makePublic},
        ),
      );
      return jsonDecode(resp.body);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  // ============================================================
  // GENERATE REPORT
  // ============================================================
  static Future<Map<String, dynamic>> generateReport(
      String hashId, {bool includeHeatmap = false}) async {
    final token = await getAccessToken();
    if (token == null) return {'success': false, 'error': 'Not logged in'};

    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/images/$hashId/generate-report/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'include_heatmap': includeHeatmap}),
      );
      return jsonDecode(resp.body);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  /// Full URL to view a report inline
  static String reportViewUrl(String reportHashId) =>
      '$baseUrl/api/reports/$reportHashId/view/';

  /// Full URL to download a report
  static String reportDownloadUrl(String reportHashId) =>
      '$baseUrl/api/reports/$reportHashId/download/';
  // ============================================================
  // GET IMAGE IDs for navigation (current user's ordered list)
  // ============================================================
  static Future<Map<String, dynamic>> getMyImageIds() async {
    final token = await getAccessToken();
    if (token == null) return {'success': false, 'error': 'Not logged in'};

    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/images/ids/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return jsonDecode(resp.body);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
  }) async {
    final base = await getSavedBaseUrl();
    try {
      final response = await http.post(
        Uri.parse('$base/api/auth/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'email': email,
          'password': password,
          'password_confirm': passwordConfirm,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Save tokens if returned
        if (data['access'] != null || data['access_token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'access_token',
            (data['access'] ?? data['access_token']).toString(),
          );
          if (data['refresh'] != null || data['refresh_token'] != null) {
            await prefs.setString(
              'refresh_token',
              (data['refresh'] ?? data['refresh_token']).toString(),
            );
          }
        }

        return {...data, 'success': true};
      }

      final data = jsonDecode(response.body);
      return {
        'success': false,
        'error': data['error'] ?? data['detail'] ?? 'Registration failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

}
