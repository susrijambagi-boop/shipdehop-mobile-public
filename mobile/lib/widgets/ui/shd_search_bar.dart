import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ShdSearchBar extends StatelessWidget {
  final String hintText;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const ShdSearchBar({
    super.key,
    this.hintText = 'Where are you going or sending?',
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.readOnly = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: ShipdeHopColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ShipdeHopColors.borderLight, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: ShipdeHopColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: ShipdeHopColors.brandPrimary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: readOnly
                  ? Text(
                      hintText,
                      style: ShipdeHopTypography.bodyMedium.copyWith(
                        color: ShipdeHopColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : TextField(
                      controller: controller,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: TextInputAction.search,
                      style: ShipdeHopTypography.bodyLarge,
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: ShipdeHopTypography.bodyMedium.copyWith(
                          color: ShipdeHopColors.textMuted,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
