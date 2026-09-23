import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'dart:async';
import 'api_service.dart';

class PublicImageDetailPage extends StatefulWidget {
  final String shareToken;
  const PublicImageDetailPage({super.key, required this.shareToken});

  @override
  State<PublicImageDetailPage> createState() => _PublicImageDetailPageState();
}

class _PublicImageDetailPageState extends State<PublicImageDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  // Chat
  bool _chatOpen = false;
  final ScrollController _chatScrollController = ScrollController();

  // Carousel
  final PageController _pageController = PageController();
  int _currentSlide = 0;
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD
  // ============================================================
  Future<void> _load() async {
    final data = await ApiService.getPublicImageByToken(widget.shareToken);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data['success'] == true) {
        _data = data['data'];
        _startAutoSlide();
      } else {
        _error = data['error'] ?? 'Failed to load';
      }
    });
  }

  // ============================================================
  // SLIDES
  // ============================================================
  List<Map<String, String>> _buildSlides() {
    if (_data == null) return [];
    final d = _data!;
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

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    final slides = _buildSlides();
    if (slides.length <= 1) return;

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentSlide + 1) % slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
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
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
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
                    _buildChatButton(),
                    if (_chatOpen) _buildChatWindow(),
                  ],
                ),
    );
  }

  // ============================================================
  // MAIN CONTENT
  // ============================================================
  Widget _buildContent() {
    final d = _data!;
    final ai = d['ai_detection'];
    final edit = d['human_edit_detection'];
    final heatmap = d['heatmap_analysis'];
    final metadata = d['metadata'];
    final verdict = d['verdict'];
    final slides = _buildSlides();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slides.isNotEmpty) _buildCarousel(slides),
          const SizedBox(height: 16),

          // Verdict
          if (verdict != null) _verdictCard(verdict),
          const SizedBox(height: 12),

          // Scores
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

          // Heatmap Analysis
          if (heatmap != null) ...[
            _sectionTitle('Heatmap Analysis'),
            _infoCard([
              _row('Severity', heatmap['severity_level'] ?? '-'),
              _row('Primary Region', heatmap['primary_region'] ?? '-'),
              _row('Secondary Region', heatmap['secondary_region'] ?? '-'),
              _row('Edited %',
                  '${heatmap['edited_percentage']?.toStringAsFixed(1) ?? '0'}%'),
              _row('Edit Zones', '${heatmap['edit_zones_count'] ?? 0}'),
            ]),
            const SizedBox(height: 20),
          ],

          // Metadata
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
  // CAROUSEL
  // ============================================================
  Widget _buildCarousel(List<Map<String, String>> slides) {
    return Column(
      children: [
        // Label above
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Container(
            key: ValueKey(_currentSlide),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF13223A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00E5CC).withOpacity(0.4),
              ),
            ),
            child: Text(
              slides.isNotEmpty ? (slides[_currentSlide]['label'] ?? '') : '',
              style: const TextStyle(
                color: Color(0xFF00E5CC),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Image viewer
        SizedBox(
          height: 420,
          child: PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _currentSlide = index);
            },
            itemBuilder: (context, index) {
              final slide = slides[index];
              final url = slide['url'] ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: const Color(0xFF0F1A2E),
                    child: Image.network(
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
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Dots
        if (slides.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slides.length, (i) {
              final active = i == _currentSlide;
              return GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF00E5CC)
                        : Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  // ============================================================
  // FLOATING CHAT BUTTON
  // ============================================================
  Widget _buildChatButton() {
    final chatHistory = _data?['chat_history'] as List? ?? [];
    final hasChat = chatHistory.isNotEmpty;

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
                    chatHistory.length > 9
                        ? '9+'
                        : '${chatHistory.length}',
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
  // CHAT WINDOW (read-only for public viewers)
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
          border: Border.all(color: const Color(0xFF00E5CC).withOpacity(0.3)),
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
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      'Chat History',
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

            // Messages
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
                              'No chat history yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'The original owner has not asked any questions',
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

            // Footer (read-only notice)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF1A2C4A)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.visibility, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Read-only — shared public view',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
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
  // CHAT BUBBLE (with markdown)
  // ============================================================
  Widget _chatBubble(Map<String, dynamic> q) {
    final answer = q['answer'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question
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

          // Answer
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
                    child: MarkdownBody(
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
        gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}