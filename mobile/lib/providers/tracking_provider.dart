import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/domain.dart';
import 'app_providers.dart';

class TrackingState {
  const TrackingState({this.tripId, this.point, this.running = false, this.isDriver = false, this.error});
  final String? tripId;
  final TrackingPoint? point;
  final bool running, isDriver;
  final String? error;
  TrackingState copyWith({String? tripId, TrackingPoint? point, bool? running, bool? isDriver, String? error}) => TrackingState(
    tripId: tripId ?? this.tripId, point: point ?? this.point, running: running ?? this.running, isDriver: isDriver ?? this.isDriver, error: error,
  );
}

class LiveTrackingController extends Notifier<TrackingState> {
  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _channel;
  Timer? _snapshotTimer;
  TrackingPoint? _latest;

  @override TrackingState build() {
    ref.onDispose(() { unawaited(stop()); });
    return const TrackingState();
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0, intervalDuration: const Duration(milliseconds: 500));
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true);
    }
    return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw StateError('Location services are disabled.');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw StateError('Location permission is required.');
  }

  Future<void> startDriver(String tripId) async {
    await stop(); await _ensurePermission();
    final supabase = ref.read(supabaseProvider);
    final channel = supabase.channel('trip:$tripId:tracking', opts: const RealtimeChannelConfig(private: true));
    _channel = channel;
    await _subscribe(channel);
    state = TrackingState(tripId: tripId, running: true, isDriver: true);

    _positionSub = Geolocator.getPositionStream(locationSettings: _settings()).listen((position) async {
      final point = TrackingPoint(lat: position.latitude, lon: position.longitude, recordedAt: position.timestamp, heading: position.heading, speedMps: position.speed < 0 ? null : position.speed);
      _latest = point; state = state.copyWith(point: point, running: true, isDriver: true);
      await channel.sendBroadcastMessage(event: 'position', payload: point.toJson());
    }, onError: (Object e) => state = state.copyWith(error: e.toString(), running: false));

    _snapshotTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final point = _latest; if (point == null) return;
      try { await ref.read(apiClientProvider).post('/trips/$tripId/tracking/snapshot', point.toJson()); } catch (_) { /* live stream continues; next durable snapshot retries */ }
    });
  }

  Future<void> startViewer(String tripId) async {
    await stop();
    final supabase = ref.read(supabaseProvider);
    try {
      final rows = await supabase.rpc<List<dynamic>>('get_trip_tracking_snapshot', params: {'p_trip_id': tripId});
      if (rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        _latest = TrackingPoint(lat: (row['lat'] as num).toDouble(), lon: (row['lon'] as num).toDouble(), recordedAt: DateTime.parse(row['recorded_at'].toString()), heading: (row['heading'] as num?)?.toDouble(), speedMps: (row['speed_mps'] as num?)?.toDouble());
      }
    } catch (_) { /* live channel remains the source of truth */ }
    final channel = supabase.channel('trip:$tripId:tracking', opts: const RealtimeChannelConfig(private: true));
    _channel = channel;
    channel.onBroadcast(event: 'position', callback: (payload) {
      final point = TrackingPoint.fromJson(payload);
      _latest = point; state = state.copyWith(point: point, running: true, isDriver: false);
    });
    await _subscribe(channel);
    state = TrackingState(tripId: tripId, running: true, isDriver: false, point: _latest);
  }

  Future<void> _subscribe(RealtimeChannel channel) async {
    final completer = Completer<void>();
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed && !completer.isCompleted) completer.complete();
      if ((status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) && !completer.isCompleted) {
        completer.completeError(error ?? StateError('Realtime subscription failed'));
      }
    });
    await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> stop() async {
    _snapshotTimer?.cancel(); _snapshotTimer = null;
    await _positionSub?.cancel(); _positionSub = null;
    final channel = _channel; _channel = null;
    if (channel != null) await ref.read(supabaseProvider).removeChannel(channel);
    _latest = null;
    if (state.running) state = const TrackingState();
  }
}

final liveTrackingControllerProvider = NotifierProvider<LiveTrackingController, TrackingState>(LiveTrackingController.new);
