import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/policy_resolver.dart';
import '../core/profile_preferences.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../providers/app_providers.dart';
import '../widgets/date_flexibility_picker.dart';
import '../widgets/location_picker.dart';
import '../widgets/policy_summary_card.dart';
import '../widgets/route_preview_widget.dart';
import 'cargo_matches_screen.dart';

class PublishRouteScreen extends ConsumerStatefulWidget {
  const PublishRouteScreen({super.key});

  @override
  ConsumerState<PublishRouteScreen> createState() => _PublishRouteScreenState();
}

class _PublishRouteScreenState extends ConsumerState<PublishRouteScreen> {
  final _formKey = GlobalKey<FormState>();

  ConfirmedLocation? _originLoc;
  ConfirmedLocation? _destLoc;
  DateFlexibility _departureFlexibility = DateFlexibility(
    earliestDateTime: DateTime.now().add(const Duration(hours: 2)),
    latestDateTime: DateTime.now().add(const Duration(hours: 24)),
    isFlexible: true,
    flexibilityWindowHours: 1,
  );

  final originName = TextEditingController();
  final destName = TextEditingController();
  final oLat = TextEditingController();
  final oLon = TextEditingController();
  final dLat = TextEditingController();
  final dLon = TextEditingController();
  final price = TextEditingController();
  final tripCost = TextEditingController();
  final jurisdiction = TextEditingController(text: 'IN');
  final currency = TextEditingController(text: 'INR');

  int seats = 2;
  String cargo = 'MEDIUM';
  bool ladiesOnly = false;
  bool busy = false;
  late DateTime departure;

  @override
  void initState() {
    super.initState();
    // Default departure to safe future time (now + 2 hours)
    departure = DateTime.now().add(const Duration(hours: 2));
    Future<void>.microtask(_loadTravelDefaults);
  }

  Future<void> _loadTravelDefaults() async {
    String? userId;
    try {
      userId = ref.read(currentUserIdProvider);
    } catch (_) {
      // Widget tests and unauthenticated previews may render this screen
      // without initializing Supabase. Travel defaults are optional, so
      // keep the screen usable with its built-in defaults in that case.
      return;
    }

    if (userId == null) return;

    final prefs = await ProfilePreferencesStore(userId).loadTravelPreferences();
    if (!mounted) return;
    setState(() {
      cargo = prefs.parcelCapacity;
      ladiesOnly = prefs.ladiesOnly;
    });
  }

  @override
  void dispose() {
    for (final c in [
      originName,
      destName,
      oLat,
      oLon,
      dLat,
      dLon,
      price,
      tripCost,
      jurisdiction,
      currency,
    ]) {
      c.dispose();
    }
    super.dispose();
  }



  Future<void> publish() async {
    // If departure time has passed while editing form, refresh it or show validation error
    if (departure.isBefore(DateTime.now())) {
      setState(() {
        departure = DateTime.now().add(const Duration(hours: 2));
      });
    }

    if (!_formKey.currentState!.validate()) return;

    final nums = [oLat, oLon, dLat, dLon, price, tripCost]
        .map((c) => double.tryParse(c.text.trim()))
        .toList();
    if (nums.any((e) => e == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid numeric values for coordinates and prices.')),
      );
      return;
    }

    if (departure.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Departure time must be in the future.')),
      );
      return;
    }

    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final created = await ref.read(apiClientProvider).post('/trips', {
        'originName': originName.text.trim(),
        'origin': {'lat': nums[0], 'lon': nums[1]},
        'destinationName': destName.text.trim(),
        'destination': {'lat': nums[2], 'lon': nums[3]},
        'departureTime': departure.toUtc().toIso8601String(),
        'seats': seats,
        'parcelCapacityTier': cargo,
        'pricePerSeat': nums[4],
        'estimatedTripCost': nums[5],
        'currency': currency.text.trim().toUpperCase(),
        'jurisdictionCode': jurisdiction.text.trim(),
        'ladiesOnly': ladiesOnly,
      });

      final tripMap = (created['trip'] as Map).cast<String, dynamic>();
      final tripId = tripMap['id'].toString();

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Route published successfully! Matching approved HopShip parcels...'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CargoMatchesScreen(tripId: tripId),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to publish route: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Publish Carrier Route'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carrier / Traveller Route Publishing',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Publish your upcoming route to offer passenger seats and carry pre-inspected HopShip parcels along your travel corridor.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LocationPicker(
                title: 'Journey Origin',
                initialQuery: originName.text.isNotEmpty ? originName.text : null,
                geocodingProvider: ref.read(geocodingProvider),
                locationService: ref.read(locationServiceProvider),
                onLocationConfirmed: (loc) {
                  setState(() => _originLoc = loc);
                  originName.text = loc.displayLabel;
                  oLat.text = loc.latitude.toString();
                  oLon.text = loc.longitude.toString();
                },
              ),
              const SizedBox(height: 12),
              LocationPicker(
                title: 'Journey Destination',
                initialQuery: destName.text.isNotEmpty ? destName.text : null,
                geocodingProvider: ref.read(geocodingProvider),
                locationService: ref.read(locationServiceProvider),
                onLocationConfirmed: (loc) {
                  setState(() => _destLoc = loc);
                  destName.text = loc.displayLabel;
                  dLat.text = loc.latitude.toString();
                  dLon.text = loc.longitude.toString();
                },
              ),
              if (_originLoc != null && _destLoc != null) ...[
                const SizedBox(height: 16),
                PolicySummaryCard(
                  policy: PolicyResolver.resolvePolicy(_originLoc!, _destLoc!),
                ),
                const SizedBox(height: 16),
                RoutePreviewWidget(
                  origin: _originLoc!,
                  destination: _destLoc!,
                  onRouteConfirmed: (route) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Carrier route confirmed (${route.formattedDistance}, ${route.formattedDuration})'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  onEditOrigin: () => setState(() => _originLoc = null),
                  onEditDestination: () => setState(() => _destLoc = null),
                ),
              ],
              const SizedBox(height: 16),
              DateFlexibilityPicker(
                title: 'Carrier Departure Timing Window',
                initialValue: _departureFlexibility,
                onChanged: (flex) => setState(() => _departureFlexibility = flex),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: seats,
                decoration: const InputDecoration(
                  labelText: 'Passenger Seats Offered',
                  prefixIcon: Icon(Icons.event_seat_outlined),
                ),
                items: List.generate(
                  8,
                  (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} Seat${i == 0 ? '' : 's'}')),
                ),
                onChanged: (v) => setState(() => seats = v ?? 1),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: cargo,
                decoration: const InputDecoration(
                  labelText: 'HopShip Parcel Capacity Tier',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'NONE', child: Text('NONE (Passengers Only)')),
                  DropdownMenuItem(value: 'ENVELOPE', child: Text('ENVELOPE (Docs up to 1 kg)')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('MEDIUM (Small Box up to 5 kg)')),
                  DropdownMenuItem(value: 'LUGGAGE', child: Text('LUGGAGE (Large Bag up to 25 kg)')),
                ],
                onChanged: (v) => setState(() => cargo = v ?? 'MEDIUM'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: ladiesOnly,
                onChanged: (v) => setState(() => ladiesOnly = v),
                title: const Text('Ladies Only Corridor'),
                subtitle: const Text('Restrict match visibility to verified female travellers & senders'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price / Seat (INR)',
                        hintText: 'e.g. 300',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (v) {
                        final parsed = double.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed < 0) return 'Enter a valid seat price (≥ 0)';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: tripCost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Estimated Trip Cost (INR)',
                        hintText: 'e.g. 600',
                        prefixIcon: Icon(Icons.calculate_outlined),
                      ),
                      validator: (v) {
                        final parsed = double.tryParse(v?.trim() ?? '');
                        if (parsed == null || parsed <= 0) return 'Enter total trip cost (> 0)';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      validator: (v) => v == null || v.trim().length != 3 ? '3-letter currency (e.g. INR)' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: jurisdiction,
                      decoration: const InputDecoration(labelText: 'Jurisdiction Code'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required (e.g. IN_MH)' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: The backend recalculates cost-sharing compliance based on jurisdiction policy.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : publish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.publish),
                label: Text(
                  busy ? 'Publishing Route...' : 'Publish Route & Search Parcel Matches',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
}
