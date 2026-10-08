import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/confirmed_location.dart';

enum NavigationProvider {
  googleMaps,
  appleMaps,
  waze,
  hereWeGo,
  openStreetMap,
  bingMaps,
}

class ExternalDirectionsLauncher {
  static String getDirectionsUrl({
    required NavigationProvider provider,
    required ConfirmedLocation origin,
    required ConfirmedLocation destination,
  }) {
    final oLat = origin.latitude;
    final oLng = origin.longitude;
    final dLat = destination.latitude;
    final dLng = destination.longitude;

    switch (provider) {
      case NavigationProvider.googleMaps:
        return 'https://www.google.com/maps/dir/?api=1&origin=$oLat,$oLng&destination=$dLat,$dLng&travelmode=driving';
      case NavigationProvider.appleMaps:
        return 'https://maps.apple.com/?saddr=$oLat,$oLng&daddr=$dLat,$dLng';
      case NavigationProvider.waze:
        return 'https://waze.com/ul?ll=$dLat,$dLng&navigate=yes';
      case NavigationProvider.hereWeGo:
        return 'https://wego.here.com/directions/drive/$oLat,$oLng/$dLat,$dLng';
      case NavigationProvider.openStreetMap:
        return 'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=$oLat,$oLng;$dLat,$dLng';
      case NavigationProvider.bingMaps:
        return 'https://www.bing.com/maps?rtp=pos.${oLat}_$oLng~pos.${dLat}_$dLng';
    }
  }

  static Future<bool> launchDirections({
    required NavigationProvider provider,
    required ConfirmedLocation origin,
    required ConfirmedLocation destination,
  }) async {
    final urlString = getDirectionsUrl(
      provider: provider,
      origin: origin,
      destination: destination,
    );
    final uri = Uri.parse(urlString);

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Fall back to platform default web view if external app launch fails
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  static void showChooserModal({
    required BuildContext context,
    required ConfirmedLocation origin,
    required ConfirmedLocation destination,
  }) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.directions, color: Colors.indigo),
                    const SizedBox(width: 10),
                    Text(
                      'Open External Navigation',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.red),
                title: const Text('Google Maps'),
                subtitle: const Text('Web & Native Maps'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchDirections(provider: NavigationProvider.googleMaps, origin: origin, destination: destination);
                },
              ),
              ListTile(
                leading: const Icon(Icons.explore, color: Colors.black),
                title: const Text('Apple Maps'),
                subtitle: const Text('iOS & Web Navigation'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchDirections(provider: NavigationProvider.appleMaps, origin: origin, destination: destination);
                },
              ),
              ListTile(
                leading: const Icon(Icons.navigation, color: Colors.lightBlue),
                title: const Text('Waze'),
                subtitle: const Text('Live Community Traffic'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchDirections(provider: NavigationProvider.waze, origin: origin, destination: destination);
                },
              ),
              ListTile(
                leading: const Icon(Icons.place, color: Colors.blue),
                title: const Text('HERE WeGo'),
                subtitle: const Text('Turn-by-turn Navigation'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchDirections(provider: NavigationProvider.hereWeGo, origin: origin, destination: destination);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public, color: Colors.green),
                title: const Text('OpenStreetMap Directions'),
                subtitle: const Text('Open Source OSRM Router'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchDirections(provider: NavigationProvider.openStreetMap, origin: origin, destination: destination);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
