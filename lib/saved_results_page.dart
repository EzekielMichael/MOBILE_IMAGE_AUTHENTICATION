import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_service.dart';
import 'my_image_detail_page.dart';

class SavedResultsPage extends StatefulWidget {
  /// Optional: if not passed, we load from SharedPreferences.
  final String? userId;

  const SavedResultsPage({super.key, this.userId});

  @override
  State<SavedResultsPage> createState() => _SavedResultsPageState();
}

class _SavedResultsPageState extends State<SavedResultsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _userId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ============================================================
  // LOAD USER ID + SAVED ITEMS
  // ============================================================
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // 1. Resolve userId
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      _userId = widget.userId;
    } else {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('user_id');
    }

    if (_userId == null || _userId!.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Please sign in to see your saved results.';
      });
      return;
    }

    // 2. Fetch saved items for THIS user only
    final items = await OfflineService.listSaved(_userId!);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  // ============================================================
  // DELETE
  // ============================================================
  Future<void> _delete(String hashId) async {
    if (_userId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13223A),
        title: const Text('Delete saved result?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will remove the offline copy from your device.',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true && _userId != null) {
      await OfflineService.deleteSaved(_userId!, hashId);
      await _load();
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Color _verdictColor(String verdict) {
    final v = verdict.toUpperCase();
    if (v.contains('AUTHENTIC')) return const Color(0xFF10B981);
    if (v.contains('AI')) return const Color(0xFFE11D48);
    if (v.contains('EDIT') || v.contains('MANIPULATED')) {
      return const Color(0xFFEA580C);
    }
    return Colors.grey;
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
        title: const Text('Saved Results',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 70, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_for_offline_outlined,
                              size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No saved results yet',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 14)),
                          SizedBox(height: 6),
                          Text('Save a result from an image detail page',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final hashId = item['hash_id'] ?? '';
                        final filename = item['filename'] ?? 'Unknown';
                        final verdict =
                            item['verdict'] ?? 'Not Analyzed';
                        final path = item['path'] ?? '';

                        final originalFile =
                            File('$path/original.jpg');
                        final hasImage = originalFile.existsSync();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13223A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.grey.withOpacity(0.15)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              // Pass userId so the detail page
                              // loads the correct offline copy
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MyImageDetailPage(
                                    hashId: hashId,
                                    preferOffline: true,
                                    userId: _userId,
                                  ),
                                ),
                              );
                              _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Thumbnail
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    child: hasImage
                                        ? Image.file(
                                            originalFile,
                                            width: 70,
                                            height: 70,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 70,
                                            height: 70,
                                            color: const Color(
                                                0xFF0F1A2E),
                                            child: const Icon(Icons.image,
                                                color: Colors.grey),
                                          ),
                                  ),
                                  const SizedBox(width: 12),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          filename,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3),
                                          decoration: BoxDecoration(
                                            color:
                                                _verdictColor(verdict)
                                                    .withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            verdict,
                                            style: TextStyle(
                                              color:
                                                  _verdictColor(verdict),
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Tap to open offline',
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),

                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent),
                                    onPressed: () => _delete(hashId),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}