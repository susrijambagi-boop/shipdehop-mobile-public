import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ShdEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? message;
  final String? buttonLabel;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onAction;

  const ShdEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.message,
    this.buttonLabel,
    this.actionLabel,
    this.onPressed,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final displayMessage = subtitle ?? message ?? '';
    final label = buttonLabel ?? actionLabel;
    final callback = onPressed ?? onAction;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: ShipdeHopColors.surfaceSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: ShipdeHopColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: ShipdeHopTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (displayMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayMessage,
              style: ShipdeHopTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          if (label != null && callback != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: callback,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: ShipdeHopColors.brandPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: ShipdeHopColors.brandPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
