import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'core/session_manager.dart';
import 'providers/app_providers.dart';
import 'screens/app_bootstrapping_screen.dart';
import 'screens/main_home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/restricted_account_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme/shipdehop_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
    if (AppConfig.stripePublishableKey.isNotEmpty) {
      Stripe.publishableKey = AppConfig.stripePublishableKey;
      await Stripe.instance.applySettings();
    }
  }
  runApp(const ProviderScope(child: ShipdeHopApp()));
}

/// Resolves the top-level authenticated experience without mounting feature
/// screens. Keeping this decision pure makes the progressive-verification
/// policy easy to test without starting timers/subscriptions owned by Home.
Widget resolveShipdeHopHome(AppAuthState authState) {
  if (const bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false)) {
    return const MainHomeScreen();
  }
  switch (authState.flowStatus) {
    case AuthFlowStatus.loading:
      return const AppBootstrappingScreen();
    case AuthFlowStatus.unauthenticated:
      // The release entry point is email magic-link auth. The older WhatsApp
      // verification screen remains dormant until its Meta webhook is configured.
      return const SignInScreen();
    case AuthFlowStatus.authenticatedIdentityRequired:
    case AuthFlowStatus.authenticatedIdentityPending:
    case AuthFlowStatus.authenticatedVerified:
      // Progressive verification: authenticated users can browse the app even
      // when production Aadhaar verification is temporarily unavailable.
      // Sensitive transactions remain protected by backend identity gates.
      return const MainHomeScreen();
    case AuthFlowStatus.authenticatedRestricted:
      return const RestrictedAccountScreen();
  }
}

class ShipdeHopApp extends ConsumerWidget {
  final bool showOnboarding;

  const ShipdeHopApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) {
      AppConfig.devTestAuthOverride = true;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ShipdeHop',
        theme: ShipdeHopTheme.lightTheme,
        home: const UnconfiguredAppScreen(),
      );
    }

    if (showOnboarding) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ShipdeHop',
        theme: ShipdeHopTheme.lightTheme,
        home: const OnboardingScreen(),
      );
    }

    final authState = ref.watch(appAuthStateProvider);
    final homeWidget = resolveShipdeHopHome(authState);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShipdeHop',
      theme: ShipdeHopTheme.lightTheme,
      home: homeWidget,
    );
  }
}

class UnconfiguredAppScreen extends StatelessWidget {
  const UnconfiguredAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.amber),
                const SizedBox(height: 16),
                Text(
                  'ShipdeHop Environment Setup Required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please pass SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY using --dart-define parameters when launching the app:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SelectableText(
                    'flutter run \\\n'
                    '  --dart-define=SUPABASE_URL=http://localhost:54321 \\\n'
                    '  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
