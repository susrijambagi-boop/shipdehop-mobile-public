import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_config.dart';
import '../models/domain.dart';
import '../providers/app_providers.dart';
import '../providers/tracking_provider.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/directions_chooser_sheet.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/mascot/mascot_loading.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String tripId;
  final bool driverMode;
  final bool isParcel;

  const LiveTrackingScreen({
    super.key,
    required this.tripId,
    required this.driverMode,
    this.isParcel = true,
  });

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  Future<void> _start() async {
    if (!AppConfig.isConfigured) return;
    try {
      if (widget.driverMode) {
        await ref.read(supabaseProvider).from('trip_routes').update({'status': 'IN_PROGRESS'}).eq('id', widget.tripId);
        await ref.read(liveTrackingControllerProvider.notifier).startDriver(widget.tripId);
      } else {
        await ref.read(liveTrackingControllerProvider.notifier).startViewer(widget.tripId);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    Future.microtask(() => ref.read(liveTrackingControllerProvider.notifier).stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveTrackingControllerProvider);
    final point = state.point;

    if (point == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.isParcel ? 'HopShip Tracking' : 'HopRide Tracking'),
          backgroundColor: ShipdeHopColors.brandDark,
          foregroundColor: Colors.white,
        ),
        body: const MascotLoadingOverlay(
          title: 'Connecting to HopTrack live stream…',
          subtitle: 'Acquiring satellite GPS route coordinates',
        ),
      );
    }

    final now = DateTime.now();
    final ageSeconds = now.difference(point.recordedAt.toLocal()).inSeconds;
    final isStale = ageSeconds > 120;

    final currentPos = ll.LatLng(point.lat, point.lon);
    final zones = ref.watch(safeZonesProvider(point)).value ?? const <SafeZoneModel>[];

    final markers = <Marker>[
      Marker(
        point: currentPos,
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: isStale ? ShipdeHopColors.warning : ShipdeHopColors.brandPrimary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Icon(
            widget.driverMode
                ? Icons.navigation_rounded
                : (widget.isParcel ? Icons.local_shipping_rounded : Icons.directions_car_rounded),
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
      for (final z in zones)
        Marker(
          point: ll.LatLng(z.lat, z.lon),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: ShipdeHopColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        title: Text(
          widget.driverMode ? 'HopTrack · Sharing Location' : 'HopTrack · Live Journey',
          style: ShipdeHopTypography.titleSmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: ShipdeHopColors.brandDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.near_me_rounded, color: Colors.white),
            tooltip: 'Directions',
            onPressed: () {
              DirectionsChooserSheet.show(
                context,
                destinationName: 'Active Route Destination',
                latitude: point.lat,
                longitude: point.lon,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap dominating screen height
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentPos,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.shipdehop.mobile',
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // Stale / Weak GPS Alert Banner
          if (isStale)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ShipdeHopColors.warningBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ShipdeHopColors.warning),
                  boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.signal_cellular_connected_no_internet_0_bar_rounded, color: ShipdeHopColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location update delayed',
                            style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 12, fontWeight: FontWeight.bold, color: ShipdeHopColors.warning),
                          ),
                          Text(
                            'Last updated ${ageSeconds ~/ 60}m ago · Payment remains protected in HopPay',
                            style: ShipdeHopTypography.bodySmall.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: ShipdeHopColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    ShipdeHopMascot(
                      pose: widget.isParcel ? MascotPose.carryParcel : MascotPose.ride,
                      motion: MascotMotion.routeGlide,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.driverMode ? 'Sharing Live Route' : 'Carrier in Transit',
                            style: ShipdeHopTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(point.speedMps ?? 0).toStringAsFixed(1)} m/s · Live GPS',
                            style: ShipdeHopTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ShipdeHopColors.successBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.sensors_rounded, size: 14, color: ShipdeHopColors.success),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ShipdeHopColors.success)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: ShipdeHopColors.surfaceCard,
            boxShadow: [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, -2))],
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: ShipdeHopColors.brandPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${zones.length} Verified Safe Meetup Zones along this corridor',
                  style: ShipdeHopTypography.bodySmall.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

