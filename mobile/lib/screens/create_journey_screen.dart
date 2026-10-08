import '../core/india_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/policy_resolver.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../models/journey.dart';
import '../models/route_result.dart';
import '../providers/app_providers.dart';
import '../repositories/journey_repository.dart';
import '../widgets/location_picker.dart';
import '../widgets/route_preview_widget.dart';
import 'journey_details_screen.dart';

class CreateJourneyScreen extends ConsumerStatefulWidget {
  const CreateJourneyScreen({
    super.key,
    this.initialPassengers = true,
    this.initialParcels = true,
    this.initialShopping = true,
    this.initialOriginLabel,
    this.initialDestinationLabel,
    this.initialDepartureDate,
    this.initialSeatCapacity,
    this.repository,
  });

  final bool initialPassengers;
  final bool initialParcels;
  final bool initialShopping;
  final String? initialOriginLabel;
  final String? initialDestinationLabel;
  final DateTime? initialDepartureDate;
  final int? initialSeatCapacity;
  final JourneyRepository? repository;

  @override
  ConsumerState<CreateJourneyScreen> createState() => _CreateJourneyScreenState();
}

class _CreateJourneyScreenState extends ConsumerState<CreateJourneyScreen> {
  ConfirmedLocation? _origin;
  ConfirmedLocation? _destination;

  RouteResult? _routeResult;
  bool _isLoadingRoute = false;
  String? _routeError;

  ResolvedPolicy? _fetchedPolicy;
  bool _isLoadingPolicy = false;
  String? _policyError;

  late bool _acceptPassengers;
  late bool _acceptParcels;
  late bool _acceptShopping;
  late int _seatCapacity;
  final TextEditingController _estimatedTripCostController = TextEditingController(text: '');
  final TextEditingController _pricePerSeatController = TextEditingController(text: '');
  String _parcelTier = 'MEDIUM';
  late DateTime _departureDate;
  bool _isFlexiDate = false;
  int _locationChangeToken = 0;

  @override
  void initState() {
    super.initState();
    _acceptPassengers = widget.initialPassengers;
    _acceptParcels = widget.initialParcels;
    _acceptShopping = widget.initialShopping;
    _seatCapacity = (widget.initialSeatCapacity ?? 2).clamp(1, 8);
    _departureDate = widget.initialDepartureDate ?? DateTime.now().add(const Duration(hours: 3));
    _applyInitialRoute();
  }

  @override
  void dispose() {
    _estimatedTripCostController.dispose();
    _pricePerSeatController.dispose();
    super.dispose();
  }

  Future<void> _applyInitialRoute() async {
    final originLabel      = widget.initialOriginLabel?.trim();
    final destinationLabel = widget.initialDestinationLabel?.trim();
    if (originLabel == null && destinationLabel == null) return;

    final geocoder = ref.read(geocodingProvider);
    String? geocodingError;

    if (originLabel?.isNotEmpty == true) {
      try {
        final matches = await geocoder.search(originLabel!);
        if (matches.isNotEmpty && mounted) {
          _origin = matches.first;
        } else if (mounted) {
          geocodingError = 'Could not resolve origin "$originLabel". Please select manually.';
        }
      } catch (err) {
        debugPrint('[CreateJourneyScreen] Initial origin geocoding failed: $err');
        if (mounted) {
          geocodingError = 'Could not resolve origin. Please select manually.';
        }
      }
    }

    if (destinationLabel?.isNotEmpty == true) {
      try {
        final matches = await geocoder.search(destinationLabel!);
        if (matches.isNotEmpty && mounted) {
          _destination = matches.first;
        } else if (mounted) {
          geocodingError = 'Could not resolve destination "$destinationLabel". Please select manually.';
        }
      } catch (err) {
        debugPrint('[CreateJourneyScreen] Initial destination geocoding failed: $err');
        if (mounted) {
          geocodingError = 'Could not resolve destination. Please select manually.';
        }
      }
    }

    if (!mounted) return;
    if (geocodingError != null) {
      setState(() {
        _routeError = geocodingError;
      });
    }

    if (_origin != null && _destination != null) {
      await _onLocationsChanged();
    }
  }

  Future<void> _onLocationsChanged() async {
    _locationChangeToken++;
    final token = _locationChangeToken;
    setState(() {
      _routeResult = null;
      _routeError = null;
      _fetchedPolicy = null;
      _policyError = null;
    });

    if (_origin != null && _destination != null) {
      await Future.wait([
        _computeRoute(token),
        _fetchPolicy(token),
      ]);
    }
  }

  Future<void> _computeRoute(int token) async {
    if (_origin == null || _destination == null) return;
    if (mounted) {
      setState(() {
        _isLoadingRoute = true;
        _routeError = null;
        _routeResult = null;
      });
    }
    try {
      final routing = ref.read(routingProvider);
      final res = await routing.calculateRoute(_origin!, _destination!);
      if (mounted && _locationChangeToken == token) {
        setState(() {
          _routeResult = res;
          _isLoadingRoute = false;
        });
      }
    } catch (err) {
      if (mounted && _locationChangeToken == token) {
        setState(() {
          _routeResult = null;
          _routeError = 'Failed to calculate road route: $err';
          _isLoadingRoute = false;
        });
      }
    }
  }

  Future<void> _fetchPolicy(int token) async {
    if (_origin == null || _destination == null) return;
    final policyResolver = PolicyResolver.resolvePolicy(_origin!, _destination!);
    if (!policyResolver.isSupported) {
      if (mounted && _locationChangeToken == token) {
        setState(() {
          _policyError = policyResolver.unsupportedReason ?? 'This route is not available yet.';
          _isLoadingPolicy = false;
        });
      }
      return;
    }

    if (mounted && _locationChangeToken == token) setState(() => _isLoadingPolicy = true);
    try {
      final policyRepo = ref.read(policyRepositoryProvider);
      final policy = await policyRepo.fetchPolicy(policyResolver.jurisdictionCode);
      if (!policy.isSupported || policy.maxRecoveryRatio == null) {
        throw Exception('Policy for ${policy.jurisdictionCode} is disabled or missing economic recovery limits.');
      }
      if (mounted && _locationChangeToken == token) {
        setState(() {
          _fetchedPolicy = policy;
          _policyError = null;
          _isLoadingPolicy = false;
        });
      }
    } catch (err) {
      if (mounted && _locationChangeToken == token) {
        setState(() {
          _fetchedPolicy = null;
          _policyError = 'Backend policy retrieval failed: ${err.toString().replaceAll('Exception: ', '')}';
          _isLoadingPolicy = false;
        });
      }
    }
  }

  bool get _canPublish {
    if (_origin == null || _destination == null) return false;
    if (_isLoadingRoute || _routeResult == null) return false;
    if (_isLoadingPolicy) return false;
    if (_acceptPassengers && (_fetchedPolicy == null || _policyError != null || _fetchedPolicy!.maxRecoveryRatio == null)) {
      return false;
    }
    final cost = double.tryParse(_estimatedTripCostController.text.trim());
    if (cost == null || cost <= 0) return false;

    if (_acceptPassengers) {
      final seatPrice = double.tryParse(_pricePerSeatController.text.trim());
      if (seatPrice == null || seatPrice < 0) return false;
    }
    return true;
  }

  Future<void> _handleConfirmJourney() async {
    if (_origin == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select origin and destination locations.')),
      );
      return;
    }

    if (_routeResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authoritative road route calculation is required to publish.')),
      );
      return;
    }

    final double? estimatedCostInput = double.tryParse(_estimatedTripCostController.text.trim());
    if (estimatedCostInput == null || estimatedCostInput <= 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive estimated trip cost.')),
      );
      return;
    }

    final effectiveSeatCap = _acceptPassengers ? _seatCapacity : 0;
    double effectivePricePerSeat = 0.0;

    final policyResolver = PolicyResolver.resolvePolicy(_origin!, _destination!);

    if (_acceptPassengers) {
      if (_fetchedPolicy == null || !_fetchedPolicy!.isSupported || _fetchedPolicy!.maxRecoveryRatio == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_policyError ?? 'Backend policy is required before validating passenger contribution.')),
        );
        return;
      }

      final double? priceInput = double.tryParse(_pricePerSeatController.text.trim());
      if (priceInput == null || priceInput < 0.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid requested contribution per passenger seat.')),
        );
        return;
      }
      effectivePricePerSeat = priceInput;

      final policy = _fetchedPolicy!;
      double maxCap = (estimatedCostInput / effectiveSeatCap) * policy.maxRecoveryRatio!;
      if (policy.hardCapPerSeat != null && policy.hardCapPerSeat! < maxCap) {
        maxCap = policy.hardCapPerSeat!;
      }
      if (effectivePricePerSeat > maxCap) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Passenger contribution exceeds policy cap of ${policy.currency} ${maxCap.toStringAsFixed(2)} per seat.')),
        );
        return;
      }
    }

    final timing = DateFlexibility(
      earliestDateTime: _departureDate,
      latestDateTime: _isFlexiDate
          ? _departureDate.add(const Duration(hours: 12))
          : _departureDate.add(const Duration(hours: 4)),
      isFlexible: _isFlexiDate,
    );

    final hasPhysicalCargo = _acceptParcels || _acceptShopping;
    final parcelCapacityTier = hasPhysicalCargo ? _parcelTier : 'NONE';

    final journey = Journey(
      id: 'journey-${DateTime.now().millisecondsSinceEpoch}',
      origin: _origin!,
      destination: _destination!,
      timing: timing,
      route: _routeResult,
      travellerName: 'You',
      seatCapacity: effectiveSeatCap,
      availableSeats: effectiveSeatCap,
      acceptsPassengers: _acceptPassengers,
      acceptsParcels: _acceptParcels,
      parcelCapacityTier: parcelCapacityTier,
      acceptsShoppingRequests: _acceptShopping,
      pricePerSeat: effectivePricePerSeat,
      estimatedTripCost: estimatedCostInput,
      currency: policyResolver.currency,
      jurisdictionCode: policyResolver.jurisdictionCode,
      status: 'SCHEDULED',
    );

    final repository = widget.repository ?? LiveJourneyRepository(apiClient: ref.read(apiClientProvider));
    final created = await repository.createJourney(journey);

    if (!mounted) return;
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => JourneyDetailsScreen(journey: created),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeGeocoder = ref.watch(geocodingProvider);
    final activeRouter = ref.watch(routingProvider);
    final activeLocationService = ref.watch(locationServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a Journey'),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Publish Your Route & Carry Opportunities',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'One unified journey powers passenger rides, parcel crowdshipping, and Buy-for-Me requests along your route.',
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
                      'Route & Schedule',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    LocationPicker(
                      title: 'Where are you travelling from?',
                      initialLocation: _origin,
                      geocodingProvider: activeGeocoder,
                      locationService: activeLocationService,
                      onLocationConfirmed: (loc) {
                        setState(() => _origin = loc);
                        _onLocationsChanged();
                      },
                    ),
                    const SizedBox(height: 12),
                    LocationPicker(
                      title: 'Where are you going?',
                      initialLocation: _destination,
                      geocodingProvider: activeGeocoder,
                      locationService: activeLocationService,
                      onLocationConfirmed: (loc) {
                        setState(() => _destination = loc);
                        _onLocationsChanged();
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Departure Time',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              Text(
                                IndiaTime.format(_departureDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          key: const Key('journey_departure_change'),
                          onPressed: () async {
                            final now = IndiaTime.wallClock(DateTime.now());
                            final safeInitial =
                                IndiaTime.wallClock(_departureDate).isBefore(now) ? now : IndiaTime.wallClock(_departureDate);
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: safeInitial,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (pickedDate != null && mounted) {
                              if (!context.mounted) return;
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(IndiaTime.wallClock(_departureDate)),
                              );
                              if (pickedTime != null && mounted) {
                                setState(() {
                                  _departureDate = IndiaTime.fromWallClock(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                  );
                                });
                              }
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text(
                        'Flexible departure window',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Allow matches within 12 hours of departure',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _isFlexiDate,
                      onChanged: (val) => setState(() => _isFlexiDate = val),
                    ),
                  ],
                ),
              ),
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
                      'Trip Economics & Cost Sharing',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('journey_estimated_trip_cost'),
                      controller: _estimatedTripCostController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Estimated Total Trip Cost (₹)',
                        hintText: 'e.g. 600.0',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (_acceptPassengers) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('journey_price_per_seat'),
                        controller: _pricePerSeatController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Requested Passenger Seat Contribution (₹)',
                          hintText: 'e.g. 150.0',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
                      'What capabilities do you offer on this trip?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    CheckboxListTile(
                      key: const Key('journey_accept_passengers'),
                      title: const Text('Accept passenger ride matches (HopRide)'),
                      subtitle: Text(_acceptPassengers
                          ? 'Available seats: $_seatCapacity'
                          : 'Disabled for this journey'),
                      value: _acceptPassengers,
                      onChanged: (val) => setState(() {
                        _acceptPassengers = val ?? true;
                      }),
                    ),
                    if (_acceptPassengers)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Text('Passenger seats available:'),
                            const SizedBox(width: 12),
                            DropdownButton<int>(
                              key: const Key('journey_seat_capacity'),
                              value: _seatCapacity,
                              items: List.generate(
                                8,
                                (i) => DropdownMenuItem(
                                  value: i + 1,
                                  child: Text('${i + 1} seat${i > 0 ? 's' : ''}'),
                                ),
                              ),
                              onChanged: (v) => setState(() => _seatCapacity = v ?? 2),
                            ),
                          ],
                        ),
                      ),
                    CheckboxListTile(
                      key: const Key('journey_accept_parcels'),
                      title: const Text('Accept parcel crowdshipping (HopShip)'),
                      subtitle: Text(_acceptParcels
                          ? 'Carry parcel shipments along route'
                          : 'Disabled for this journey'),
                      value: _acceptParcels,
                      onChanged: (val) => setState(() {
                        _acceptParcels = val ?? true;
                      }),
                    ),
                    CheckboxListTile(
                      key: const Key('journey_accept_shopping'),
                      title: const Text('Accept Buy-for-Me requests (HopShop)'),
                      subtitle: Text(_acceptShopping
                          ? 'Buy & deliver items requested along route'
                          : 'Disabled for this journey'),
                      value: _acceptShopping,
                      onChanged: (val) => setState(() {
                        _acceptShopping = val ?? false;
                      }),
                    ),
                    if (_acceptParcels || _acceptShopping)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Text('Carrying capacity tier:', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              key: const Key('journey_parcel_tier'),
                              value: _parcelTier,
                              items: const [
                                DropdownMenuItem(value: 'ENVELOPE', child: Text('Small items')),
                                DropdownMenuItem(value: 'MEDIUM', child: Text('Medium bag')),
                                DropdownMenuItem(value: 'LUGGAGE', child: Text('Large luggage')),
                              ],
                              onChanged: (v) => setState(() => _parcelTier = v ?? 'MEDIUM'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_routeError != null) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(_routeError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      TextButton(
                        onPressed: () => _onLocationsChanged(),
                        child: const Text('Retry Route Calculation'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_origin != null && _destination != null) ...[
              if (_isLoadingRoute)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Calculating road route...', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                RoutePreviewWidget(
                  origin: _origin!,
                  destination: _destination!,
                  routingProvider: activeRouter,
                  onRouteConfirmed: (res) => setState(() => _routeResult = res),
                  onEditOrigin: () {},
                  onEditDestination: () {},
                ),
              const SizedBox(height: 12),
            ],
            if (_isLoadingPolicy)
              const LinearProgressIndicator()
            else if (_policyError != null)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_policyError!, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                      ),
                      TextButton(
                        onPressed: () => _onLocationsChanged(),
                        child: const Text('Retry Policy'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_fetchedPolicy != null)
              Card(
                elevation: 0,
                color: Colors.purple.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            Text(
                              _fetchedPolicy!.countryName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple),
                            ),
                            Text(
                              _fetchedPolicy!.formattedSummary,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canPublish ? _handleConfirmJourney : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm & Publish Journey'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
