import 'package:shared_preferences/shared_preferences.dart';

/// Opaque pre-auth phone verification session persistence.
/// Persists ONLY the random opaque sessionId string across browser refreshes.
/// Does NOT persist phone numbers, challenge codes, challenge hashes, JWTs, or refresh tokens.
class PendingVerificationStorage {
  static const String _keySessionId = 'shipdehop_pending_phone_session_id';

  static Future<void> savePendingSessionId(String sessionId) async {
    if (sessionId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySessionId, sessionId);
  }

  static Future<String?> getPendingSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySessionId);
  }

  static Future<void> clearPendingSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySessionId);
  }
}
