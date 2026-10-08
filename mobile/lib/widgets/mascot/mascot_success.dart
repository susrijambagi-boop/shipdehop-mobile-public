import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'shipdehop_mascot.dart';
import 'mascot_pose.dart';
import 'mascot_motion.dart';

/// One-shot celebration modal / dialog widget for order confirmation & completion.
class MascotSuccessModal extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? secondaryDetail;
  final String buttonLabel;
  final VoidCallback onDismiss;
  final Widget? contentExtra;

  const MascotSuccessModal({
    super.key,
    required this.title,
    required this.subtitle,
    this.secondaryDetail,
    this.buttonLabel = 'Got it!',
    required this.onDismiss,
    this.contentExtra,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? secondaryDetail,
    String buttonLabel = 'Continue',
    Widget? contentExtra,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: MascotSuccessModal(
          title: title,
          subtitle: subtitle,
          secondaryDetail: secondaryDetail,
          buttonLabel: buttonLabel,
          onDismiss: () => Navigator.of(context).pop(),
          contentExtra: contentExtra,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Confetti / sparkle ring accent
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF97316).withValues(alpha: 0.08),
                ),
              ).animate()
                  .scale(begin: const Offset(0.4, 0.4), end: const Offset(1.1, 1.1), duration: 700.ms, curve: Curves.easeOutBack)
                  .fadeIn(duration: 400.ms),
              const ShipdeHopMascot(
                pose: MascotPose.celebrate,
                motion: MascotMotion.celebrateOnce,
                size: 130,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B4B),
            ),
          ).animate().fadeIn(delay: 200.ms).moveY(begin: 10, end: 0, duration: 400.ms),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ).animate().fadeIn(delay: 350.ms),
          if (secondaryDetail != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF312E81)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      secondaryDetail!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF312E81),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 450.ms),
          ],
          if (contentExtra != null) ...[
            const SizedBox(height: 16),
            contentExtra!,
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDismiss,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF312E81),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
