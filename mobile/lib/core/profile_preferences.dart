import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/confirmed_location.dart';

class SavedPlaceRecord {
  const SavedPlaceRecord({
    required this.id,
    required this.label,
    required this.location,
  });

  final String id;
  final String label;
  final ConfirmedLocation location;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'location': location.toJson(),
      };

  factory SavedPlaceRecord.fromJson(Map<String, dynamic> json) {
    return SavedPlaceRecord(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Saved place',
      location: ConfirmedLocation.fromJson(
        (json['location'] as Map).cast<String, dynamic>(),
      ),
    );
  }
}

class TravelPreferences {
  const TravelPreferences({
    this.preferredMode = 'CAR',
    this.parcelCapacity = 'MEDIUM',
    this.maxDetourKm = 5,
    this.ladiesOnly = false,
    this.verifiedOnly = true,
    this.matchAlerts = true,
  });

  final String preferredMode;
  final String parcelCapacity;
  final double maxDetourKm;
  final bool ladiesOnly;
  final bool verifiedOnly;
  final bool matchAlerts;

  Map<String, dynamic> toJson() => {
        'preferredMode': preferredMode,
        'parcelCapacity': parcelCapacity,
        'maxDetourKm': maxDetourKm,
        'ladiesOnly': ladiesOnly,
        'verifiedOnly': verifiedOnly,
        'matchAlerts': matchAlerts,
      };

  factory TravelPreferences.fromJson(Map<String, dynamic> json) {
    return TravelPreferences(
      preferredMode: json['preferredMode']?.toString() ?? 'CAR',
      parcelCapacity: json['parcelCapacity']?.toString() ?? 'MEDIUM',
      maxDetourKm: (json['maxDetourKm'] as num?)?.toDouble() ?? 5,
      ladiesOnly: json['ladiesOnly'] == true,
      verifiedOnly: json['verifiedOnly'] != false,
      matchAlerts: json['matchAlerts'] != false,
    );
  }
}

class AccountPreferences {
  const AccountPreferences({
    this.journeyUpdates = true,
    this.messageAlerts = true,
    this.paymentAlerts = true,
  });

  final bool journeyUpdates;
  final bool messageAlerts;
  final bool paymentAlerts;

  Map<String, dynamic> toJson() => {
        'journeyUpdates': journeyUpdates,
        'messageAlerts': messageAlerts,
        'paymentAlerts': paymentAlerts,
      };

  factory AccountPreferences.fromJson(Map<String, dynamic> json) {
    return AccountPreferences(
      journeyUpdates: json['journeyUpdates'] != false,
      messageAlerts: json['messageAlerts'] != false,
      paymentAlerts: json['paymentAlerts'] != false,
    );
  }
}

class SafetyPreferences {
  const SafetyPreferences({
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.shareLiveLocation = true,
    this.safetyCheckIns = true,
  });

  final String emergencyName;
  final String emergencyPhone;
  final bool shareLiveLocation;
  final bool safetyCheckIns;

  Map<String, dynamic> toJson() => {
        'emergencyName': emergencyName,
        'emergencyPhone': emergencyPhone,
        'shareLiveLocation': shareLiveLocation,
        'safetyCheckIns': safetyCheckIns,
      };

  factory SafetyPreferences.fromJson(Map<String, dynamic> json) {
    return SafetyPreferences(
      emergencyName: json['emergencyName']?.toString() ?? '',
      emergencyPhone: json['emergencyPhone']?.toString() ?? '',
      shareLiveLocation: json['shareLiveLocation'] != false,
      safetyCheckIns: json['safetyCheckIns'] != false,
    );
  }
}

class ProfilePreferencesStore {
  const ProfilePreferencesStore(this.userId);

  final String userId;

  String _key(String suffix) => 'shipdehop.profile.$userId.$suffix';

  Future<List<SavedPlaceRecord>> loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key('saved_places'));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => SavedPlaceRecord.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSavedPlaces(List<SavedPlaceRecord> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key('saved_places'),
      jsonEncode(places.map((item) => item.toJson()).toList()),
    );
  }

  Future<TravelPreferences> loadTravelPreferences() async {
    final map = await _loadMap('travel_preferences');
    return map == null ? const TravelPreferences() : TravelPreferences.fromJson(map);
  }

  Future<void> saveTravelPreferences(TravelPreferences value) =>
      _saveMap('travel_preferences', value.toJson());

  Future<AccountPreferences> loadAccountPreferences() async {
    final map = await _loadMap('account_preferences');
    return map == null ? const AccountPreferences() : AccountPreferences.fromJson(map);
  }

  Future<void> saveAccountPreferences(AccountPreferences value) =>
      _saveMap('account_preferences', value.toJson());

  Future<SafetyPreferences> loadSafetyPreferences() async {
    final map = await _loadMap('safety_preferences');
    return map == null ? const SafetyPreferences() : SafetyPreferences.fromJson(map);
  }

  Future<void> saveSafetyPreferences(SafetyPreferences value) =>
      _saveMap('safety_preferences', value.toJson());

  Future<void> clearLocalProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_key('saved_places')),
      prefs.remove(_key('travel_preferences')),
      prefs.remove(_key('account_preferences')),
      prefs.remove(_key('safety_preferences')),
    ]);
  }

  Future<Map<String, dynamic>?> _loadMap(String suffix) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(suffix));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMap(String suffix, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(suffix), jsonEncode(value));
  }
}
