import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/pending_verification_storage.dart';
import 'package:shipdehop_mobile/core/session_manager.dart';
import 'package:shipdehop_mobile/main.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/main_home_screen.dart';
import 'package:shipdehop_mobile/screens/sign_in_screen.dart';
import 'package:shipdehop_mobile/screens/identity_verification_screen.dart';
import 'package:shipdehop_mobile/widgets/identity_badge.dart';

void main() {
  group('Zero-Cost Identity & Phone Verification Tests', () {
    testWidgets('IdentityBadge renders correct status and colors for verified user', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityBadge(
              status: VerificationBadgeStatus.verified,
              phoneVerified: true,
              governmentIdVerified: true,
              faceVerified: true,
            ),
          ),
        ),
      );

      expect(find.text('ShipdeHop Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);
    });

    testWidgets('IdentityBadge renders correct pending review badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IdentityBadge(
              status: VerificationBadgeStatus.pendingReview,
            ),
          ),
        ),
      );

      expect(find.text('Identity Under Review'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    });

    test('Release entry route uses email SignInScreen instead of unconfigured WhatsApp auth', () {
      const state = AppAuthState(isBootstrapping: false);
      final home = resolveShipdeHopHome(state);
      expect(home, isA<SignInScreen>());
    });

    testWidgets('IdentityVerificationScreen renders truthful Online Aadhaar OTP step', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: IdentityVerificationScreen(phoneE164: '+919876543210'),
          ),
        ),
      );

      expect(find.text('Verify your identity'), findsWidgets);
      expect(find.text('🔒 Privacy & Security Guarantees'), findsOneWidget);
      expect(find.textContaining('I consent to Aadhaar e-KYC verification'), findsOneWidget);
      expect(find.text('Send Aadhaar OTP'), findsOneWidget);
    });

    test('SessionManager holds in-memory access token without storing refresh token in client state', () {
      final container = ProviderContainer();
      final manager = container.read(sessionManagerProvider.notifier);

      expect(container.read(appAuthStateProvider).isAuthenticated, false);

      manager.setSession(
        userId: '88888888-8888-4888-8888-888888888888',
        accessToken: 'mock_es256_access_token_sample',
        phoneE164: '+919876543210',
      );

      final state = container.read(appAuthStateProvider);
      expect(state.isAuthenticated, true);
      expect(state.userId, '88888888-8888-4888-8888-888888888888');
      expect(state.accessToken, 'mock_es256_access_token_sample');
      expect(state.phoneE164, '+919876543210');
      expect(state.isIdentityVerified, false);

      manager.markIdentityVerified();
      expect(container.read(appAuthStateProvider).isIdentityVerified, true);
    });

    test('ApiClient allows unauthenticated phone start call when requireAuth: false', () async {
      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/auth/phone/start')) {
          return http.Response(
            jsonEncode({
              'sessionId': 'test-session-uuid',
              'challenge': 'VERIFY SHIPDEHOP ABC123',
              'whatsappUrl': 'https://wa.me/15550009427?text=VERIFY%20SHIPDEHOP%20ABC123',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mockSupabase = SupabaseClient('https://mock.supabase.co', 'mock_key');

      final client = ApiClient(
        mockSupabase,
        httpClient: mockClient,
        tokenProvider: () => null,
      );

      final result = await client.post(
        '/auth/phone/start',
        {'phoneNumber': '+919876543210', 'countryCode': '+91'},
        requireAuth: false,
      );

      expect(result['sessionId'], 'test-session-uuid');
      expect(result['challenge'], 'VERIFY SHIPDEHOP ABC123');
    });

    test('ApiClient strictly rejects protected route with 401 when unauthenticated and requireAuth: true', () async {
      final mockClient = MockHttpClient((request) async {
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      });

      final mockSupabase = SupabaseClient('https://mock.supabase.co', 'mock_key');

      final client = ApiClient(
        mockSupabase,
        httpClient: mockClient,
        tokenProvider: () => null,
      );

      expect(
        () => client.post('/rides', {'destination': 'Doha'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('PendingVerificationStorage persists only opaque sessionId and clears safely', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await PendingVerificationStorage.savePendingSessionId('sess-12345-opaque-uuid');
      final saved = await PendingVerificationStorage.getPendingSessionId();
      expect(saved, 'sess-12345-opaque-uuid');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('shipdehop_pending_phone_session_id'), true);
      expect(prefs.containsKey('phone'), false);
      expect(prefs.containsKey('challenge'), false);
      expect(prefs.containsKey('jwt'), false);
      expect(prefs.containsKey('refresh_token'), false);

      await PendingVerificationStorage.clearPendingSessionId();
      final cleared = await PendingVerificationStorage.getPendingSessionId();
      expect(cleared, isNull);
    });

    test('SessionManager accurately computes canonical AuthFlowStatus across all lifecycle states', () {
      final container = ProviderContainer();
      final manager = container.read(sessionManagerProvider.notifier);

      manager.signOut();
      var state = container.read(appAuthStateProvider);
      expect(state.flowStatus, AuthFlowStatus.unauthenticated);

      manager.setSession(
        userId: '11111111-1111-4111-a111-111111111111',
        accessToken: 'access_jwt_1',
        phoneE164: '+919876543210',
        identityStatus: 'NOT_STARTED',
      );
      state = container.read(appAuthStateProvider);
      expect(state.flowStatus, AuthFlowStatus.authenticatedIdentityRequired);
      expect(state.isIdentityRequired, true);

      manager.setIdentityStatus('PENDING_REVIEW');
      state = container.read(appAuthStateProvider);
      expect(state.flowStatus, AuthFlowStatus.authenticatedIdentityPending);
      expect(state.isIdentityPending, true);

      manager.markIdentityVerified();
      state = container.read(appAuthStateProvider);
      expect(state.flowStatus, AuthFlowStatus.authenticatedVerified);
      expect(state.isIdentityVerified, true);

      manager.setIdentityStatus('REJECTED');
      state = container.read(appAuthStateProvider);
      expect(state.flowStatus, AuthFlowStatus.authenticatedRestricted);
      expect(state.isRestricted, true);
    });

    test('ShipdeHop routes authenticated unverified users to Home while transaction gates remain server-side', () {
      const state = AppAuthState(
        userId: '22222222-2222-4222-a222-222222222222',
        accessToken: 'access_jwt_2',
        phoneE164: '+919876543210',
        identityStatus: 'NOT_STARTED',
        isBootstrapping: false,
      );

      final home = resolveShipdeHopHome(state);
      expect(home, isA<MainHomeScreen>());
    });

    for (final width in [375.0, 390.0, 430.0]) {
      testWidgets('IdentityVerificationScreen renders without overflow on ${width}px width', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: IdentityVerificationScreen(phoneE164: '+919876543210'),
            ),
          ),
        );

        expect(find.text('Verify your identity'), findsWidgets);
        expect(find.text('Send Aadhaar OTP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request) handler;
  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
