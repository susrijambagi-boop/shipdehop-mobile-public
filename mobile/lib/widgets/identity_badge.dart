import 'package:flutter/material.dart';

enum VerificationBadgeStatus {
  verified,
  verifiedTest,
  pendingReview,
  inProgress,
  notStarted,
}

class IdentityBadge extends StatelessWidget {
  final VerificationBadgeStatus status;
  final bool phoneVerified;
  final bool governmentIdVerified;
  final bool faceVerified;
  final bool isAadhaarVerified;
  final VoidCallback? onTap;

  const IdentityBadge({
    super.key,
    required this.status,
    this.phoneVerified = false,
    this.governmentIdVerified = false,
    this.faceVerified = false,
    this.isAadhaarVerified = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case VerificationBadgeStatus.verified:
        bg = const Color(0xFFE6F4EA);
        fg = const Color(0xFF137333);
        icon = Icons.verified_user_rounded;
        label = isAadhaarVerified ? 'Aadhaar Verified' : 'ShipdeHop Verified';
        break;
      case VerificationBadgeStatus.verifiedTest:
        bg = const Color(0xFFE8F0FE);
        fg = const Color(0xFF1A73E8);
        icon = Icons.science_rounded;
        label = 'UIDAI e-KYC Test Passed';
        break;
      case VerificationBadgeStatus.pendingReview:
        bg = const Color(0xFFFEF7E0);
        fg = const Color(0xFFB06000);
        icon = Icons.hourglass_top_rounded;
        label = 'Identity Under Review';
        break;
      case VerificationBadgeStatus.inProgress:
        bg = const Color(0xFFE8F0FE);
        fg = const Color(0xFF1A73E8);
        icon = Icons.pending_actions_rounded;
        label = 'Verification In Progress';
        break;
      case VerificationBadgeStatus.notStarted:
        bg = const Color(0xFFF1F3F4);
        fg = const Color(0xFF5F6368);
        icon = Icons.shield_outlined;
        label = 'Get Verified';
        break;
    }


    return InkWell(
      onTap: onTap ?? () => _showDetailsSheet(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    status == VerificationBadgeStatus.verified
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: status == VerificationBadgeStatus.verified
                        ? const Color(0xFF137333)
                        : const Color(0xFF1A73E8),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    status == VerificationBadgeStatus.verified
                        ? 'ShipdeHop Verified Member'
                        : 'Trust & Verification',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'ShipdeHop uses identity verification to help build trust between people sending, carrying, and receiving parcels.',
                style: TextStyle(fontSize: 13, color: Color(0xFF5F6368)),
              ),
              const Divider(height: 32),
              _buildCheckItem(
                'Phone Ownership Verified',
                'WhatsApp verification completed',
                phoneVerified,
              ),
              const SizedBox(height: 14),
              _buildCheckItem(
                'Identity Verification',
                status == VerificationBadgeStatus.verified
                    ? 'Approved by ShipdeHop'
                    : 'Manual beta review',
                status == VerificationBadgeStatus.verified,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckItem(String title, String subtitle, bool isDone) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: isDone ? const Color(0xFF137333) : const Color(0xFF9AA0A6),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDone ? const Color(0xFF202124) : const Color(0xFF70757A),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF70757A)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
