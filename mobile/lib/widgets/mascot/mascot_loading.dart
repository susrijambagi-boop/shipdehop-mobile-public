import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'shipdehop_mascot.dart';
import 'mascot_pose.dart';
import 'mascot_motion.dart';

/// Contextual signature loading screen & card widget featuring the mascot.
class MascotLoadingOverlay extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isFullScreen;

  const MascotLoadingOverlay({
    super.key,
    this.title = 'Getting your hops ready…',
    this.subtitle,
    this.isFullScreen = true,
  });

  factory MascotLoadingOverlay.carpool() {
    return const MascotLoadingOverlay(
      title: 'Finding people going your way…',
      subtitle: 'Matching verified drivers on your corridor',
    );
  }

  factory MascotLoadingOverlay.parcelpool() {
    return const MascotLoadingOverlay(
      title: 'Looking for travellers on your route…',
      subtitle: 'Verifying HopShield inspect parameters',
    );
  }

  factory MascotLoadingOverlay.marketplace() {
    return const MascotLoadingOverlay(
      title: 'Finding the best way to get it there…',
      subtitle: 'Connecting P2P sellers & carriers',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Animated route line draw effect
                Container(
                  width: 180,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ).animate(onPlay: (c) => Animate.defaultDuration == Duration.zero ? null : c.repeat(reverse: true))
                      .slideX(begin: -0.3, end: 0.3, duration: 1500.ms, curve: Curves.easeInOut),
                ),
                const ShipdeHopMascot(
                  pose: MascotPose.run,
                  motion: MascotMotion.runMatching,
                  size: 110,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPulseDot(0),
                const SizedBox(width: 6),
                _buildPulseDot(250),
                const SizedBox(width: 6),
                _buildPulseDot(500),
              ],
            ),
          ],
        ),
      ),
    );

    if (isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: bodyContent),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: bodyContent,
    );
  }

  Widget _buildPulseDot(int delayMs) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF312E81),
        shape: BoxShape.circle,
      ),
    ).animate(onPlay: (c) => Animate.defaultDuration == Duration.zero ? null : c.repeat(reverse: true))
        .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.2, 1.2), delay: delayMs.ms, duration: 600.ms);
  }
}
