import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../theme/app_theme.dart';
import '../services/gemini_service.dart';

/// Step 6–10 of the AI generate flow.
/// Shows loading → result image → Save / Change Jewelry / Retake Photo.
class GenerateResultScreen extends StatefulWidget {
  final String capturedPhotoPath;
  final JewelryItem selectedItem;

  const GenerateResultScreen({
    super.key,
    required this.capturedPhotoPath,
    required this.selectedItem,
  });

  @override
  State<GenerateResultScreen> createState() => _GenerateResultScreenState();
}

class _GenerateResultScreenState extends State<GenerateResultScreen> {
  _State _state = _State.loading;
  String? _resultImagePath;
  String? _errorMessage;
  bool _saving = false;

  // Key for capturing the result widget as image (for save)
  final _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() { _state = _State.loading; _errorMessage = null; });
    try {
      final resultPath = await GeminiService.generateJewelryImage(
        userPhotoPath: widget.capturedPhotoPath,
        jewelryItem: widget.selectedItem,
      );
      if (mounted) {
        setState(() {
          _resultImagePath = resultPath;
          _state = _State.result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _state = _State.error;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_resultImagePath == null) return;
    setState(() => _saving = true);
    try {
      await Gal.putImage(_resultImagePath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_state) {
        _State.loading => _buildLoading(mq),
        _State.result  => _buildResult(mq),
        _State.error   => _buildError(mq),
      },
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading(MediaQueryData mq) {
    return Stack(
      children: [
        // Blurred user photo as background
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.file(
              File(widget.capturedPhotoPath),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black54),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      color: AppColors.gold, strokeWidth: 3),
                ),
              ),
              const SizedBox(height: 24),
              Text('Generating your look…',
                  style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Placing ${widget.selectedItem.name} on your photo',
                  style: GoogleFonts.dmSans(
                      color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 6),
              Text('This may take a few seconds',
                  style: GoogleFonts.dmSans(
                      color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Result ────────────────────────────────────────────────────────────────

  Widget _buildResult(MediaQueryData mq) {
    return Column(
      children: [
        // Top bar
        Container(
          color: Colors.black,
          padding: EdgeInsets.only(top: mq.padding.top),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text('Generated Look',
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              // Save button in top bar
              TextButton.icon(
                onPressed: _saving ? null : _saveToGallery,
                icon: _saving
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.gold))
                    : const Icon(Icons.download_rounded,
                        color: AppColors.gold, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save',
                    style: GoogleFonts.dmSans(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
        ),

        // Result image
        Expanded(
          child: RepaintBoundary(
            key: _repaintKey,
            child: Image.file(
              File(_resultImagePath!),
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),

        // Action buttons
        Container(
          color: Colors.black,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + mq.padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Jewelry name badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond_outlined,
                        color: AppColors.gold, size: 14),
                    const SizedBox(width: 6),
                    Text(widget.selectedItem.name,
                        style: GoogleFonts.dmSans(
                            color: AppColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Save to Gallery (primary)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveToGallery,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save to Gallery',
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Change Jewelry / Retake Photo (secondary row)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'change'),
                      icon: const Icon(Icons.swap_horiz_rounded,
                          size: 16, color: Colors.white70),
                      label: Text('Change Jewelry',
                          style: GoogleFonts.dmSans(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'retake'),
                      icon: const Icon(Icons.camera_alt_outlined,
                          size: 16, color: Colors.white70),
                      label: Text('Retake Photo',
                          style: GoogleFonts.dmSans(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError(MediaQueryData mq) {
    return SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.error_outline_rounded,
              color: Colors.white38, size: 64),
          const SizedBox(height: 16),
          Text('Generation failed',
              style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_errorMessage ?? 'Something went wrong',
                style: GoogleFonts.dmSans(
                    color: Colors.white54, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Try Again',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

enum _State { loading, result, error }
