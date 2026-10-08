import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/policy_resolver.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../providers/app_providers.dart';
import '../widgets/date_flexibility_picker.dart';
import '../widgets/location_picker.dart';

class PostRideRequestScreen extends ConsumerStatefulWidget {
  const PostRideRequestScreen({super.key});

  @override
  ConsumerState<PostRideRequestScreen> createState() => _PostRideRequestScreenState();
}

class _PostRideRequestScreenState extends ConsumerState<PostRideRequestScreen> {
  ConfirmedLocation? _pickup;
  ConfirmedLocation? _drop;

  DateFlexibility _timing = DateFlexibility(
    earliestDateTime: DateTime.now().add(const Duration(hours: 1)),
    latestDateTime: DateTime.now().add(const Duration(hours: 6)),
    isFlexible: true,
    flexibilityWindowHours: 5,
  );

  int _seatsNeeded = 1;
  bool _isSubmitting = false;

  Future<void> _handleSubmitRequest() async {
    if (_pickup == null || _drop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a pickup and drop location.')),
      );
      return;
    }
    final policy = PolicyResolver.resolvePolicy(_pickup!, _drop!);
    if (!policy.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(policy.unsupportedReason ?? 'This route is not available yet.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final payload = {
        'pickupName': _pickup!.displayLabel,
        'pickup': {'lat': _pickup!.latitude, 'lon': _pickup!.longitude},
        'dropName': _drop!.displayLabel,
        'drop': {'lat': _drop!.latitude, 'lon': _drop!.longitude},
        'earliestDeparture': _timing.earliestDateTime.toUtc().toIso8601String(),
        'latestDeparture': _timing.latestDateTime.toUtc().toIso8601String(),
        'seatsNeeded': _seatsNeeded,
        'currency': policy.currency,
        'jurisdictionCode': policy.jurisdictionCode,
      };

      await ref.read(apiClientProvider).post('/ride-requests', payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Ride request posted! Compatible drivers along your route can now respond.',
          ),
          backgroundColor: Colors.indigo.shade800,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting ride request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _pickup != null && _drop != null
        ? PolicyResolver.resolvePolicy(_pickup!, _drop!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post a Ride Request'),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Need a Ride? Let Drivers Find You',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Specify your pickup, drop, timing, and seats needed. Drivers travelling your route will see your request.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pick Up & Drop Off',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    LocationPicker(
                      title: 'Where do you need pickup?',
                      initialLocation: _pickup,
                      geocodingProvider: ref.read(geocodingProvider),
                      locationService: ref.read(locationServiceProvider),
                      onLocationConfirmed: (loc) => setState(() => _pickup = loc),
                    ),
                    const SizedBox(height: 12),
                    LocationPicker(
                      title: 'Where are you going?',
                      initialLocation: _drop,
                      geocodingProvider: ref.read(geocodingProvider),
                      locationService: ref.read(locationServiceProvider),
                      onLocationConfirmed: (loc) => setState(() => _drop = loc),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DateFlexibilityPicker(
              title: 'Preferred Departure Window',
              initialValue: _timing,
              onChanged: (flex) => setState(() => _timing = flex),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Seats Needed',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Number of passenger seats required',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<int>(
                      value: _seatsNeeded,
                      items: List.generate(8, (i) => i + 1)
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text('$n seat${n > 1 ? 's' : ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _seatsNeeded = v ?? 1),
                    ),
                  ],
                ),
              ),
            ),
            if (policy != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Colors.purple.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined, color: Colors.purple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'India launch',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.purple,
                              ),
                            ),
                            Text(
                              policy.formattedSummary,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting || _pickup == null || _drop == null || policy?.isSupported != true
                    ? null
                    : _handleSubmitRequest,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Posting...' : 'Post Ride Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}