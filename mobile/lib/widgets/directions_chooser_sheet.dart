import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';

class DirectionsChooserSheet extends StatelessWidget {
  const DirectionsChooserSheet({
    super.key,
    required this.destinationName,
    required this.latitude,
    required this.longitude,
  });

  final String destinationName;
  final double latitude;
  final double longitude;

  static void show(
    BuildContext context, {
    required String destinationName,
    required double latitude,
    required double longitude,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DirectionsChooserSheet(
        destinationName: destinationName,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  Future<void> _launchUrl(String urlStr, BuildContext context) async {
    final uri = Uri.parse(urlStr);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open map provider for $destinationName')),
          );
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ShipdeHopColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Directions to $destinationName',
            style: ShipdeHopTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select your preferred navigation application:',
            style: TextStyle(fontSize: 12, color: ShipdeHopColors.textSecondary),
          ),
          const SizedBox(height: 16),

          if (isIOS)
            ListTile(
              leading: const Icon(Icons.map_rounded, color: Colors.blue),
              title: const Text('Apple Maps', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(context);
                _launchUrl('http://maps.apple.com/?daddr=$latitude,$longitude', context);
              },
            ),

          ListTile(
            leading: const Icon(Icons.navigation_rounded, color: Colors.red),
            title: const Text('Google Maps', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _launchUrl('https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude', context);
            },
          ),

          ListTile(
            leading: const Icon(Icons.alt_route_rounded, color: Colors.lightBlue),
            title: const Text('Waze', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _launchUrl('https://waze.com/ul?ll=$latitude,$longitude&navigate=yes', context);
            },
          ),

          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.green),
            title: const Text('OpenStreetMap', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _launchUrl('https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=;$latitude,$longitude', context);
            },
          ),
        ],
      ),
    );
  }
}
