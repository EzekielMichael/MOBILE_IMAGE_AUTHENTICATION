import 'package:flutter/material.dart';
import 'api_service.dart';
import 'public_image_detail_page.dart';

class PublicGalleryPage extends StatefulWidget {
  const PublicGalleryPage({super.key});

  @override
  State<PublicGalleryPage> createState() => _PublicGalleryPageState();
}

class _PublicGalleryPageState extends State<PublicGalleryPage> {
  List<dynamic> _images = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final data = await ApiService.getPublicImages(filter: _filter);

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (data['success'] == true) {
        _images = data['results'] ?? [];
      } else {
        _error = data['error'] ?? 'Failed to load images';
      }
    });
  }

  String _verdictOf(Map img) {
    final verdict = img['verdict'];
    return verdict?['verdict'] ?? 'Not Analyzed';
  }

  Color _verdictColor(String verdict) {
    final v = verdict.toUpperCase();
    if (v.contains('AUTHENTIC')) return const Color(0xFF10B981);
    if (v.contains('AI')) return const Color(0xFFE11D48);
    if (v.contains('EDIT') || v.contains('MANIPULATED')) {
      return const Color(0xFFEA580C);
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1428),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1428),
        elevation: 0,
        title: const Text('Public Gallery', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Color(0xFF00E5CC)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('All', 'all'),
                const SizedBox(width: 8),
                _filterChip('Authentic', 'authentic'),
                const SizedBox(width: 8),
                _filterChip('AI Generated', 'ai_generated'),
                const SizedBox(width: 8),
                _filterChip('Human Edited', 'human_edited'),
              ],
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = value);
        _loadImages();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E5CC) : const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF00E5CC) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF0A1428) : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadImages,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5CC),
              ),
              child: const Text('Retry', style: TextStyle(color: Color(0xFF0A1428))),
            ),
          ],
        ),
      );
    }

    if (_images.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey, size: 80),
            SizedBox(height: 16),
            Text('No public images yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadImages,
      color: const Color(0xFF00E5CC),
      backgroundColor: const Color(0xFF13223A),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: _images.length,
        itemBuilder: (context, index) {
          final img = _images[index];
          return _imageCard(img);
        },
      ),
    );
  }

  Widget _imageCard(Map<String, dynamic> img) {
    final imageUrl = img['image_url'] ?? '';
    final filename = img['filename'] ?? 'Unknown';
    final verdict = _verdictOf(img);
    final vColor = _verdictColor(verdict);
    final token = img['public_share_token'] ?? '';

    final ai = img['ai_detection'];
    final edit = img['human_edit_detection'];

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PublicImageDetailPage(shareToken: token),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF0F1A2E),
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: const Color(0xFF0F1A2E),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF00E5CC),
                              strokeWidth: 2,
                            ),
                          ),
                        );
                      },
                    ),
                    // Verdict badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: vColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          verdict.length > 15
                              ? '${verdict.substring(0, 15)}...'
                              : verdict,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (ai != null) ...[
                        Icon(Icons.memory, size: 12, color: Colors.red.shade400),
                        const SizedBox(width: 3),
                        Text(
                          '${ai['ai_percentage']}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (edit != null) ...[
                        Icon(Icons.edit, size: 12, color: Colors.orange.shade400),
                        const SizedBox(width: 3),
                        Text(
                          '${edit['edit_percentage']}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}