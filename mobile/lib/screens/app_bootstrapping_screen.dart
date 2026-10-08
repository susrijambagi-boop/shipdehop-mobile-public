import 'package:flutter/material.dart';
import '../theme/shipdehop_colors.dart';

class AppBootstrappingScreen extends StatelessWidget {
  const AppBootstrappingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: ShipdeHopColors.brandPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.shield_rounded,
                  size: 36,
                  color: ShipdeHopColors.brandPrimary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
                children: [
                  TextSpan(text: 'Shipde', style: TextStyle(color: ShipdeHopColors.textPrimary)),
                  TextSpan(text: 'Hop', style: TextStyle(color: ShipdeHopColors.squirrelOrange)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ShipdeHopColors.brandPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
