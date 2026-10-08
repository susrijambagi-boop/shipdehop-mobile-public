import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/india_time.dart';
import '../models/journey.dart';
import '../models/journey_opportunity.dart';
import '../providers/app_providers.dart';
import '../repositories/journey_repository.dart';

class JourneyDetailsScreen extends ConsumerStatefulWidget {
  const JourneyDetailsScreen({
    super.key,
    required this.journey,
    this.repository,
  });

  final Journey journey;
  final JourneyRepository? repository;

  @override
  ConsumerState<JourneyDetailsScreen> createState() => _JourneyDetailsScreenState();
}

class _JourneyDetailsScreenState extends ConsumerState<JourneyDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late JourneyRepository _repository;
  bool _isLoading = false;
  String? _errorMessage;
  List<JourneyOpportunity> _opportunities = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _repository = widget.repository ?? LiveJourneyRepository(apiClient: ref.read(apiClientProvider));
    _loadOpportunities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOpportunities() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final opps = await _repository.fetchJourneyOpportunities(widget.journey.id);
      if (mounted) {
        setState(() {
          _opportunities = opps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptOpportunity(JourneyOpportunity opp) async {
    setState(() => _isLoading = true);
    try {
      if (opp.type == JourneyOpportunityType.passenger) {
        await ref.read(apiClientProvider).post('/ride-requests/${opp.id}/accept', {
          'tripId': widget.journey.id,
        });
      } else {
        await ref.read(apiClientProvider).post('/orders/reserve-shipment', {
          'shipmentTaskId': opp.id,
          'tripId': widget.journey.id,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${opp.typeLabel} accepted! Escrow order created.'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        _loadOpportunities();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept match: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.journey;

    final passengerOpps = _opportunities.where((o) => o.type == JourneyOpportunityType.passenger).toList();
    final parcelOpps = _opportunities.where((o) => o.type == JourneyOpportunityType.parcel).toList();
    final shoppingOpps = _opportunities.where((o) => o.type == JourneyOpportunityType.shoppingRequest).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Details'),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // JOURNEY HEADER CARD
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            j.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            j.statusLabel,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(Icons.person_pin, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(j.travellerName, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(width: 16),
                        const Icon(Icons.schedule, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          IndiaTime.formatIst(j.timing.earliestDateTime, includeDate: true),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

                    // CAPACITY SUMMARY
                    const Text('Capacity Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.event_seat, size: 16, color: Colors.indigo),
                          label: Text(j.acceptsPassengers ? '${j.availableSeats}/${j.seatCapacity} Seats Available' : 'No Seats Offered'),
                          backgroundColor: j.acceptsPassengers ? Colors.indigo.shade50 : Colors.grey.shade100,
                        ),
                        Chip(
                          avatar: const Icon(Icons.local_shipping, size: 16, color: Colors.blue),
                          label: Text(j.acceptsParcels ? j.parcelCapacityFormattedSummary : 'No Parcels'),
                          backgroundColor: j.acceptsParcels ? Colors.blue.shade50 : Colors.grey.shade100,
                        ),
                        Chip(
                          avatar: const Icon(Icons.shopping_bag, size: 16, color: Colors.teal),
                          label: Text(j.acceptsShoppingRequests ? 'Shopping Carry Active' : 'No Shopping'),
                          backgroundColor: j.acceptsShoppingRequests ? Colors.teal.shade50 : Colors.grey.shade100,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // OPPORTUNITIES SECTION TITLE
            const Text(
              'Opportunities Along Your Journey',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Matching requests en route along your travel corridor',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 12),

            // TAB BAR FOR OPPORTUNITIES
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.indigo,
                labelColor: Colors.indigo.shade900,
                unselectedLabelColor: Colors.grey.shade600,
                tabs: [
                  Tab(text: 'Passengers (${passengerOpps.length})'),
                  Tab(text: 'Parcels (${parcelOpps.length})'),
                  Tab(text: 'Shopping (${shoppingOpps.length})'),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error loading opportunities: $_errorMessage', style: const TextStyle(color: Colors.red)),
                ),
              )
            else
              SizedBox(
                height: 360,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOpportunityList(passengerOpps, 'No passenger ride requests along this corridor.'),
                    _buildOpportunityList(parcelOpps, 'No parcel delivery requests along this corridor.'),
                    _buildOpportunityList(shoppingOpps, 'No Shopster shopping requests along this corridor.'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpportunityList(List<JourneyOpportunity> opps, String emptyMessage) {
    if (opps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: opps.length,
      itemBuilder: (context, index) {
        final opp = opps[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: opp.type == JourneyOpportunityType.passenger
                                ? Colors.indigo.shade50
                                : opp.type == JourneyOpportunityType.parcel
                                    ? Colors.blue.shade50
                                    : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            opp.typeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: opp.type == JourneyOpportunityType.passenger
                                  ? Colors.indigo.shade900
                                  : opp.type == JourneyOpportunityType.parcel
                                      ? Colors.blue.shade900
                                      : Colors.teal.shade900,
                            ),
                          ),
                        ),
                        if (opp.type == JourneyOpportunityType.parcel || opp.type == JourneyOpportunityType.shoppingRequest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: opp.calculateFitStatus(widget.journey.parcelCapacityUnitsAvailable) == ParcelFitStatus.tooLarge
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: opp.calculateFitStatus(widget.journey.parcelCapacityUnitsAvailable) == ParcelFitStatus.tooLarge
                                    ? Colors.red.shade300
                                    : Colors.green.shade300,
                              ),
                            ),
                            child: Text(
                              opp.getFitLabel(widget.journey.parcelCapacityUnitsAvailable),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: opp.calculateFitStatus(widget.journey.parcelCapacityUnitsAvailable) == ParcelFitStatus.tooLarge
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                        if (opp.isSimulation) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade800, width: 0.5),
                            ),
                            child: Text(
                              'DEV SIMULATION',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        opp.scoreLabel,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Text(
                  '${opp.origin.displayLabel} → ${opp.destination.displayLabel}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(opp.requesterName, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    const SizedBox(width: 12),
                    if (opp.weightKg != null) ...[
                      const Icon(Icons.scale, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('${opp.weightKg} kg', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ],
                    if (opp.seatsNeeded != null) ...[
                      const Icon(Icons.event_seat, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('${opp.seatsNeeded} seat', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ],
                  ],
                ),

                const Divider(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${opp.currency} ${opp.rewardAmount.toStringAsFixed(0)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
                        ),
                        const Text('Offered Reward', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: opp.calculateFitStatus(widget.journey.parcelCapacityUnitsAvailable) == ParcelFitStatus.tooLarge
                          ? null
                          : () => _acceptOpportunity(opp),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Accept Match'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
