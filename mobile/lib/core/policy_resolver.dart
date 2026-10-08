import 'package:flutter/foundation.dart';
import '../models/confirmed_location.dart';

@immutable
class ResolvedPolicy {
  const ResolvedPolicy({
    required this.countryName,
    required this.countryCode,
    required this.currency,
    required this.jurisdictionCode,
    required this.isSupported,
    required this.isCrossBorder,
    this.maxRecoveryRatio,
    this.hardCapPerSeat,
    this.policyName,
    this.unsupportedReason,
  });

  final String countryName;
  final String countryCode;
  final String currency;
  final String jurisdictionCode;
  final bool isSupported;
  final bool isCrossBorder;
  final double? maxRecoveryRatio;
  final double? hardCapPerSeat;
  final String? policyName;
  final String? unsupportedReason;

  String get formattedSummary {
    if (!isSupported) {
      return unsupportedReason ?? 'Currently available in India.';
    }
    return '$countryName • $currency • ${policyName ?? jurisdictionCode}';
  }
}

class PolicyRepository {
  final dynamic apiClient;
  const PolicyRepository(this.apiClient);

  Future<ResolvedPolicy> fetchPolicy(String jurisdictionCode) async {
    if (apiClient == null) {
      throw Exception('ApiClient unavailable for fetching policy.');
    }
    final res = await apiClient.get('/policies/$jurisdictionCode', requireAuth: false);
    return ResolvedPolicy(
      countryName: res['jurisdictionCode'] == 'IN' ? 'India' : res['jurisdictionCode']?.toString() ?? 'India',
      countryCode: res['jurisdictionCode']?.toString() ?? 'IN',
      currency: res['currency']?.toString() ?? 'INR',
      jurisdictionCode: res['jurisdictionCode']?.toString() ?? 'IN',
      isSupported: res['enabled'] == true,
      isCrossBorder: false,
      maxRecoveryRatio: (res['maxRecoveryRatio'] as num?)?.toDouble(),
      hardCapPerSeat: (res['hardCapPerSeat'] as num?)?.toDouble(),
      policyName: res['policyName']?.toString(),
    );
  }
}

class PolicyResolver {
  static ResolvedPolicy resolvePolicy(
    ConfirmedLocation origin,
    ConfirmedLocation destination,
  ) {
    final oCountryCode = _normalizeCountryCode(origin.countryCode);
    final dCountryCode = _normalizeCountryCode(destination.countryCode);

    // Cross-border detection
    if (oCountryCode != dCountryCode || oCountryCode != 'IN' || dCountryCode != 'IN') {
      final isCross = oCountryCode != dCountryCode;
      return ResolvedPolicy(
        countryName: isCross
            ? '${origin.countryName ?? 'Origin'} → ${destination.countryName ?? 'Destination'}'
            : (origin.countryName ?? 'Outside India'),
        countryCode: isCross ? '$oCountryCode-$dCountryCode' : oCountryCode,
        currency: 'INR',
        jurisdictionCode: 'OUTSIDE_INDIA',
        isSupported: false,
        isCrossBorder: isCross,
        unsupportedReason: 'Currently available in India.',
      );
    }

    if (_testFixturePolicies != null && _testFixturePolicies!.containsKey('IN')) {
      return _testFixturePolicies!['IN']!;
    }

    return const ResolvedPolicy(
      countryName: 'India',
      countryCode: 'IN',
      currency: 'INR',
      jurisdictionCode: 'IN',
      isSupported: true,
      isCrossBorder: false,
    );
  }

  static Map<String, ResolvedPolicy>? _testFixturePolicies;

  static void setTestFixturePolicy(String jurisdictionCode, ResolvedPolicy policy) {
    _testFixturePolicies ??= {};
    _testFixturePolicies![jurisdictionCode] = policy;
  }

  static void clearTestFixturePolicies() {
    _testFixturePolicies = null;
  }

  static String _normalizeCountryCode(String? code) {
    if (code == null || code.trim().isEmpty) return 'UNKNOWN';
    final upper = code.trim().toUpperCase();
    if (upper == 'IND' || upper == 'INDIA') return 'IN';
    return upper;
  }
}
