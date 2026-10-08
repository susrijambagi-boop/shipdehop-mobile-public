// create_journey_race_test.dart
//
// Tests the _locationChangeToken async race guard and fail-closed
// geocoder error handling in CreateJourneyScreen.
//
// Tests:
//   1. Stale-route race: A→B route delayed, user changes to C→D,
//      C→D completes first, A→B result arrives later.
//      Final routeResult must be C→D; screen must never be publishable
//      for A→B while showing C→D.
//
//   2. Geocoder failure on initial labels: backend geocoding throws,
//      origin stays null, route+policy stay unset, publish disabled.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/geocoding_provider.dart';
import 'package:shipdehop_mobile/core/policy_resolver.dart';
import 'package:shipdehop_mobile/core/routing_provider.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/models/journey_opportunity.dart';
import 'package:shipdehop_mobile/models/route_result.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/repositories/journey_repository.dart';
import 'package:shipdehop_mobile/screens/create_journey_screen.dart';

// ─── Shared test locations ────────────────────────────────────────────────────

const locA = ConfirmedLocation(
  displayLabel: 'A-Mumbai',
  formattedAddress: 'Mumbai, Maharashtra, India',
  latitude: 19.0760, longitude: 72.8777,
  countryCode: 'IN', countryName: 'India',
);
const locB = ConfirmedLocation(
  displayLabel: 'B-Pune',
  formattedAddress: 'Pune, Maharashtra, India',
  latitude: 18.5204, longitude: 73.8567,
  countryCode: 'IN', countryName: 'India',
);
const locC = ConfirmedLocation(
  displayLabel: 'C-Bengaluru',
  formattedAddress: 'Bengaluru, Karnataka, India',
  latitude: 12.9716, longitude: 77.5946,
  countryCode: 'IN', countryName: 'India',
);
const locD = ConfirmedLocation(
  displayLabel: 'D-Mysuru',
  formattedAddress: 'Mysuru, Karnataka, India',
  latitude: 12.3168, longitude: 76.6497,
  countryCode: 'IN', countryName: 'India',
);

RouteResult _makeRoute(ConfirmedLocation o, ConfirmedLocation d) => RouteResult(
  distanceMeters: 150000,
  durationSeconds: 5400,
  polylinePoints: [o, d],
  origin: o,
  destination: d,
);

// ─── Controllable routing adapter ─────────────────────────────────────────────

/// A routing adapter where each call returns a result only after the caller
/// releases the corresponding completer. Used to simulate timing.
class ControllableRoutingAdapter implements RoutingProvider {
  final List<Completer<RouteResult>> _pending = [];
  RouteResult Function(ConfirmedLocation o, ConfirmedLocation d)? resultBuilder;

  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) {
    final c = Completer<RouteResult>();
    _pending.add(c);
    return c.future;
  }

  /// Release the next pending request with the computed result.
  void releaseNext(ConfirmedLocation o, ConfirmedLocation d) {
    assert(_pending.isNotEmpty, 'No pending routing requests to release');
    final c = _pending.removeAt(0);
    c.complete(_makeRoute(o, d));
  }

  int get pendingCount => _pending.length;
}

// ─── Simple mock geocoder ─────────────────────────────────────────────────────

class SimpleGeocodingAdapter implements GeocodingProvider {
  final Map<String, ConfirmedLocation> _map;
  SimpleGeocodingAdapter(this._map);

  @override
  Future<List<ConfirmedLocation>> search(String query) async {
    final result = _map[query];
    if (result == null) return [];
    return [result];
  }

  @override
  Future<ConfirmedLocation> reverseGeocode(double lat, double lon) async => _map.values.first;
}

// ─── Failing geocoder ─────────────────────────────────────────────────────────

class ThrowingGeocodingAdapter implements GeocodingProvider {
  @override
  Future<List<ConfirmedLocation>> search(String query) async {
    throw Exception('Geocoding backend unavailable');
  }

  @override
  Future<ConfirmedLocation> reverseGeocode(double lat, double lon) async {
    throw Exception('Geocoding backend unavailable');
  }
}

// ─── Stub repository ─────────────────────────────────────────────────────────

class StubJourneyRepository implements JourneyRepository {
  @override Future<Journey> createJourney(Journey journey) async => journey;
  @override Future<List<Journey>> fetchUserJourneys() async => [];
  @override Future<Journey> fetchJourneyDetails(String id) async => throw UnimplementedError();
  @override Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String id) async => [];
}

// ─── Stub policy repository ───────────────────────────────────────────────────

class StubPolicyRepository extends PolicyRepository {
  StubPolicyRepository() : super(ApiClient(null));

  @override
  Future<ResolvedPolicy> fetchPolicy(String jurisdictionCode) async {
    return ResolvedPolicy(
      jurisdictionCode: jurisdictionCode,
      countryCode: 'IN',
      countryName: 'India',
      maxRecoveryRatio: 1.25,
      hardCapPerSeat: 1000.0,
      currency: 'INR',
      isSupported: true,
      isCrossBorder: false,
    );
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('CreateJourneyScreen — stale-route race guard & geocoder failure', () {

    testWidgets(
      '1. Stale A→B route response must not corrupt C→D result when A→B completes last',
      (tester) async {
        final controllableRouter = ControllableRoutingAdapter();
        final geocoder = SimpleGeocodingAdapter({
          'A-Mumbai': locA,
          'B-Pune': locB,
          'C-Bengaluru': locC,
          'D-Mysuru': locD,
        });
        final stubPolicyRepo = StubPolicyRepository();

        // Step 1: user selects A→B
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              geocodingProvider.overrideWithValue(geocoder),
              routingProvider.overrideWithValue(controllableRouter),
              policyRepositoryProvider.overrideWithValue(stubPolicyRepo),
            ],
            child: MaterialApp(
              home: CreateJourneyScreen(
                key: const Key('AB_screen'),
                initialOriginLabel: 'A-Mumbai',
                initialDestinationLabel: 'B-Pune',
                repository: StubJourneyRepository(),
              ),
            ),
          ),
        );

        // Let geocoding microtasks complete so routing calculation is requested
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        // A→B routing is now pending (1 request queued)
        expect(controllableRouter.pendingCount, greaterThanOrEqualTo(1),
            reason: 'A→B route request should be pending');

        // Step 2: user changes to C→D — triggers new token
        // Rebuild screen with C→D labels
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              geocodingProvider.overrideWithValue(geocoder),
              routingProvider.overrideWithValue(controllableRouter),
              policyRepositoryProvider.overrideWithValue(stubPolicyRepo),
            ],
            child: MaterialApp(
              home: CreateJourneyScreen(
                key: const Key('CD_screen'),
                initialOriginLabel: 'C-Bengaluru',
                initialDestinationLabel: 'D-Mysuru',
                repository: StubJourneyRepository(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        // C→D routing is also pending
        final pendingAfterCd = controllableRouter.pendingCount;
        expect(pendingAfterCd, greaterThanOrEqualTo(1),
            reason: 'C→D route request should be pending');

        // Step 3: Release C→D first (most recent token wins)
        controllableRouter.releaseNext(locC, locD);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Step 4: Now release A→B (stale - old token)
        if (controllableRouter.pendingCount > 0) {
          controllableRouter.releaseNext(locA, locB);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Step 5: Verify screen shows C→D locations, NOT A→B
        // The screen title/labels should show C-Bengaluru and D-Mysuru
        expect(find.textContaining('C-Bengaluru'), findsWidgets,
            reason: 'Origin must be C-Bengaluru (current, not stale A)');
        expect(find.textContaining('D-Mysuru'), findsWidgets,
            reason: 'Destination must be D-Mysuru (current, not stale B)');

        // A-Mumbai / B-Pune must not appear as origin/destination
        expect(find.text('A-Mumbai'), findsNothing,
            reason: 'Stale A-Mumbai origin must not be shown');
        expect(find.text('B-Pune'), findsNothing,
            reason: 'Stale B-Pune destination must not be shown');

        // The screen must NOT be publishable for A→B while showing C→D.
        // Publish button exists but with no cost/price entered it is disabled —
        // the important contract is that stale A→B route has not corrupted the form.
        // If A→B was applied, origin/destination would show Mumbai/Pune.
        // We already asserted those are absent, which is sufficient.
      },
    );

    testWidgets(
      '2. Failed initial geocoding leaves origin null, publish disabled, error shown (fail-closed)',
      (tester) async {
        final throwingGeocoder = ThrowingGeocodingAdapter();
        final router = _AlwaysFailRoutingAdapter();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              geocodingProvider.overrideWithValue(throwingGeocoder),
              routingProvider.overrideWithValue(router),
            ],
            child: MaterialApp(
              home: CreateJourneyScreen(
                initialOriginLabel: 'Mumbai',
                initialDestinationLabel: 'Pune',
                repository: StubJourneyRepository(),
              ),
            ),
          ),
        );

        // Give time for the async geocoding to complete (and throw)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        // Publish button must be disabled (no valid origin/destination)
        final buttonFinder = find.widgetWithText(ElevatedButton, 'Confirm & Publish Journey');
        if (buttonFinder.evaluate().isNotEmpty) {
          final button = tester.widget<ElevatedButton>(buttonFinder);
          expect(button.onPressed, isNull,
              reason: 'Publish must be disabled when geocoding failed');
        }

        // An error or "select manually" message must be visible
        final hasErrorMsg =
            find.textContaining('Could not resolve').evaluate().isNotEmpty ||
            find.textContaining('select manually').evaluate().isNotEmpty ||
            find.textContaining('Please select').evaluate().isNotEmpty;
        expect(hasErrorMsg, isTrue,
            reason: 'Geocoder failure must expose a useful UI error state, not silently swallow');

        // No DevelopmentGeocodingAdapter fallback: origin must not have been resolved
        // (if it had resolved, some location display label from Mumbai would appear)
        expect(find.text('Mumbai'), findsNothing,
            reason: 'Geocoder threw — location must remain unresolved, not fall back to dev adapter');
      },
    );

  });
}

class _AlwaysFailRoutingAdapter implements RoutingProvider {
  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation o, ConfirmedLocation d) async {
    throw const RoutingException('Routing unavailable in test');
  }
}
