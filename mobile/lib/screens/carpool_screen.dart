import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/route_location_picker.dart';
import '../widgets/ui/shd_primary_button.dart';
import 'create_journey_screen.dart';
import 'my_routes_screen.dart';
import 'post_ride_request_screen.dart';

class CarPoolScreen extends ConsumerStatefulWidget {
  const CarPoolScreen({
    super.key,
    this.initialModeIndex = 0,
    this.prefilledOrigin,
    this.prefilledDestination,
  });

  final int initialModeIndex;
  final String? prefilledOrigin;
  final String? prefilledDestination;

  @override
  ConsumerState<CarPoolScreen> createState() => _CarPoolScreenState();
}

class _CarPoolScreenState extends ConsumerState<CarPoolScreen> {
  late int _selectedModeIndex;
  String _origin = 'Choose origin';
  String _destination = 'Choose destination';

  late DateTime _findDeparture;
  DateTime? _findReturn;
  int _findPassengers = 1;

  late DateTime _offerDeparture;
  int _offerSeats = 3;

  @override
  void initState() {
    super.initState();
    _selectedModeIndex = widget.initialModeIndex;
    final now = DateTime.now();
    _findDeparture = DateTime(now.year, now.month, now.day);
    _offerDeparture = now.add(const Duration(hours: 3));
    _applyPrefilledRoute();
  }

  void _applyPrefilledRoute() {
    if (widget.prefilledOrigin?.trim().isNotEmpty == true) {
      _origin = widget.prefilledOrigin!.trim();
    }
    if (widget.prefilledDestination?.trim().isNotEmpty == true) {
      _destination = widget.prefilledDestination!.trim();
    }
  }

  @override
  void didUpdateWidget(covariant CarPoolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModeIndex != oldWidget.initialModeIndex ||
        widget.prefilledOrigin != oldWidget.prefilledOrigin ||
        widget.prefilledDestination != oldWidget.prefilledDestination) {
      setState(() {
        _selectedModeIndex = widget.initialModeIndex;
        _applyPrefilledRoute();
      });
    }
  }

  bool get _routeReady =>
      _origin != 'Choose origin' && _destination != 'Choose destination';

  Future<void> _pickRoute() async {
    final result = await RouteLocationPicker.show(
      context,
      title: 'Choose your CarPool route',
      initialOrigin: _origin,
      initialDestination: _destination,
      geocodingProvider: ref.read(geocodingProvider),
      locationService: ref.read(locationServiceProvider),
    );
    if (result == null || !mounted) return;
    setState(() {
      _origin = result.origin.displayLabel;
      _destination = result.destination.displayLabel;
    });
  }

  Future<void> _pickFindDeparture() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _findDeparture.isBefore(DateTime(now.year, now.month, now.day))
          ? now
          : _findDeparture,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'When are you travelling?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _findDeparture = picked;
      if (_findReturn != null && _findReturn!.isBefore(picked)) {
        _findReturn = null;
      }
    });
  }

  Future<void> _pickFindReturn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _findReturn ?? _findDeparture.add(const Duration(days: 1)),
      firstDate: _findDeparture,
      lastDate: _findDeparture.add(const Duration(days: 365)),
      helpText: 'Choose return date',
    );
    if (picked != null && mounted) setState(() => _findReturn = picked);
  }

  Future<int?> _pickCount({
    required String title,
    required int initial,
    int min = 1,
    int max = 8,
    String singular = 'person',
    String plural = 'people',
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var count = initial;
        return StatefulBuilder(
          builder: (context, setSheetState) => Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ShipdeHopColors.borderLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title, style: ShipdeHopTypography.titleLarge),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$count ${count == 1 ? singular : plural}',
                        style: ShipdeHopTypography.titleMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: count > min
                          ? () => setSheetState(() => count--)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: count < max
                          ? () => setSheetState(() => count++)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, count),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: ShipdeHopColors.brandPrimary,
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFindPassengers() async {
    final count = await _pickCount(
      title: 'How many passengers?',
      initial: _findPassengers,
      singular: 'passenger',
      plural: 'passengers',
    );
    if (count != null && mounted) setState(() => _findPassengers = count);
  }

  Future<void> _pickOfferDeparture() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _offerDeparture.isBefore(now) ? now : _offerDeparture,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'When will you leave?',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_offerDeparture),
      helpText: 'Choose departure time',
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      _offerDeparture = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickOfferSeats() async {
    final count = await _pickCount(
      title: 'How many seats are available?',
      initial: _offerSeats,
      singular: 'seat',
      plural: 'seats',
    );
    if (count != null && mounted) setState(() => _offerSeats = count);
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(date.year, date.month, date.day);
    if (value == today) return 'Today';
    if (value == today.add(const Duration(days: 1))) return 'Tomorrow';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _timeLabel(DateTime date) {
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${_dateLabel(date)}, $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CarPool',
                    style: ShipdeHopTypography.displayLarge.copyWith(fontSize: 27),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share the road, not the whole cost.',
                    style: ShipdeHopTypography.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E5F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        _tab(0, 'Find a Ride', Icons.person_pin_circle_outlined),
                        _tab(1, 'Offer a Ride', Icons.directions_car_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: IndexedStack(
                index: _selectedModeIndex,
                children: [_findRide(), _offerRide()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, String label, IconData icon) {
    final selected = _selectedModeIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedModeIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: 180.ms,
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: ShipdeHopColors.shadow,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? ShipdeHopColors.brandPrimary
                    : ShipdeHopColors.textMuted,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? ShipdeHopColors.textPrimary
                        : ShipdeHopColors.textSecondary,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _findRide() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Where are you going?',
          style: ShipdeHopTypography.displayMedium.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 14),
        _findRideCard(),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ShipdeHopColors.carpoolBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: ShipdeHopColors.carpoolAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Can't find the exact ride?", style: ShipdeHopTypography.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Post your route and seat request for nearby drivers.',
                      style: ShipdeHopTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PostRideRequestScreen(),
                  ),
                ),
                child: const Text('Post'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ShipdeHopColors.carpoolBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                color: ShipdeHopColors.carpoolAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CarPool is launching in India first. Choose your real route and travel date to find available rides.',
                  style: ShipdeHopTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _findRideCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShipdeHopColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: ShipdeHopColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            key: const Key('carpool_find_route_picker'),
            onTap: _pickRoute,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _locationRow('FROM', _origin, Icons.trip_origin_rounded, ShipdeHopColors.success),
                  const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
                  _locationRow('TO', _destination, Icons.location_on_rounded, ShipdeHopColors.squirrelOrange),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
          Row(
            children: [
              Expanded(
                child: _searchFieldTile(
                  key: const Key('carpool_find_departure'),
                  label: 'DEPARTURE',
                  value: _dateLabel(_findDeparture),
                  icon: Icons.calendar_month_rounded,
                  onTap: _pickFindDeparture,
                ),
              ),
              Container(width: 1, height: 58, color: ShipdeHopColors.borderSubtle),
              Expanded(
                child: _searchFieldTile(
                  key: const Key('carpool_find_return'),
                  label: 'RETURN',
                  value: _findReturn == null ? 'One way' : _dateLabel(_findReturn!),
                  icon: Icons.event_repeat_rounded,
                  onTap: _pickFindReturn,
                  onClear: _findReturn == null
                      ? null
                      : () => setState(() => _findReturn = null),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
          _searchFieldTile(
            key: const Key('carpool_find_passengers'),
            label: 'PASSENGERS',
            value: '$_findPassengers passenger${_findPassengers == 1 ? '' : 's'}',
            icon: Icons.people_outline_rounded,
            onTap: _pickFindPassengers,
          ),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton.icon(
              key: const Key('carpool_search_button'),
              onPressed: _routeReady
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Searching rides for $_origin → $_destination on ${_dateLabel(_findDeparture)} for $_findPassengers passenger${_findPassengers == 1 ? '' : 's'}.',
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search'),
              style: FilledButton.styleFrom(
                backgroundColor: ShipdeHopColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerRide() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          'Offer a ride',
          style: ShipdeHopTypography.displayMedium.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 4),
        Text(
          'Publish seats on a route you are already taking.',
          style: ShipdeHopTypography.bodyMedium,
        ),
        const SizedBox(height: 14),
        _routePanel(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricButton(
                key: const Key('carpool_offer_departure'),
                label: 'DEPARTURE',
                value: _timeLabel(_offerDeparture),
                icon: Icons.schedule_rounded,
                onTap: _pickOfferDeparture,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricButton(
                key: const Key('carpool_offer_seats'),
                label: 'SEATS',
                value: '$_offerSeats available',
                icon: Icons.event_seat_rounded,
                onTap: _pickOfferSeats,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ShdPrimaryButton(
          label: 'Create journey',
          icon: Icons.add_road_rounded,
          onPressed: _routeReady
              ? () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CreateJourneyScreen(
                        initialPassengers: true,
                        initialParcels: true,
                        initialShopping: true,
                        initialOriginLabel: _origin,
                        initialDestinationLabel: _destination,
                        initialDepartureDate: _offerDeparture,
                        initialSeatCapacity: _offerSeats,
                      ),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const MyRoutesScreen()),
            ),
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('My published routes'),
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ShipdeHopColors.brandDark,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.directions_car_rounded,
                  color: ShipdeHopColors.squirrelOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Turn empty seats into shared miles',
                      style: ShipdeHopTypography.titleSmall.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Real requests and cost-sharing options appear only after your India route is published.',
                      style: ShipdeHopTypography.bodySmall.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routePanel() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('carpool_route_picker'),
        onTap: _pickRoute,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: ShipdeHopColors.shadow,
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              _locationRow('FROM', _origin, Icons.my_location_rounded, ShipdeHopColors.success),
              const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
              _locationRow('TO', _destination, Icons.location_on_rounded, ShipdeHopColors.squirrelOrange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationRow(String label, String value, IconData icon, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ShipdeHopTypography.labelSmall.copyWith(
                    fontSize: 11,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: ShipdeHopColors.textMuted),
        ],
      ),
    );
  }

  Widget _searchFieldTile({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: ShipdeHopColors.brandPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: ShipdeHopTypography.labelSmall),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  tooltip: 'Make one way',
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: ShipdeHopColors.textMuted,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricButton({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: ShipdeHopColors.brandPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: ShipdeHopTypography.labelSmall),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 13),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: ShipdeHopColors.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}