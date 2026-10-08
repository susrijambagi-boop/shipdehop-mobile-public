import 'package:supabase_flutter/supabase_flutter.dart';

import 'launch_market.dart';
import 'profile_preferences.dart';

class LocationFavorites {
  const LocationFavorites._();

  static Future<List<SavedPlaceRecord>> load() async {
    var userId = 'anonymous';
    try {
      userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    } catch (_) {
      // Widget/unit tests may not initialize Supabase. Anonymous local storage
      // keeps the location picker independently testable.
    }

    final places = await ProfilePreferencesStore(userId).loadSavedPlaces();
    return places
        .where((place) => LaunchMarket.isSupportedLocation(place.location))
        .toList();
  }
}