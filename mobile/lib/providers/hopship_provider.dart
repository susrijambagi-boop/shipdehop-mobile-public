import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/launch_market.dart';
import 'app_providers.dart';

class HopShieldResult {
  const HopShieldResult({
    required this.decision,
    required this.confidence,
    required this.contentMismatch,
    required this.prohibitedCategories,
    required this.rationale,
  });

  final String decision;
  final double confidence;
  final bool contentMismatch;
  final List<String> prohibitedCategories;
  final String rationale;

  factory HopShieldResult.fromJson(Map<String, dynamic> json) {
    return HopShieldResult(
      decision: json['decision']?.toString() ?? 'REVIEW',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      contentMismatch: json['contentMismatch'] as bool? ?? false,
      prohibitedCategories: (json['prohibitedCategories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      rationale: json['rationale']?.toString() ?? 'No rationale provided.',
    );
  }
}

class HopShipState {
  const HopShipState({
    this.isBusy = false,
    this.error,
    this.quote,
    this.createdTask,
    this.inspectionResult,
  });

  final bool isBusy;
  final String? error;
  final Map<String, dynamic>? quote;
  final Map<String, dynamic>? createdTask;
  final HopShieldResult? inspectionResult;

  HopShipState copyWith({
    bool? isBusy,
    String? error,
    Map<String, dynamic>? quote,
    Map<String, dynamic>? createdTask,
    HopShieldResult? inspectionResult,
    bool clearError = false,
  }) {
    return HopShipState(
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : (error ?? this.error),
      quote: quote ?? this.quote,
      createdTask: createdTask ?? this.createdTask,
      inspectionResult: inspectionResult ?? this.inspectionResult,
    );
  }
}

class HopShipNotifier extends Notifier<HopShipState> {
  @override
  HopShipState build() => const HopShipState();

  Future<void> calculateQuote({
    required bool isBuyForMe,
    required double declaredValue,
    required double rewardAmount,
    required String currency,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final result = await ref.read(apiClientProvider).post('/pricing/shipment', {
        'itemType': isBuyForMe ? 'URL_PURCHASE' : 'PARCEL',
        'declaredValue': declaredValue,
        'reward': rewardAmount,
        // Initial production launch is India-only. Do not trust a manually
        // edited client currency field to move a request into another market.
        'currency': LaunchMarket.currency,
      });
      state = state.copyWith(isBusy: false, quote: result);
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createDraftTask({
    required bool isBuyForMe,
    required String? productUrl,
    required double declaredValue,
    required double rewardAmount,
    required String currency,
    required String pickupName,
    required double pickupLat,
    required double pickupLon,
    required String dropName,
    required double dropLat,
    required double dropLon,
    required double weightKg,
  }) async {
    if (!LaunchMarket.containsCoordinates(pickupLat, pickupLon) ||
        !LaunchMarket.containsCoordinates(dropLat, dropLon)) {
      throw StateError(LaunchMarket.unsupportedMessage);
    }

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final result = await ref
          .read(supabaseProvider)
          .rpc<Map<String, dynamic>>('create_shipment_task', params: {
        'p_item_type': isBuyForMe ? 'URL_PURCHASE' : 'PARCEL',
        'p_product_url': isBuyForMe ? productUrl : null,
        'p_declared_value': declaredValue,
        'p_reward_amount': rewardAmount,
        'p_currency': LaunchMarket.currency,
        'p_pickup_name': pickupName,
        'p_pickup_lon': pickupLon,
        'p_pickup_lat': pickupLat,
        'p_drop_name': dropName,
        'p_drop_lon': dropLon,
        'p_drop_lat': dropLat,
        'p_weight_kg': weightKg,
      });

      state = state.copyWith(isBusy: false, createdTask: result);
      return result;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      rethrow;
    }
  }

  Future<HopShieldResult> inspectShipmentParcel({
    required String taskId,
    required List<int> imageBytes,
    required String imageMimeType,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final base64Image = base64Encode(imageBytes);
      final response = await ref
          .read(apiClientProvider)
          .post('/hopshield/shipments/$taskId/inspect', {
        'imageBase64': base64Image,
        'imageMimeType': imageMimeType,
      });

      final shieldJson =
          (response['hopShield'] as Map).cast<String, dynamic>();
      final result = HopShieldResult.fromJson(shieldJson);

      final updatedTask =
          response['shipment'] as Map<String, dynamic>? ?? state.createdTask;

      state = state.copyWith(
        isBusy: false,
        createdTask: updatedTask,
        inspectionResult: result,
      );

      if (result.decision == 'APPROVED') {
        ref.invalidate(shipmentFeedProvider);
      }

      return result;
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      rethrow;
    }
  }

  void reset() {
    state = const HopShipState();
  }
}

final hopShipNotifierProvider =
    NotifierProvider<HopShipNotifier, HopShipState>(HopShipNotifier.new);
