import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';
import 'dart:io';
import 'api_service.dart';
import 'offline_service.dart';

class MyImageDetailPage extends StatefulWidget {
  final String hashId;
  final bool preferOffline;
  final String? userId;
  final List<String>? imageIds;
  final int? startIndex;

  const MyImageDetailPage({
    super.key,
    required this.hashId,
    this.preferOffline = false,
    this.userId,
    this.imageIds,
    this.startIndex,
  });

  @override
  State<MyImageDetailPage> createState() => _MyImageDetailPageState();
}

class _MyImageDetailPageState extends State<MyImageDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  double _dragDistance = 0;

  String? _userId;
  bool _isOfflineCopy = false;
  bool _hasOfflineSave = false;

  // Public / Report state
  bool _isPublic = false;
  bool _togglingPublic = false;
  bool _generatingReport = false;
  bool _downloadingReport = false;
  List<Map<String, dynamic>> _reports = [];

  // Chat state
  bool _chatOpen = false;
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _sendingQuestion = false;

  // Image viewer
  int _currentSlide = 0;

  // Swipe navigation state
  late String _currentHashId;
  List<String> _imageIds = [];
  int _currentIndex = -1;
  bool _loadingNav = false;
  bool _switching = false;

  static const double _swipeVelocity = 350.0;

  @override
  void initState() {
    super.initState();
    _currentHashId = widget.hashId;
    _load();
    _loadImageIds();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // USER ID
  // ============================================================
  Future<void> _loadUserId() async {
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      _userId = widget.userId;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? prefs.getString('userId');
  }

  // ============================================================
  // LOAD IMAGE ID LIST
  // ============================================================
  Future<void> _loadImageIds() async {
    if (widget.imageIds != null && widget.imageIds!.isNotEmpty) {
      _imageIds = List<String>.from(widget.imageIds!);
      _currentIndex = _imageIds.indexOf(_currentHashId);
      if (_currentIndex < 0) _currentIndex = 0;
      if (mounted) setState(() {});
      return;
    }

    setState(() => _loadingNav = true);
    final result = await ApiService.getMyImageIds();
    if (!mounted) return;

    if (result['success'] == true && result['image_ids'] is List) {
      _imageIds = List<String>.from(result['image_ids']);
      _currentIndex = _imageIds.indexOf(_currentHashId);
      if (_currentIndex < 0) {
        _imageIds = [];
        _currentIndex = -1;
      }
    }
    setState(() => _loadingNav = false);
  }

  // ============================================================
  // LOAD CURRENT IMAGE
  // ============================================================
  Future<void> _load() async {
    await _loadUserId();

    if (_userId == null || _userId!.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view this image.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final offline =
        await OfflineService.loadImageResult(_userId!, _currentHashId);
    final hasOffline = offline != null;

    if (hasOffline && widget.preferOffline) {
      if (!mounted) return;
      setState(() {
        _data = offline;
        _hasOfflineSave = true;
        _isOfflineCopy = true;
        _loading = false;
        _isPublic = offline['is_public'] == true;
        _currentSlide = _defaultSlideIndex(offline);
        _reports = _extractReports(offline);
      });
      return;
    }

    final data = await ApiService.getMyImageDetail(_currentHashId);
    if (!mounted) return;

    if (data['success'] == true) {
      final d = data['data'];
      setState(() {
        _loading = false;
        _data = d;
        _hasOfflineSave = hasOffline;
        _isOfflineCopy = false;
        _isPublic = d['is_public'] == true;
        _currentSlide = _defaultSlideIndex(d);
        _reports = _extractReports(d);
      });
    } else {
      if (hasOffline) {
        setState(() {
          _loading = false;
          _data = offline;
          _hasOfflineSave = true;
          _isOfflineCopy = true;
          _isPublic = offline['is_public'] == true;
          _currentSlide = _defaultSlideIndex(offline);
          _reports = _extractReports(offline);
        });
      } else {
        setState(() {
          _loading = false;
          _error = data['error'] ?? 'Failed to load';
        });
      }
    }
  }

  List<Map<String, dynamic>> _extractReports(Map<String, dynamic>? d) {
    if (d == null) return [];
    final raw = d['reports'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  int _defaultSlideIndex(Map<String, dynamic>? d) {
    if (d == null) return 0;
    final slides = _buildSlidesFromData(d);
    for (int i = 0; i < slides.length; i++) {
      if (slides[i]['label'] == 'Overlay') return i;
    }
    for (int i = 0; i < slides.length; i++) {
      if (slides[i]['label'] == 'Heatmap') return i;
    }
    return 0;
  }

  // ============================================================
  // SWIPE NAVIGATION
  // ============================================================
  Future<void> _goToNext() async {
    if (_switching) return;
    if (_imageIds.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= _imageIds.length - 1) {
      _showSnack('This is the last image', Colors.grey.shade700);
      return;
    }
    await _switchToIndex(_currentIndex + 1);
  }

  Future<void> _goToPrevious() async {
    if (_switching) return;
    if (_imageIds.isEmpty) return;
    if (_currentIndex <= 0) {
      _showSnack('This is the first image', Colors.grey.shade700);
      return;
    }
    await _switchToIndex(_currentIndex - 1);
  }

  Future<void> _switchToIndex(int newIndex) async {
    if (newIndex < 0 || newIndex >= _imageIds.length) return;

    setState(() {
      _switching = true;
      _currentIndex = newIndex;
      _currentHashId = _imageIds[newIndex];
      _chatOpen = false;
      _currentSlide = 0;
      _isPublic = false;
      _hasOfflineSave = false;
      _reports = [];
      _data = null;
    });

    await _load();
    if (mounted) setState(() => _switching = false);
  }

  // ============================================================
  // SAVE OFFLINE
  // ============================================================
  Future<void> _saveOffline() async {
    if (_data == null || _userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Save for offline?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'The images and analysis will be stored on this device under your account. Only you will see them.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF00E5CC))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
      ),
    );

    try {
      await OfflineService.saveImageResult(_userId!, _currentHashId, _data!);
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _hasOfflineSave = true);
      _showSnack('Saved for offline viewing', const Color(0xFF10B981));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('Failed to save: $e', Colors.redAccent);
    }
  }

  // ============================================================
  // DELETE
  // ============================================================
  Future<void> _deleteImage() async {
    if (_isOfflineCopy) {
      _showSnack('Offline copy — cannot delete', Colors.orangeAccent);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Delete image?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete the image and all its analysis. This cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
      ),
    );

    final result = await ApiService.deleteImage(_currentHashId);
    if (!mounted) return;
    Navigator.pop(context);

    if (result['success'] == true) {
      if (_userId != null) {
        try {
          await OfflineService.deleteSaved(_userId!, _currentHashId);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      _showSnack(result['message'] ?? 'Image deleted',
          const Color(0xFF10B981));
    } else {
      _showSnack(result['error'] ?? 'Failed to delete', Colors.redAccent);
    }
  }

  // ============================================================
  // TOGGLE PUBLIC
  // ============================================================
  Future<void> _togglePublic() async {
    if (_isOfflineCopy) {
      _showSnack('Offline copy — cannot share', Colors.orangeAccent);
      return;
    }
    if (_togglingPublic) return;

    final goingPublic = !_isPublic;

    if (goingPublic) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF13223A),
          title: const Text('Make public?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'This image will be visible to anyone with the share link.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Make public',
                  style: TextStyle(color: Color(0xFF00E5CC))),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _togglingPublic = true);
    final result = await ApiService.togglePublic(
      _currentHashId,
      makePublic: goingPublic,
    );
    if (!mounted) return;
    setState(() => _togglingPublic = false);

    if (result['success'] == true) {
      setState(() => _isPublic = result['is_public'] == true);
      _showSnack(
        _isPublic ? 'Image is now public' : 'Image is now private',
        const Color(0xFF10B981),
      );
      if (_isPublic && result['share_url'] != null) {
        _showShareLink(result['share_url']);
      }
    } else {
      _showSnack(result['error'] ?? 'Failed to update sharing',
          Colors.redAccent);
    }
  }

  void _showShareLink(String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Share Link',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Anyone with this link can view the image:',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1A2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(
                  color: Color(0xFF00E5CC),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Open',
                style: TextStyle(color: Color(0xFF00E5CC))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // REPORT MENU  (number + generate / view / download)
  // ============================================================
  void _showReportMenu() {
    if (_isOfflineCopy) {
      _showSnack('Offline copy — cannot manage reports',
          Colors.orangeAccent);
      return;
    }

    final hasReports = _reports.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13223A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf,
                      color: Color(0xFF00E5CC), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    hasReports
                        ? 'Reports (${_reports.length})'
                        : 'No reports yet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1A2C4A), height: 1),

            // Generate new report
            ListTile(
              leading: _generatingReport
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00E5CC),
                      ),
                    )
                  : const Icon(Icons.add_circle_outline,
                      color: Color(0xFF00E5CC)),
              title: Text(
                hasReports ? 'Generate New Report' : 'Generate Report',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Optionally include heatmap analysis',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              onTap: _generatingReport
                  ? null
                  : () {
                      Navigator.pop(context);
                      _promptGenerateReport();
                    },
            ),

            // If reports exist → show view & download (latest)
            if (hasReports) ...[
              const Divider(color: Color(0xFF1A2C4A), height: 1),
              ListTile(
                leading: _downloadingReport
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00E5CC),
                        ),
                      )
                    : const Icon(Icons.visibility_outlined,
                        color: Color(0xFF00E5CC)),
                title: const Text('View Latest Report',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _reports.first['generated_at'] ?? '',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                onTap: _downloadingReport
                    ? null
                    : () {
                        Navigator.pop(context);
                        _openReport(_reports.first['report_id'],
                            download: false);
                      },
              ),
              ListTile(
                leading: _downloadingReport
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00E5CC),
                        ),
                      )
                    : const Icon(Icons.download_outlined,
                        color: Color(0xFF00E5CC)),
                title: const Text('Download Latest Report',
                    style: TextStyle(color: Colors.white)),
                onTap: _downloadingReport
                    ? null
                    : () {
                        Navigator.pop(context);
                        _openReport(_reports.first['report_id'],
                            download: true);
                      },
              ),

              // View all reports (only if > 1)
              if (_reports.length > 1)
                ListTile(
                  leading: const Icon(Icons.list_alt,
                      color: Color(0xFF00E5CC)),
                  title: Text(
                    'View All Reports (${_reports.length})',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showAllReportsSheet();
                  },
                ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAllReportsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13223A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('All Reports',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _reports.length,
                itemBuilder: (context, i) {
                  final r = _reports[i];
                  final heatmap = r['include_heatmap'] == true;
                  return ListTile(
                    leading: const Icon(Icons.picture_as_pdf,
                        color: Color(0xFF00E5CC)),
                    title: Text(
                      'Report #${_reports.length - i}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${r['generated_at'] ?? ''}  ·  ${heatmap ? 'with heatmap' : 'no heatmap'}',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined,
                              color: Color(0xFF00E5CC), size: 20),
                          onPressed: () {
                            Navigator.pop(context);
                            _openReport(r['report_id'], download: false);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_outlined,
                              color: Color(0xFF00E5CC), size: 20),
                          onPressed: () {
                            Navigator.pop(context);
                            _openReport(r['report_id'], download: true);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _promptGenerateReport() async {
    if (_isOfflineCopy) {
      _showSnack('Offline copy — cannot generate report',
          Colors.orangeAccent);
      return;
    }
    if (_generatingReport) return;

    bool includeHeatmap = true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Generate report',
            style: TextStyle(color: Colors.white)),
        content: const Text('Include heatmap analysis in the report?',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              includeHeatmap = false;
              Navigator.pop(context, true);
            },
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              includeHeatmap = true;
              Navigator.pop(context, true);
            },
            child: const Text('Yes',
                style: TextStyle(color: Color(0xFF00E5CC))),
          ),
        ],
      ),
    );
    if (choice != true) return;

    setState(() => _generatingReport = true);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
      ),
    );

    final result = await ApiService.generateReport(
      _currentHashId,
      includeHeatmap: includeHeatmap,
    );

    if (!mounted) return;
    Navigator.pop(context);
    setState(() => _generatingReport = false);

    if (result['success'] == true) {
      _showSnack(
        result['reused'] == true
            ? 'Report already exists'
            : 'Report generated',
        const Color(0xFF10B981),
      );

      // Refresh the image detail to pick up the new report
      await _refreshImageDetail();
    } else {
      _showSnack(
          result['error'] ?? 'Failed to generate report', Colors.redAccent);
    }
  }

  Future<void> _refreshImageDetail() async {
    final data = await ApiService.getMyImageDetail(_currentHashId);
    if (!mounted) return;
    if (data['success'] == true) {
      setState(() {
        _data = data['data'];
        _reports = _extractReports(data['data']);
      });
    }
  }

  // ============================================================
  // DOWNLOAD + OPEN REPORT (with JWT)
  // ============================================================
  Future<void> _openReport(String reportId, {required bool download}) async {
    if (_downloadingReport) return;
    setState(() => _downloadingReport = true);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(color: Color(0xFF00E5CC)),
            SizedBox(height: 12),
            Text('Fetching report...',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ??
          prefs.getString('token') ??
          '';

      final path = download ? 'download' : 'view';
      final url = Uri.parse(
        '${ApiService.baseUrl}/api/reports/$reportId/$path/',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/report_$reportId.pdf');
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;
      Navigator.pop(context);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showSnack('Could not open report: ${result.message}',
            Colors.redAccent);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('Could not open report: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _downloadingReport = false);
    }
  }

  // ============================================================
  // SNACK HELPER
  // ============================================================
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ============================================================
  // SLIDES
  // ============================================================
  List<Map<String, String>> _buildSlides() => _buildSlidesFromData(_data);

  List<Map<String, String>> _buildSlidesFromData(Map<String, dynamic>? d) {
    if (d == null) return [];
    final edit = d['human_edit_detection'];
    final slides = <Map<String, String>>[];

    if (d['image_url'] != null) {
      slides.add({'url': d['image_url'], 'label': 'Original'});
    }
    if (edit != null && edit['heatmap_url'] != null) {
      slides.add({'url': edit['heatmap_url'], 'label': 'Heatmap'});
    }
    if (edit != null && edit['overlay_url'] != null) {
      slides.add({'url': edit['overlay_url'], 'label': 'Overlay'});
    }
    return slides;
  }

  // ============================================================
  // CHAT
  // ============================================================
  Future<void> _refreshChatHistory() async {
    if (_isOfflineCopy) return;
    final data = await ApiService.getMyImageDetail(_currentHashId);
    if (!mounted) return;
    if (data['success'] == true) {
      setState(() {
        _data = data['data'];
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendQuestion() async {
    if (_isOfflineCopy) {
      _showSnack(
          'Offline copy — connect to internet to ask questions',
          Colors.orangeAccent);
      return;
    }

    final question = _questionController.text.trim();
    if (question.isEmpty || _sendingQuestion) return;

    setState(() => _sendingQuestion = true);

    final chatHistory = List<Map<String, dynamic>>.from(
      (_data?['chat_history'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
    chatHistory.add({
      'question': question,
      'answer': '⏳ Thinking...',
      'asked_at_formatted': 'Just now',
    });

    setState(() {
      _data = {...?_data, 'chat_history': chatHistory};
      _questionController.clear();
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    final result = await ApiService.askQuestion(_currentHashId, question);
    if (!mounted) return;
    setState(() => _sendingQuestion = false);

    if (result['success'] == true) {
      await _refreshChatHistory();
    } else {
      final updatedHistory = List<Map<String, dynamic>>.from(
        (_data?['chat_history'] as List? ?? []).cast<Map<String, dynamic>>(),
      );
      if (updatedHistory.isNotEmpty) {
        updatedHistory[updatedHistory.length - 1]['answer'] =
            '❌ ${result['error'] ?? 'Failed to get answer'}';
      }
      setState(() {
        _data = {...?_data, 'chat_history': updatedHistory};
      });
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1428),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1428),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00E5CC)),
        title: Text(
          _data?['filename'] ?? 'Loading...',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: _buildAppBarActions(),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
            )
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                )
              : Stack(
                  children: [
                    _buildContent(),
                    if (_switching)
                      Container(
                        color: const Color(0xFF0A1428).withOpacity(0.6),
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF00E5CC)),
                        ),
                      ),
                    if (_imageIds.isNotEmpty && _currentIndex >= 0)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_currentIndex + 1} / ${_imageIds.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    _buildChatButton(),
                    if (_chatOpen) _buildChatWindow(),
                  ],
                ),
    );
  }

  // ============================================================
  // APPBAR ACTIONS  (Report icon shows count)
  // ============================================================
  List<Widget> _buildAppBarActions() {
    if (_data == null) return [];

    final reportCount = _reports.length;

    return [
      IconButton(
        tooltip: _hasOfflineSave ? 'Saved for offline' : 'Save for offline',
        icon: Icon(
          _hasOfflineSave
              ? Icons.download_done
              : Icons.download_for_offline_outlined,
          color: _hasOfflineSave
              ? Colors.greenAccent
              : const Color(0xFF00E5CC),
          size: 22,
        ),
        onPressed: _hasOfflineSave ? null : _saveOffline,
      ),

      IconButton(
        tooltip: _isPublic ? 'Make private' : 'Make public',
        icon: _togglingPublic
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00E5CC),
                ),
              )
            : Icon(
                _isPublic ? Icons.public : Icons.public_off,
                color: _isPublic
                    ? const Color(0xFF10B981)
                    : const Color(0xFF00E5CC),
                size: 22,
              ),
        onPressed: _togglingPublic ? null : _togglePublic,
      ),

      // ---- REPORT ICON with badge ----
      Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'Reports',
            icon: _generatingReport || _downloadingReport
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E5CC),
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: Color(0xFF00E5CC),
                    size: 22,
                  ),
            onPressed:
                _generatingReport || _downloadingReport ? null : _showReportMenu,
          ),
          if (reportCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF00E5CC),
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  reportCount > 9 ? '9+' : '$reportCount',
                  style: const TextStyle(
                    color: Color(0xFF0A1428),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),

      IconButton(
        tooltip: 'Delete image',
        icon: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 22,
        ),
        onPressed: _deleteImage,
      ),
    ];
  }

  // ============================================================
  // MAIN CONTENT
  // ============================================================
  Widget _buildContent() {
    final d = _data!;
    final ai = d['ai_detection'];
    final edit = d['human_edit_detection'];
    final metadata = d['metadata'];
    final verdict = d['verdict'];
    final slides = _buildSlides();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOfflineCopy)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.orangeAccent.withOpacity(0.4)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.cloud_off,
                      color: Colors.orangeAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline copy — chat is read-only until you reconnect',
                      style: TextStyle(
                          color: Colors.orangeAccent, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          if (!_isOfflineCopy && _hasOfflineSave)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.cloud_done,
                      color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Also saved on this device for offline viewing',
                      style: TextStyle(
                          color: Color(0xFF10B981), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          if (_isPublic && !_isOfflineCopy)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0088FF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF0088FF).withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.public,
                      color: Color(0xFF0088FF), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This image is public — anyone with the link can view it',
                      style: TextStyle(
                          color: Color(0xFF0088FF), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          if (slides.isNotEmpty) _buildImageTabs(slides),
          const SizedBox(height: 16),

          if (verdict != null) _verdictCard(verdict),
          const SizedBox(height: 12),

          Row(
            children: [
              if (ai != null)
                Expanded(
                  child: _compactScoreCard(
                    'AI',
                    '${ai['ai_percentage']}%',
                    const Color(0xFFE11D48),
                  ),
                ),
              if (ai != null && edit != null) const SizedBox(width: 8),
              if (edit != null)
                Expanded(
                  child: _compactScoreCard(
                    'Edit',
                    '${edit['edit_percentage']}%',
                    const Color(0xFFEA580C),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          if (metadata != null) ...[
            _sectionTitle('Metadata'),
            _infoCard([
              _row(
                'Device',
                '${metadata['camera_make'] ?? ''} ${metadata['camera_model'] ?? ''}'
                        .trim()
                        .isEmpty
                    ? 'Unknown'
                    : '${metadata['camera_make'] ?? ''} ${metadata['camera_model'] ?? ''}'
                        .trim(),
              ),
              _row(
                'Software',
                (metadata['software'] == null ||
                        metadata['software'].toString().isEmpty)
                    ? 'None detected'
                    : metadata['software'],
              ),
              _row(
                'Capture Date',
                (metadata['date_original'] == null ||
                        metadata['date_original'].toString().isEmpty)
                    ? '—'
                    : metadata['date_original'],
              ),
              _row(
                'Last Modified',
                (metadata['modify_date'] == null ||
                        metadata['modify_date'].toString().isEmpty)
                    ? '—'
                    : metadata['modify_date'],
              ),
              _row(
                'C2PA',
                metadata['c2pa_present'] == true
                    ? 'Present ✅'
                    : 'Not present ❌',
              ),
            ]),
            const SizedBox(height: 80),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // IMAGE TABS
  // ============================================================
  Widget _buildImageTabs(List<Map<String, String>> slides) {
    if (_currentSlide >= slides.length) _currentSlide = 0;

    final current = slides[_currentSlide];
    final url = current['url'] ?? '';
    final isLocal = url.startsWith('/') || url.startsWith('file://');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF13223A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00E5CC).withOpacity(0.25),
            ),
          ),
          child: Row(
            children: List.generate(slides.length, (i) {
              final slide = slides[i];
              final active = i == _currentSlide;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _currentSlide = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF00E5CC),
                                Color(0xFF0088FF)
                              ],
                            )
                          : null,
                      color: active ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        slide['label'] ?? '',
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : const Color(0xFF00E5CC),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            _dragDistance += details.primaryDelta ?? 0;
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            final dist = _dragDistance;
            _dragDistance = 0;

            if (velocity < -200 || dist < -80) {
              _goToNext();
            } else if (velocity > 200 || dist > 80) {
              _goToPrevious();
            }
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: 420,
                  color: const Color(0xFF0F1A2E),
                  child: isLocal
                      ? Image.file(File(url), fit: BoxFit.contain)
                      : Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF00E5CC),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.grey, size: 60),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // FLOATING CHAT BUTTON
  // ============================================================
  Widget _buildChatButton() {
    final chatCount = (_data?['chat_history'] as List?)?.length ?? 0;
    final hasChat = chatCount > 0;

    return Positioned(
      right: 20,
      bottom: 20,
      child: GestureDetector(
        onTap: () => setState(() => _chatOpen = !_chatOpen),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5CC), Color(0xFF0088FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5CC).withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                _chatOpen ? Icons.close : Icons.chat_bubble_outline,
                color: Colors.white,
                size: 28,
              ),
            ),
            if (hasChat && !_chatOpen)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE11D48),
                    shape: BoxShape.circle,
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Text(
                    chatCount > 9 ? '9+' : '$chatCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHAT POPUP
  // ============================================================
  Widget _buildChatWindow() {
    final chatHistory = _data?['chat_history'] as List? ?? [];

    return Positioned(
      right: 20,
      bottom: 90,
      left: 20,
      child: Container(
        height: 500,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1A2E),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: const Color(0xFF00E5CC).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00E5CC), Color(0xFF0088FF)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ask About This Image',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${chatHistory.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: chatHistory.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 60,
                                color: const Color(0xFF00E5CC)
                                    .withOpacity(0.4)),
                            const SizedBox(height: 16),
                            const Text(
                              'Ask me anything about this image',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Try: "Is this AI generated?"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: chatHistory.length,
                      itemBuilder: (context, index) {
                        final q = chatHistory[index] as Map<String, dynamic>;
                        return _chatBubble(q);
                      },
                    ),
            ),

            if (!_isOfflineCopy)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF1A2C4A)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questionController,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendQuestion(),
                        decoration: InputDecoration(
                          hintText: 'Ask a question...',
                          hintStyle: const TextStyle(
                              color: Color(0xFF6B8299), fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF1A2C4A),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendingQuestion ? null : _sendQuestion,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF00E5CC),
                              Color(0xFF0088FF)
                            ],
                          ),
                        ),
                        child: _sendingQuestion
                            ? const Padding(
                                padding: EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send,
                                color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF1A2C4A)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.lock, size: 14, color: Colors.grey),
                    SizedBox(width: 6),
                    Text(
                      'Offline mode — connect to internet to chat',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHAT BUBBLE
  // ============================================================
  Widget _chatBubble(Map<String, dynamic> q) {
    final answer = q['answer'] ?? '';
    final isLoading = answer.toString().startsWith('⏳');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00E5CC), Color(0xFF0088FF)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                q['question'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF1A2C4A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.smart_toy,
                      size: 14, color: Color(0xFF00E5CC)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: isLoading
                        ? const _TypingIndicator()
                        : MarkdownBody(
                            data: answer,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Color(0xFFE0E0E0),
                                fontSize: 12,
                                height: 1.4,
                              ),
                              strong: const TextStyle(
                                color: Color(0xFF00E5CC),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              em: const TextStyle(
                                color: Color(0xFF00E5CC),
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                              code: const TextStyle(
                                backgroundColor: Color(0xFF0F1A2E),
                                color: Color(0xFFFFB86C),
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                              listBullet: const TextStyle(
                                color: Color(0xFF00E5CC),
                                fontSize: 12,
                              ),
                              h1: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              h2: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              h3: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Widget _verdictCard(Map<String, dynamic> verdict) {
    final text = verdict['verdict'] ?? 'Unknown';
    final confidence = verdict['confidence_score'] ?? 0;
    final v = text.toString().toUpperCase();

    Color color = const Color(0xFF10B981);
    if (v.contains('AI')) color = const Color(0xFFE11D48);
    else if (v.contains('EDIT')) color = const Color(0xFFEA580C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient:
            LinearGradient(colors: [color, color.withOpacity(0.6)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VERDICT',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${confidence.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactScoreCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF13223A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13223A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: rows),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TYPING INDICATOR
// ============================================================
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay) % 1.0;
            final offset = (t < 0.5) ? t * 2 : (1 - t) * 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, -offset * 4),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E5CC),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}