import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';

class ShdStatusBadge extends StatelessWidget {
  final String status;
  final bool compact;

  const ShdStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cleanStatus = status.trim().toUpperCase();

    Color bgColor = ShipdeHopColors.surfaceSubtle;
    Color textColor = ShipdeHopColors.textSecondary;
    String label = status;

    if (cleanStatus.contains('LOCKED') || cleanStatus.contains('PAYMENT SECURED') || cleanStatus.contains('SECURED')) {
      bgColor = ShipdeHopColors.infoBg;
      textColor = ShipdeHopColors.info;
      label = compact ? 'Payment Secured' : 'Payment Secured • Awaiting pickup';
    } else if (cleanStatus.contains('TRANSIT') || cleanStatus.contains('IN_TRANSIT')) {
      bgColor = ShipdeHopColors.warningBg;
      textColor = ShipdeHopColors.warning;
      label = 'In transit';
    } else if (cleanStatus.contains('RELEASED') || cleanStatus.contains('COMPLETED') || cleanStatus.contains('DELIVERED') || cleanStatus.contains('VERIFIED')) {
      bgColor = ShipdeHopColors.successBg;
      textColor = ShipdeHopColors.success;
      label = 'Completed';
    } else if (cleanStatus.contains('CANCEL') || cleanStatus.contains('CANCELLED') || cleanStatus.contains('REFUND')) {
      bgColor = ShipdeHopColors.errorBg;
      textColor = ShipdeHopColors.error;
      label = 'Cancelled';
    } else if (cleanStatus.contains('CREATED') || cleanStatus.contains('PENDING') || cleanStatus.contains('OPEN') || cleanStatus.contains('LISTED')) {
      bgColor = ShipdeHopColors.brandPrimaryLight;
      textColor = ShipdeHopColors.brandPrimary;
      label = cleanStatus.contains('LISTED') ? 'Listed' : 'Active';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
