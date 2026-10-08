import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shipdehop_mobile/core/profile_preferences.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('saved places persist and remain scoped to the signed-in user', () async {
    const place = SavedPlaceRecord(
      id: 'home-1',
      label: 'Home',
      location: ConfirmedLocation(
        displayLabel: 'Home',
        formattedAddress: '12 Test Street',
        latitude: 12.34,
        longitude: 56.78,
        countryCode: 'IN',
      ),
    );

    const userA = ProfilePreferencesStore('user-a');
    const userB = ProfilePreferencesStore('user-b');

    await userA.saveSavedPlaces(const [place]);

    final loadedA = await userA.loadSavedPlaces();
    final loadedB = await userB.loadSavedPlaces();

    expect(loadedA, hasLength(1));
    expect(loadedA.single.label, 'Home');
    expect(loadedA.single.location.formattedAddress, '12 Test Street');
    expect(loadedB, isEmpty);
  });

  test('travel, account and safety preferences round-trip', () async {
    const store = ProfilePreferencesStore('user-a');

    await store.saveTravelPreferences(const TravelPreferences(
      preferredMode: 'TRAIN',
      parcelCapacity: 'LUGGAGE',
      maxDetourKm: 9,
      ladiesOnly: true,
      verifiedOnly: true,
      matchAlerts: false,
    ));
    await store.saveAccountPreferences(const AccountPreferences(
      journeyUpdates: false,
      messageAlerts: true,
      paymentAlerts: false,
    ));
    await store.saveSafetyPreferences(const SafetyPreferences(
      emergencyName: 'Asha',
      emergencyPhone: '+911234567890',
      shareLiveLocation: true,
      safetyCheckIns: false,
    ));

    final travel = await store.loadTravelPreferences();
    final account = await store.loadAccountPreferences();
    final safety = await store.loadSafetyPreferences();

    expect(travel.preferredMode, 'TRAIN');
    expect(travel.parcelCapacity, 'LUGGAGE');
    expect(travel.maxDetourKm, 9);
    expect(travel.ladiesOnly, isTrue);
    expect(travel.matchAlerts, isFalse);
    expect(account.journeyUpdates, isFalse);
    expect(account.messageAlerts, isTrue);
    expect(account.paymentAlerts, isFalse);
    expect(safety.emergencyName, 'Asha');
    expect(safety.safetyCheckIns, isFalse);
  });

  test('clearLocalProfileData removes only the current users profile preferences', () async {
    const userA = ProfilePreferencesStore('user-a');
    const userB = ProfilePreferencesStore('user-b');

    await userA.saveTravelPreferences(const TravelPreferences(preferredMode: 'FLIGHT'));
    await userB.saveTravelPreferences(const TravelPreferences(preferredMode: 'BUS'));

    await userA.clearLocalProfileData();

    expect((await userA.loadTravelPreferences()).preferredMode, 'CAR');
    expect((await userB.loadTravelPreferences()).preferredMode, 'BUS');
  });
}
