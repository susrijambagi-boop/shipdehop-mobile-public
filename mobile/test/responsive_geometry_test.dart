import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shipdehop_mobile/screens/carpool_screen.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/hop_club_screen.dart';
import 'package:shipdehop_mobile/screens/hop_passport_screen.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';
import 'package:shipdehop_mobile/screens/onboarding_screen.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/widgets/global_header.dart';

import 'package:flutter_animate/flutter_animate.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });

  const viewports = [
    Size(360, 800), // Compact mobile (360dp)
    Size(390, 844), // Standard iPhone (390dp)
    Size(430, 932), // Large Pro Max (430dp)
  ];

  group('Responsive Geometry Verification — Zero Overflow across Viewports', () {
    for (final size in viewports) {
      testWidgets('ExploreScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                appBar: GlobalHeader(onSelectTab: (_) {}),
                body: ExploreScreen(onSelectTab: (idx, {destination, modeIndex, origin}) {}),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ParcelPoolScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ParcelPoolScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('CarPoolScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: CarPoolScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('MarketplaceScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: MarketplaceScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ProfileScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: ProfileScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('HopClubScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: HopClubScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('HopPassportScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: HopPassportScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });

      testWidgets('OnboardingScreen renders cleanly at ${size.width}x${size.height} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: OnboardingScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
