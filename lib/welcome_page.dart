import 'package:flutter/material.dart';
import 'api_service.dart';
import 'login_page.dart';
import 'public_gallery_page.dart';
import 'public_image_detail_page.dart';
import 'my_images_page.dart';
import 'my_image_detail_page.dart';
import 'saved_results_page.dart';
import 'upload_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  Map<String, dynamic>? _user;
  List<dynamic> _recentUploads = [];
  List<dynamic> _recentPublic = [];
  Map<String, dynamic> _stats = {
    'total': 0,
    'ai': 0,
    'edited': 0,
    'authentic': 0,
  };

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  // ============================================================
  // HELPERS
  // ============================================================
  /// Extract verdict text from either:
  ///   - a nested object  { verdict: { verdict: "AI Generated Image" } }
  ///   - a flat string    "AI Generated Image"
  ///   - null / missing
  String _verdictOf(Map img) {
    final v = img['verdict'];
    if (v == null) return 'Not Analyzed';
    if (v is String) return v.isEmpty ? 'Not Analyzed' : v;
    if (v is Map) {
      final inner = v['verdict'];
      if (inner == null) return 'Not Analyzed';
      final s = inner.toString();
      return s.isEmpty ? 'Not Analyzed' : s;
    }
    return 'Not Analyzed';
  }

  Color _verdictColor(String verdict) {
    final v = verdict.toUpperCase();
    if (v.contains('AUTHENTIC')) return const Color(0xFF10B981);
    if (v.contains('AI')) return const Color(0xFFE11D48);
    if (v.contains('EDIT') || v.contains('MANIPULATED')) {
      return const Color(0xFFEA580C);
    }
    return const Color(0xFF6B8299);
  }

  // ============================================================
  // LOAD DASHBOARD DATA
  // ============================================================
  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final meData = await ApiService.me();
    if (meData['success'] != true) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = meData['error'] ?? 'Failed to load profile';
      });
      return;
    }

    // Fetch in parallel for speed
    final results = await Future.wait([
      ApiService.getMyImages(),
      ApiService.getPublicImages(),
    ]);

    final myImagesResp = results[0];
    final publicImagesResp = results[1];

    if (!mounted) return;

    // ✅ My images: key is "images"
    final myImages = (myImagesResp['success'] == true &&
            myImagesResp['images'] is List)
        ? List<dynamic>.from(myImagesResp['images'])
        : <dynamic>[];

    // ✅ Public images: key is "results"
    final publicImages = (publicImagesResp['success'] == true &&
            publicImagesResp['results'] is List)
        ? List<dynamic>.from(publicImagesResp['results'])
        : <dynamic>[];

    // Stats — use nested-safe verdict extractor
    int ai = 0, edited = 0, authentic = 0;
    for (final img in myImages) {
      if (img is! Map) continue;
      final v = _verdictOf(img).toUpperCase();
      if (v.contains('AI')) {
        ai++;
      } else if (v.contains('EDIT') || v.contains('MANIPULATED')) {
        edited++;
      } else if (v.contains('AUTHENTIC')) {
        authentic++;
      }
    }

    setState(() {
      _loading = false;
      _user = meData['user'];
      _recentUploads = myImages.take(3).toList();
      _recentPublic = publicImages.take(3).toList();
      _stats = {
        'total': myImages.length,
        'ai': ai,
        'edited': edited,
        'authentic': authentic,
      };
    });
  }

  // ============================================================
  // ACTIONS
  // ============================================================
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Sign out?',
            style: TextStyle(color: Colors.white)),
        content: const Text('You will need to sign in again.',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await ApiService.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _openUpload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UploadPage()),
    );
    _loadDashboard();
  }

  void _openMyImages() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MyImagesPage()))
        .then((_) => _loadDashboard());
  }

  void _openGallery() {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const PublicGalleryPage()))
        .then((_) => _loadDashboard());
  }

  void _openSaved() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedResultsPage()),
    );
  }

  void _openImageDetail(Map img, {required bool isPublic}) {
    if (isPublic) {
      final token = img['public_share_token'] ?? '';
      if (token.toString().isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublicImageDetailPage(shareToken: token),
        ),
      );
    } else {
      final hashId = img['hash_id'] ?? '';
      if (hashId.toString().isEmpty) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => MyImageDetailPage(hashId: hashId),
            ),
          )
          .then((_) => _loadDashboard());
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A1428),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A1428),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadDashboard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5CC),
                ),
                child: const Text('Retry',
                    style: TextStyle(color: Color(0xFF0A1428))),
              ),
            ],
          ),
        ),
      );
    }

    final name = _user?['full_name'] ?? _user?['username'] ?? 'User';
    final firstLetter =
        name.toString().isEmpty ? 'U' : name.toString()[0].toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1428),
      body: RefreshIndicator(
        color: const Color(0xFF00E5CC),
        backgroundColor: const Color(0xFF13223A),
        onRefresh: _loadDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ============================================================
              // HEADER
              // ============================================================
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF00E5CC), Color(0xFF0088FF)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        firstLetter,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh,
                        color: Color(0xFF00E5CC)),
                    onPressed: _loadDashboard,
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout,
                        color: Color(0xFF00E5CC)),
                    onPressed: _logout,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ============================================================
              // BIG UPLOAD CTA
              // ============================================================
              GestureDetector(
                onTap: _openUpload,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5CC), Color(0xFF0088FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5CC).withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload,
                            color: Colors.white, size: 30),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analyze a New Image',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Upload or capture a photo to detect AI / edits',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ============================================================
              // STATS
              // ============================================================
              _sectionTitle('Your Analysis Overview'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Total',
                      '${_stats['total']}',
                      Icons.photo_library_outlined,
                      const Color(0xFF00E5CC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      'AI',
                      '${_stats['ai']}',
                      Icons.smart_toy_outlined,
                      const Color(0xFFE11D48),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Edited',
                      '${_stats['edited']}',
                      Icons.edit_outlined,
                      const Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      'Authentic',
                      '${_stats['authentic']}',
                      Icons.verified_outlined,
                      const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ============================================================
              // QUICK NAV
              // ============================================================
              _sectionTitle('Explore'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _navTile(
                      icon: Icons.photo_library,
                      label: 'My Images',
                      onTap: _openMyImages,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _navTile(
                      icon: Icons.public,
                      label: 'Public Gallery',
                      onTap: _openGallery,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _navTile(
                      icon: Icons.download_for_offline_outlined,
                      label: 'Saved',
                      onTap: _openSaved,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ============================================================
              // RECENT UPLOADS
              // ============================================================
              Row(
                children: [
                  _sectionTitle('Recent Uploads'),
                  const Spacer(),
                  if (_recentUploads.isNotEmpty)
                    TextButton(
                      onPressed: _openMyImages,
                      child: const Text(
                        'See all',
                        style: TextStyle(
                            color: Color(0xFF00E5CC), fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              if (_recentUploads.isEmpty)
                _emptyCard(
                  icon: Icons.image_outlined,
                  title: 'No images yet',
                  subtitle: 'Tap "Analyze a New Image" to get started.',
                )
              else
                ..._recentUploads.map(
                  (img) => _imageRow(
                    img,
                    isPublic: false,
                    onTap: () => _openImageDetail(img, isPublic: false),
                  ),
                ),

              const SizedBox(height: 24),

              // ============================================================
              // RECENT PUBLIC SHARES
              // ============================================================
              Row(
                children: [
                  _sectionTitle('Recently Shared Publicly'),
                  const Spacer(),
                  if (_recentPublic.isNotEmpty)
                    TextButton(
                      onPressed: _openGallery,
                      child: const Text(
                        'See all',
                        style: TextStyle(
                            color: Color(0xFF00E5CC), fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              if (_recentPublic.isEmpty)
                _emptyCard(
                  icon: Icons.public_off,
                  title: 'No public images',
                  subtitle:
                      'Reports you share publicly will appear here.',
                )
              else
                ..._recentPublic.map(
                  (img) => _imageRow(
                    img,
                    isPublic: true,
                    onTap: () => _openImageDetail(img, isPublic: true),
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WIDGETS
  // ============================================================
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF13223A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5CC).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF00E5CC), size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF13223A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade600),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _imageRow(
    Map<String, dynamic> img, {
    required bool isPublic,
    required VoidCallback onTap,
  }) {
    // Support multiple possible keys from serializer
    final imageUrl = img['image_url'] ??
        img['image'] ??
        img['thumbnail_url'] ??
        '';
    final filename = img['filename'] ?? 'Unknown';
    final verdict = _verdictOf(img);
    final verdictColor = _verdictColor(verdict);
    final uploader = (img['uploaded_by'] ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 60,
                height: 60,
                color: const Color(0xFF0F1A2E),
                child: imageUrl.toString().isNotEmpty
                    ? Image.network(
                        imageUrl.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image,
                          color: Colors.grey,
                        ),
                      )
                    : const Icon(Icons.image, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: verdictColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          verdict.length > 22
                              ? '${verdict.substring(0, 22)}…'
                              : verdict,
                          style: TextStyle(
                            color: verdictColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isPublic && uploader.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.person,
                            size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            uploader,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
