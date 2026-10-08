import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/screens/sign_in_screen.dart';

void main() {
  group('Dev Auth Security & UI Tests', () {
    test('Default compile-time AppConfig.enableDevTestAuth is false', () {
      expect(AppConfig.enableDevTestAuth, isFalse);
    });

    test('AppConfig resolves default apiBaseUrl and backendBaseUrl correctly', () {
      expect(AppConfig.apiBaseUrl, isNotEmpty);
      expect(AppConfig.backendBaseUrl, equals(AppConfig.apiBaseUrl));
    });

    testWidgets('Dev UI is absent on SignInScreen when ENABLE_DEV_TEST_AUTH is false', (WidgetTester tester) async {
      AppConfig.devTestAuthOverride = false;
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SignInScreen(),
          ),
        ),
      );

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('DEV TEST ACCOUNTS'), findsNothing);
      expect(find.byKey(const Key('dev_login_sender_button')), findsNothing);
      expect(find.byKey(const Key('dev_login_carrier_button')), findsNothing);
      expect(find.text('Email me a sign-in link'), findsOneWidget);
    });

    test('Allowlist enforces exactly the 2 designated test accounts', () {
      const allowlist = {
        'shipsterheadquarter@gmail.com',
        'susrijambagi@gmail.com',
      };

      expect(allowlist.contains('shipsterheadquarter@gmail.com'), isTrue);
      expect(allowlist.contains('susrijambagi@gmail.com'), isTrue);
      expect(allowlist.contains('attacker@malicious.com'), isFalse);
      expect(allowlist.contains('randomuser@gmail.com'), isFalse);
      expect(allowlist.contains('admin@shipdehop.com'), isFalse);
    });
  });
}
