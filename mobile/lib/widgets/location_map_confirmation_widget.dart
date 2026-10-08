import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/geocoding_provider.dart';
import '../core/launch_market.dart';
import '../models/confirmed_location.dart';

class LocationMapConfirmationWidget extends StatefulWidget {
  const LocationMapConfirmationWidget({
    super.key,
    required this.initialLocation,
    this.geocodingProvider = const BackendGeocodingAdapter(),
    required this.onConfirmed,
    required this.onCancel,
  });

  final ConfirmedLocation initialLocation;
  final GeocodingProvider geocodingProvider;
  final void Function(ConfirmedLocation confirmed) onConfirmed;
  final VoidCallback onCancel;

  @override
  State<LocationMapConfirmationWidget> createState() => _LocationMapConfirmationWidgetState();
}

class _LocationMapConfirmationWidgetState extends State<LocationMapConfirmationWidget> {
  late double _currentLat;
  late double _currentLng;
  late ConfirmedLocation _currentLocation;
  late MapController _mapController;
  bool _reverseGeocoding = false;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLocation.latitude;
    _currentLng = widget.initialLocation.longitude;
    _currentLocation = widget.initialLocation;
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _updatePinLocation(double lat, double lng) async {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _reverseGeocoding = true;
    });

    _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);

    try {
      final updated = await widget.geocodingProvider.reverseGeocode(lat, lng);
      if (mounted) setState(() => _currentLocation = updated);
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentLocation = ConfirmedLocation(
            displayLabel: 'Outside launch area',
            formattedAddress: LaunchMarket.unsupportedMessage,
            latitude: lat,
            longitude: lng,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _reverseGeocoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centerPoint = LatLng(_currentLat, _currentLng);
    final inIndia = LaunchMarket.isSupportedLocation(_currentLocation);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Location Pin'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onCancel,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: centerPoint,
                    initialZoom: 14.0,
                    onPositionChanged: (pos, hasGesture) {
                      if (hasGesture) {
                        _updatePinLocation(
                          pos.center.latitude,
                          pos.center.longitude,
                        );
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      // Label-free map keeps the English ShipdeHop UI consistent.
                      urlTemplate: 'https://a.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}@2x.png',
                      userAgentPackageName: 'com.shipdehop',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: centerPoint,
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.location_on,
                            size: 48,
                            color: inIndia ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors · © CARTO',
                      style: TextStyle(fontSize: 9.5, color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      inIndia ? Icons.place : Icons.public_off_outlined,
                      color: inIndia ? Colors.indigo : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inIndia ? _currentLocation.displayLabel : 'India launch only',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            inIndia ? _currentLocation.formattedAddress : LaunchMarket.unsupportedMessage,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (_reverseGeocoding)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: inIndia && !_reverseGeocoding
                      ? () => widget.onConfirmed(_currentLocation)
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(inIndia ? 'Confirm Location' : 'Choose a location in India'),
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
        ],
      ),
    );
  }
}