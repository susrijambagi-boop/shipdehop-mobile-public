import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import 'cargo_matches_screen.dart';
import 'publish_route_screen.dart';

class MyRoutesScreen extends ConsumerStatefulWidget {
  const MyRoutesScreen({super.key});

  @override
  ConsumerState<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends ConsumerState<MyRoutesScreen> {
  @override
  Widget build(BuildContext context) {
    final routesAsync = ref.watch(myRoutesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Published Routes'),
        actions: [
          IconButton(
            tooltip: 'Refresh Routes',
            onPressed: () => ref.invalidate(myRoutesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: routesAsync.when(
        data: (routes) {
          if (routes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.alt_route, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No Published Routes Yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Publish a route to offer ride seats and match approved HopShip parcels along your travel corridor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => const PublishRouteScreen()),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Publish New Route'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRoutesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                final tripId = route['id'].toString();
                final origin = route['origin_name'] ?? 'Origin';
                final dest = route['dest_name'] ?? 'Destination';
                final departureStr = route['departure_time']?.toString();
                final departure = departureStr != null ? DateTime.tryParse(departureStr)?.toLocal() : null;
                final status = route['status'] ?? 'SCHEDULED';
                final cargoTier = route['parcel_capacity_tier'] ?? 'NONE';
                final seats = route['seat_capacity'] ?? 1;
                final currency = route['currency'] ?? 'INR';
                final price = route['price_per_seat'] ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.directions_car),
                    ),
                    title: Text(
                      '$origin → $dest',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        if (departure != null)
                          Text(
                            'Departure: ${departure.toString().substring(0, 16)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        Text(
                          'Cargo: $cargoTier • Seats: $seats ($currency $price/seat) • Status: $status',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chevron_right),
                        Text(
                          'Matches',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CargoMatchesScreen(tripId: tripId),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load routes: $e', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(myRoutesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => const PublishRouteScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Publish Route'),
      ),
    );
  }
}
