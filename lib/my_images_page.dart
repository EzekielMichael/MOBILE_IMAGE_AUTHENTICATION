import 'package:flutter/material.dart';
import 'api_service.dart';
import 'my_image_detail_page.dart';

class MyImagesPage extends StatefulWidget {
  const MyImagesPage({super.key});

  @override
  State<MyImagesPage> createState() => _MyImagesPageState();
}

class _MyImagesPageState extends State<MyImagesPage> {
  List<dynamic> _allImages = [];    // Full raw list from API
  List<dynamic> _displayed = [];    // After filtering + sorting
  String _role = 'user';
  bool _loading = true;
  String? _error;

  // Filter + Sort state
  String _filter = 'all';             // all | authentic | ai_generated | human_edited | not_analyzed
  String _sort = 'newest';            // newest | oldest | name_asc | name_desc

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  // ============================================================
  // DATA LOADING
  // ============================================================
  Future<void> _loadImages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final data = await ApiService.getMyImages();

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (data['success'] == true) {
        _allImages = data['images'] ?? [];
        _role = data['role'] ?? 'user';
        _applyFilterAndSort();
      } else {
        _error = data['error'] ?? 'Failed to load images';
      }
    });
  }

  // ============================================================
  // FILTER + SORT LOGIC
  // ============================================================
  void _applyFilterAndSort() {
    List<dynamic> filtered = List.from(_allImages);

    // ---- FILTER ----
    if (_filter != 'all') {
      filtered = filtered.where((img) {
        final verdict = _verdictOf(img).toUpperCase();
        switch (_filter) {
          case 'authentic':
            return verdict.contains('AUTHENTIC');
          case 'ai_generated':
            return verdict.contains('AI');
          case 'human_edited':
            return verdict.contains('EDIT') || verdict.contains('MANIPULATED');
          case 'not_analyzed':
            return verdict.isEmpty ||
                verdict.contains('NOT ANALYZED') ||
                verdict.contains('UNKNOWN');
          default:
            return true;
        }
      }).toList();
    }

    // ---- SORT ----
    filtered.sort((a, b) {
      switch (_sort) {
        case 'name_asc':
          return (a['filename'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['filename'] ?? '').toString().toLowerCase());
        case 'name_desc':
          return (b['filename'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((a['filename'] ?? '').toString().toLowerCase());
        case 'oldest':
          return (a['uploaded_at'] ?? '')
              .toString()
              .compareTo((b['uploaded_at'] ?? '').toString());
        case 'newest':
        default:
          return (b['uploaded_at'] ?? '')
              .toString()
              .compareTo((a['uploaded_at'] ?? '').toString());
      }
    });

    setState(() {
      _displayed = filtered;
    });
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
    _applyFilterAndSort();
  }

  void _setSort(String value) {
    setState(() => _sort = value);
    _applyFilterAndSort();
  }

  // ============================================================
  // HELPERS
  // ============================================================
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

  String _roleBadge() {
    if (_role == 'superuser') return '👑 Superuser View (All Images)';
    if (_role == 'staff') return '🛡️ Staff View (Your + Users)';
    return '👤 Your Images';
  }

  // Count for each filter (based on full unfiltered list)
  int _countFor(String filter) {
    if (filter == 'all') return _allImages.length;
    return _allImages.where((img) {
      final verdict = _verdictOf(img).toUpperCase();
      switch (filter) {
        case 'authentic':
          return verdict.contains('AUTHENTIC');
        case 'ai_generated':
          return verdict.contains('AI');
        case 'human_edited':
          return verdict.contains('EDIT') || verdict.contains('MANIPULATED');
        case 'not_analyzed':
          return verdict.isEmpty ||
              verdict.contains('NOT ANALYZED') ||
              verdict.contains('UNKNOWN');
        default:
          return false;
      }
    }).length;
  }

  String _sortLabel() {
    switch (_sort) {
      case 'oldest':
        return 'Oldest First';
      case 'name_asc':
        return 'Name (A-Z)';
      case 'name_desc':
        return 'Name (Z-A)';
      case 'newest':
      default:
        return 'Newest First';
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
        title: const Text('My Images',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          // Sort menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Color(0xFF00E5CC)),
            color: const Color(0xFF13223A),
            onSelected: _setSort,
            itemBuilder: (context) => [
              _sortItem('newest', 'Newest First', Icons.schedule),
              _sortItem('oldest', 'Oldest First', Icons.history),
              _sortItem('name_asc', 'Name (A-Z)', Icons.sort_by_alpha),
              _sortItem('name_desc', 'Name (Z-A)', Icons.sort_by_alpha),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: Column(
        children: [
          // Role badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF13223A),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _roleBadge(),
                    style: const TextStyle(
                      color: Color(0xFF00E5CC),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Current sort indicator
                Row(
                  children: [
                    const Icon(Icons.sort,
                        size: 12, color: Color(0xFF00E5CC)),
                    const SizedBox(width: 4),
                    Text(
                      _sortLabel(),
                      style: const TextStyle(
                        color: Color(0xFF00E5CC),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter chips
          Container(
            color: const Color(0xFF0F1A2E),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _filterChip('all', 'All', _countFor('all')),
                  const SizedBox(width: 8),
                  _filterChip('authentic', 'auth',
                      _countFor('authentic')),
                  const SizedBox(width: 8),
                  _filterChip('ai_generated', 'AI',
                      _countFor('ai_generated')),
                  const SizedBox(width: 8),
                  _filterChip('human_edited', 'Edit',
                      _countFor('human_edited')),
                  const SizedBox(width: 8),
                  _filterChip('not_analyzed', 'not',
                      _countFor('not_analyzed')),
                ],
              ),
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ============================================================
  // FILTER CHIP
  // ============================================================
  Widget _filterChip(String value, String label, int count) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => _setFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E5CC) : const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF00E5CC)
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF0A1428) : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF0A1428).withOpacity(0.2)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: active ? const Color(0xFF0A1428) : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SORT MENU ITEM
  // ============================================================
  PopupMenuItem<String> _sortItem(
      String value, String label, IconData icon) {
    final active = _sort == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? const Color(0xFF00E5CC) : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF00E5CC) : Colors.white,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
          if (active)
            const Icon(Icons.check,
                size: 16, color: Color(0xFF00E5CC)),
        ],
      ),
    );
  }

  // ============================================================
  // BODY
  // ============================================================
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
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 60),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadImages,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5CC),
              ),
              child: const Text('Retry',
                  style: TextStyle(color: Color(0xFF0A1428))),
            ),
          ],
        ),
      );
    }

    if (_displayed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filter == 'all'
                  ? Icons.image_not_supported
                  : Icons.filter_alt_off,
              color: Colors.grey,
              size: 80,
            ),
            const SizedBox(height: 16),
            Text(
              _filter == 'all'
                  ? 'No images yet'
                  : 'No images match this filter',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (_filter != 'all') ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _setFilter('all'),
                child: const Text(
                  'Clear Filter',
                  style: TextStyle(color: Color(0xFF00E5CC)),
                ),
              ),
            ],
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
        itemCount: _displayed.length,
        itemBuilder: (context, index) => _imageCard(_displayed[index]),
      ),
    );
  }

  // ============================================================
  // IMAGE CARD
  // ============================================================
  Widget _imageCard(Map<String, dynamic> img) {
    final imageUrl = img['image_url'] ?? '';
    final filename = img['filename'] ?? 'Unknown';
    final verdict = _verdictOf(img);
    final vColor = _verdictColor(verdict);
    final hashId = img['hash_id'] ?? '';

    final ai = img['ai_detection'];
    final edit = img['human_edit_detection'];

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyImageDetailPage(hashId: hashId),
          ),
        );
        // Optional: refresh list on return (in case saved offline)
        // _loadImages();
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
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF0F1A2E),
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey),
                      ),
                    ),
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
                        Icon(Icons.memory,
                            size: 12, color: Colors.red.shade400),
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
                        Icon(Icons.edit,
                            size: 12, color: Colors.orange.shade400),
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
