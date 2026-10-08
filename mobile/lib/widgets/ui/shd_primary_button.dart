import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ShdPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;
  final Color backgroundColor;
  final Color textColor;
  final double height;

  const ShdPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
    this.backgroundColor = ShipdeHopColors.brandPrimary,
    this.textColor = ShipdeHopColors.textOnPrimary,
    this.height = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    Widget child = SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: ShipdeHopColors.borderLight,
          elevation: 0,
          shadowColor: ShipdeHopColors.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: isDisabled ? ShipdeHopColors.textMuted : textColor),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: ShipdeHopTypography.labelLarge.copyWith(
                        color: isDisabled ? ShipdeHopColors.textMuted : textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );

    if (isFullWidth) {
      child = SizedBox(width: double.infinity, child: child);
    }

    return child.animate(target: isDisabled ? 0 : 1).scaleXY(
          begin: 0.98,
          end: 1.0,
          duration: 150.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
