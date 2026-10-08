import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';

class RestrictedAccountScreen extends ConsumerWidget {
  const RestrictedAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        title: const Text('Account Status'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.gpp_maybe_rounded,
                    size: 64,
                    color: ShipdeHopColors.error,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Identity Verification Restricted',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your identity verification could not be completed or has been restricted. Please contact ShipdeHop support for assistance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(sessionManagerProvider.notifier).signOut();
                        await ref.read(supabaseProvider).auth.signOut();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign Out'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
