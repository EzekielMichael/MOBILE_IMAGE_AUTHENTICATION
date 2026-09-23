// lib/upload_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import 'my_image_detail_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  bool _uploading = false;
  double _progress = 0.0;
  String? _error;
  String _status = '';

  // ============================================================
  // PICK FROM GALLERY
  // ============================================================
  Future<void> _pickFromGallery() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImage = File(picked.path);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  // ============================================================
  // CAPTURE WITH CAMERA
  // ============================================================
  Future<void> _captureFromCamera() async {
    try {
      final XFile? captured = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (captured == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImage = File(captured.path);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to capture image: $e');
    }
  }

  // ============================================================
  // CLEAR SELECTION
  // ============================================================
  void _clearSelection() {
    setState(() {
      _selectedImage = null;
      _error = null;
      _progress = 0.0;
      _status = '';
    });
  }

  // ============================================================
  // UPLOAD + ANALYZE
  // ============================================================
  Future<void> _upload() async {
    if (_selectedImage == null) return;

    setState(() {
      _uploading = true;
      _progress = 0.0;
      _status = 'Uploading image...';
      _error = null;
    });

    try {
      // 1. Upload the image
      final uploadResult = await ApiService.uploadImage(_selectedImage!);

      if (uploadResult['success'] != true) {
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = uploadResult['error'] ?? 'Upload failed';
        });
        return;
      }

      final hashId = uploadResult['hash_id'];
      if (hashId == null) {
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = 'Server did not return an image ID';
        });
        return;
      }

      // 2. Animate progress while server analyses
      if (!mounted) return;
      setState(() {
        _progress = 0.4;
        _status = 'Analyzing with AI model...';
      });

      final analysisResult = await ApiService.runAnalysis(hashId);

      if (analysisResult['success'] != true) {
        if (!mounted) return;
        // Even if analysis fails, we can still open the image (it will
        // show as "Not Analyzed" and user can retry).
        setState(() {
          _uploading = false;
          _error = analysisResult['error'] ??
              'Analysis failed — you can retry from the image page';
        });

        // Optional: still navigate
        // _openDetail(hashId);
        return;
      }

      if (!mounted) return;
      setState(() {
        _progress = 1.0;
        _status = 'Done!';
      });

      // 3. Navigate to detail
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MyImageDetailPage(hashId: hashId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Upload error: $e';
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
        title: const Text(
          'Upload Image',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ============================================================
            // HEADER
            // ============================================================
            const SizedBox(height: 8),
            const Icon(Icons.cloud_upload_outlined,
                size: 70, color: Color(0xFF00E5CC)),
            const SizedBox(height: 12),
            const Text(
              'Upload or Capture',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pick an image from your gallery or take a new photo.\n'
              'It will be analyzed for AI generation and manipulation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // ============================================================
            // PREVIEW / PLACEHOLDER
            // ============================================================
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF0F1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedImage == null
                      ? Colors.grey.withOpacity(0.3)
                      : const Color(0xFF00E5CC).withOpacity(0.5),
                  width: _selectedImage == null ? 1 : 2,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedImage == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined,
                              size: 70,
                              color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            'No image selected',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap a button below to choose',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          _selectedImage!,
                          fit: BoxFit.contain,
                        ),
                        // Remove button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _uploading ? null : _clearSelection,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                        // Filename overlay
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedImage!.path
                                  .split('/')
                                  .last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // ============================================================
            // PICK BUTTONS
            // ============================================================
            if (_selectedImage == null && !_uploading) ...[
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.photo_library,
                      label: 'From Gallery',
                      onTap: _pickFromGallery,
                      isPrimary: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.camera_alt,
                      label: 'Take Photo',
                      onTap: _captureFromCamera,
                      isPrimary: true,
                    ),
                  ),
                ],
              ),
            ],

            // ============================================================
            // PROGRESS / STATUS
            // ============================================================
            if (_uploading) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF13223A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00E5CC).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00E5CC),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _status.isEmpty ? 'Processing...' : _status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _progress == 0 ? null : _progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF0F1A2E),
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF00E5CC)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This may take a few seconds…',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],

            // ============================================================
            // ERROR
            // ============================================================
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ============================================================
            // UPLOAD BUTTON
            // ============================================================
            if (_selectedImage != null && !_uploading)
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.bolt, color: Colors.white),
                  label: const Text(
                    'Upload & Analyze',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5CC),
                    foregroundColor: const Color(0xFF0A1428),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

            if (_selectedImage != null && !_uploading) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.refresh,
                    color: Colors.grey, size: 16),
                label: const Text(
                  'Choose a different image',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACTION BUTTON WIDGET
  // ============================================================
  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFF00E5CC)
              : const Color(0xFF13223A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFF00E5CC)
                : Colors.grey.withOpacity(0.25),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isPrimary ? const Color(0xFF0A1428) : const Color(0xFF00E5CC),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    isPrimary ? const Color(0xFF0A1428) : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
