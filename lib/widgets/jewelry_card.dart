import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/jewelry_item.dart';
import '../theme/app_theme.dart';

class JewelryCard extends StatelessWidget {
  final JewelryItem item;
  final VoidCallback onTap;
  final bool selected;

  const JewelryCard({
    super.key,
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardW =
        (MediaQuery.of(context).size.width * 0.26).clamp(90.0, 120.0);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: cardW,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.goldLight : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.2)
                  : AppColors.shadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // When height is very small (e.g. used in a 56px row), show minimal layout
            final compact = constraints.maxHeight < 80;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image — flexible so it never forces overflow
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        6, 6, 6, compact ? 6 : 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildImage(),
                    ),
                  ),
                ),
                if (!compact) ...[
                  // Name
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: 4, left: 6, right: 6),
                    child: Text(
                      item.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Type badge
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        item.type.name.toUpperCase(),
                        style: GoogleFonts.dmSans(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (item.isAsset) {
      return Image.asset(item.imagePath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _Placeholder());
    }
    final file = File(item.imagePath);
    if (!file.existsSync()) return const _Placeholder();
    return Image.file(file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _Placeholder());
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const Center(
        child:
            Icon(Icons.diamond_outlined, color: AppColors.border, size: 24),
      );
}
