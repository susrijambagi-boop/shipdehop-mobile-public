import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/external_directions_launcher.dart';
import '../core/routing_provider.dart';
import '../models/confirmed_location.dart';
import '../models/route_result.dart';

class RoutePreviewWidget extends StatefulWidget {
  const RoutePreviewWidget({
    super.key,
    required this.origin,
    required this.destination,
    this.routingProvider = const BackendRoutingAdapter(),
    required this.onRouteConfirmed,
    required this.onEditOrigin,
    required this.onEditDestination,
  });

  final ConfirmedLocation origin;
  final ConfirmedLocation destination;
  final RoutingProvider routingProvider;
  final void Function(RouteResult route) onRouteConfirmed;
  final VoidCallback onEditOrigin;
  final VoidCallback onEditDestination;

  @override
  State<RoutePreviewWidget> createState() => _RoutePreviewWidgetState();
}

class _RoutePreviewWidgetState extends State<RoutePreviewWidget> {
  late Future<RouteResult> _routeFuture;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  @override
  void didUpdateWidget(covariant RoutePreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin != widget.origin || oldWidget.destination != widget.destination) {
      _fetchRoute();
    }
  }

  void _fetchRoute() {
    setState(() {
      _routeFuture = widget.routingProvider.calculateRoute(widget.origin, widget.destination);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RouteResult>(
      future: _routeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Calculating road route...', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            elevation: 1,
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_outlined, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text(
                    "We couldn't calculate the road route right now.",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Check your network connection or edit locations.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _fetchRoute,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: widget.onEditOrigin,
                        icon: const Icon(Icons.edit_location),
                        label: const Text('Edit Locations'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final route = snapshot.data!;
        final isApproximate = route.provider == 'development_approximation';
        final polylineLatLngs = route.polylinePoints
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        final centerLat = (widget.origin.latitude + widget.destination.latitude) / 2.0;
        final centerLng = (widget.origin.longitude + widget.destination.longitude) / 2.0;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Title & Actions
                Row(
                  children: [
                    const Icon(Icons.alt_route, color: Colors.indigo),
                    const SizedBox(width: 8),
                    const Text(
                      'Journey Route Preview',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.directions, color: Colors.indigo),
                      tooltip: 'Open in Navigation',
                      onPressed: () {
                        ExternalDirectionsLauncher.showChooserModal(
                          context: context,
                          origin: widget.origin,
                          destination: widget.destination,
                        );
                      },
                    ),
                  ],
                ),
                if (isApproximate) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, size: 14, color: Colors.brown),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Approximate development estimate (OSRM demo offline)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.brown),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 16),

                // Location Summary Cards with Edit Actions
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: widget.onEditOrigin,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.trip_origin, size: 14, color: Colors.green),
                                  SizedBox(width: 4),
                                  Text('ORIGIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                  Spacer(),
                                  Icon(Icons.edit, size: 12, color: Colors.green),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                route.origin.displayLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: widget.onEditDestination,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.location_on, size: 14, color: Colors.indigo),
                                  SizedBox(width: 4),
                                  Text('DESTINATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                  Spacer(),
                                  Icon(Icons.edit, size: 12, color: Colors.indigo),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                route.destination.displayLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Genuine Interactive FlutterMap Tile Canvas with Route Line Overlay
                Container(
                  height: 200,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(centerLat, centerLng),
                          initialZoom: 8.5,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.shipdehop.mobile',
                          ),
                          if (polylineLatLngs.length > 1)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: polylineLatLngs,
                                  strokeWidth: 4.5,
                                  color: Colors.indigo,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(widget.origin.latitude, widget.origin.longitude),
                                width: 32,
                                height: 32,
                                child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
                              ),
                              Marker(
                                point: LatLng(widget.destination.latitude, widget.destination.longitude),
                                width: 32,
                                height: 32,
                                child: const Icon(Icons.location_on, color: Colors.red, size: 32),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Attribution Banner
                      Positioned(
                        bottom: 6,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isApproximate
                                ? '© OpenStreetMap contributors • Approximate development estimate'
                                : '© OpenStreetMap contributors • OSRM Demo',
                            style: const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Distance & Duration Summary Pill Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.straighten, size: 18, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Distance', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              route.formattedDistance,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(height: 24, width: 1, color: Colors.grey.shade300),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 18, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Estimated Time', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              route.formattedDuration,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Confirm CTA
                ElevatedButton.icon(
                  onPressed: () => widget.onRouteConfirmed(route),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Confirm Journey Route'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
