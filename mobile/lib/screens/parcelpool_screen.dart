import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/route_location_picker.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/ui/shd_primary_button.dart';
import 'create_journey_screen.dart';
import 'hopship_screen.dart';

class ParcelPoolScreen extends ConsumerStatefulWidget {
  const ParcelPoolScreen({
    super.key,
    this.initialModeIndex = 0,
    this.prefilledOrigin,
    this.prefilledDestination,
  });

  final int initialModeIndex;
  final String? prefilledOrigin;
  final String? prefilledDestination;

  @override
  ConsumerState<ParcelPoolScreen> createState() => _ParcelPoolScreenState();
}

class _ParcelPoolScreenState extends ConsumerState<ParcelPoolScreen> {
  late int _selectedModeIndex;
  String _origin = 'Current location';
  String _destination = 'Choose destination';
  String _bringFrom = 'Choose city';
  String _bringItem = 'Describe the item or paste a Buy-for-Me URL';
  DateTime _sendDate = DateTime.now();
  DateTime? _travelDate;
  int _selectedParcelSize = 1;

  static const _parcelSizes = [
    ('S', '≤2kg', '2'),
    ('M', '≤5kg', '5'),
    ('L', '≤10kg', '10'),
    ('XL', '≤20kg', '20'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedModeIndex = widget.initialModeIndex;
    _applyPrefills();
  }

  @override
  void didUpdateWidget(covariant ParcelPoolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModeIndex != oldWidget.initialModeIndex ||
        widget.prefilledOrigin != oldWidget.prefilledOrigin ||
        widget.prefilledDestination != oldWidget.prefilledDestination) {
      setState(() {
        _selectedModeIndex = widget.initialModeIndex;
        _applyPrefills();
      });
    }
  }

  void _applyPrefills() {
    if (widget.prefilledOrigin?.trim().isNotEmpty == true) {
      _origin = widget.prefilledOrigin!.trim();
    }
    if (widget.prefilledDestination?.trim().isNotEmpty == true) {
      _destination = widget.prefilledDestination!.trim();
    }
  }

  Future<void> _pickRoute({bool bringMode = false}) async {
    final result = await RouteLocationPicker.show(
      context,
      title: bringMode
          ? 'Where should the item come from?'
          : 'Choose your route',
      initialOrigin: bringMode ? _bringFrom : _origin,
      initialDestination: _destination,
      fromLabel: bringMode ? 'Item from' : 'From',
      toLabel: bringMode ? 'Deliver to' : 'To',
      geocodingProvider: ref.read(geocodingProvider),
      locationService: ref.read(locationServiceProvider),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (bringMode) {
        _bringFrom = result.origin.displayLabel;
      } else {
        _origin = result.origin.displayLabel;
      }
      _destination = result.destination.displayLabel;
    });
  }

  Future<void> _pickDate({required bool travel}) async {
    final now = DateTime.now();
    final initial = travel ? (_travelDate ?? now) : _sendDate;
    final safeInitial = initial.isBefore(now) ? now : initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText:
          travel ? 'Choose departure date' : 'When should the parcel travel?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (travel) {
        _travelDate = picked;
      } else {
        _sendDate = picked;
      }
    });
  }

  Future<void> _editBringItem() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BringItemSheet(
        initialValue:
            _bringItem == 'Describe the item or paste a Buy-for-Me URL'
                ? ''
                : _bringItem,
      ),
    );
    if (value != null && mounted) setState(() => _bringItem = value);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) return 'Today';
    if (target == today.add(const Duration(days: 1))) return 'Tomorrow';
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool get _hasRoute =>
      _origin != 'Current location' && _destination != 'Choose destination';
  bool get _hasBringRoute =>
      _bringFrom != 'Choose city' && _destination != 'Choose destination';
  bool get _hasBringItem =>
      _bringItem != 'Describe the item or paste a Buy-for-Me URL';

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
                    'ParcelPool',
                    style: ShipdeHopTypography.displayLarge.copyWith(fontSize: 27),
                  ),
                  const SizedBox(height: 4),
                  Text('Things can hop too.',
                      style: ShipdeHopTypography.bodyMedium),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E5F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        _tab(0, 'Send Parcel'),
                        _tab(1, 'Bring Item'),
                        _tab(2, "I'm Travelling"),
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
                children: [_sendView(), _bringView(), _travelView()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, String label) {
    final selected = _selectedModeIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedModeIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: 180.ms,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? ShipdeHopColors.textPrimary
                  : ShipdeHopColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendView() {
    final selectedSize = _parcelSizes[_selectedParcelSize];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        _routePanel(
          rows: [
            _RouteRow(
              'FROM',
              _origin,
              Icons.circle,
              ShipdeHopColors.success,
              () => _pickRoute(),
            ),
            _RouteRow(
              'TO',
              _destination,
              Icons.location_on_rounded,
              ShipdeHopColors.squirrelOrange,
              () => _pickRoute(),
            ),
            _RouteRow(
              'WHEN',
              _formatDate(_sendDate),
              Icons.calendar_month_rounded,
              ShipdeHopColors.brandPrimary,
              () => _pickDate(travel: false),
              key: const Key('send_date_row'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Parcel size',
          style: ShipdeHopTypography.labelMedium.copyWith(
            color: ShipdeHopColors.textSecondary,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: List.generate(_parcelSizes.length * 2 - 1, (index) {
            if (index.isOdd) return const SizedBox(width: 8);
            final sizeIndex = index ~/ 2;
            final size = _parcelSizes[sizeIndex];
            return _sizePill(
              size.$1,
              size.$2,
              sizeIndex,
              _selectedParcelSize == sizeIndex,
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Selected: ${selectedSize.$1} · ${selectedSize.$2}',
          style: ShipdeHopTypography.bodySmall,
        ),
        const SizedBox(height: 12),
        ShdPrimaryButton(
          label: 'Continue to parcel details',
          icon: Icons.arrow_forward_rounded,
          onPressed: _hasRoute
              ? () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HopShipScreen(
                        prefilledPickup: _origin,
                        prefilledDropoff: _destination,
                      ),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: 14),
        _protectionStrip(),
        const SizedBox(height: 22),
        Text(
          'Travellers near you',
          style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(
          'Real matching travellers will appear after you confirm your route and parcel details.',
          style: ShipdeHopTypography.bodyMedium,
        ),
        const SizedBox(height: 12),
        _emptyOpportunity(
          icon: Icons.route_rounded,
          title: 'No traveller matches yet',
          subtitle:
              'Complete the parcel details to search live ParcelPool capacity.',
        ),
      ],
    );
  }

  Widget _bringView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        _routePanel(
          rows: [
            _RouteRow(
              'FROM WHERE?',
              _bringFrom,
              Icons.flight_takeoff_rounded,
              ShipdeHopColors.brandPrimary,
              () => _pickRoute(bringMode: true),
            ),
            _RouteRow(
              'WHAT DO YOU NEED?',
              _bringItem,
              Icons.shopping_bag_outlined,
              ShipdeHopColors.brandPrimary,
              _editBringItem,
              key: const Key('bring_item_row'),
            ),
            _RouteRow(
              'DELIVER TO?',
              _destination,
              Icons.location_on_rounded,
              ShipdeHopColors.squirrelOrange,
              () => _pickRoute(bringMode: true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ShdPrimaryButton(
          label: 'Continue to Buy-for-Me details',
          icon: Icons.add_shopping_cart_rounded,
          onPressed: _hasBringRoute && _hasBringItem
              ? () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HopShipScreen(
                        prefilledPickup: _bringFrom,
                        prefilledDropoff: _destination,
                        initialBuyForMe: true,
                      ),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: 22),
        Text(
          'Popular requested cities',
          style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 4),
        Text(
          'Live corridor activity will appear here when there is real demand.',
          style: ShipdeHopTypography.bodyMedium,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: ShipdeHopColors.brandPrimaryLight,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const ShipdeHopMascot(
                pose: MascotPose.carryParcel,
                motion: MascotMotion.none,
                size: 58,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Be specific about brand, size and quantity so travellers know exactly what to bring.',
                  style: ShipdeHopTypography.bodySmall.copyWith(
                    color: const Color(0xFF3A1FD1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _travelView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      children: [
        _routePanel(
          rows: [
            _RouteRow(
              'ORIGIN',
              _origin,
              Icons.circle,
              ShipdeHopColors.success,
              () => _pickRoute(),
            ),
            _RouteRow(
              'DESTINATION',
              _destination,
              Icons.location_on_rounded,
              ShipdeHopColors.squirrelOrange,
              () => _pickRoute(),
            ),
            _RouteRow(
              'DATE',
              _travelDate == null
                  ? 'Choose departure'
                  : _formatDate(_travelDate!),
              Icons.calendar_month_rounded,
              ShipdeHopColors.brandPrimary,
              () => _pickDate(travel: true),
              key: const Key('travel_date_row'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _metric('SPACE', 'Set next', Icons.work_outline_rounded)),
            const SizedBox(width: 8),
            Expanded(
              child: _metric(
                'SEATS',
                'Optional',
                Icons.airline_seat_recline_normal_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ShdPrimaryButton(
          label: 'Continue to journey details',
          icon: Icons.add_road_rounded,
          onPressed: _hasRoute && _travelDate != null
              ? () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CreateJourneyScreen(
                        initialPassengers: true,
                        initialParcels: true,
                        initialShopping: true,
                        initialOriginLabel: _origin,
                        initialDestinationLabel: _destination,
                        initialDepartureDate: _travelDate,
                      ),
                    ),
                  )
              : null,
        ),
        const SizedBox(height: 22),
        Text(
          'Demand along your route',
          style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(
          'Parcel rewards and shared seats can help offset trip costs when live demand exists.',
          style: ShipdeHopTypography.bodyMedium,
        ),
        const SizedBox(height: 12),
        _emptyOpportunity(
          icon: Icons.inventory_2_outlined,
          title: 'No live demand on this route yet',
          subtitle:
              'Publish your journey and ShipdeHop will surface matching requests when they appear.',
        ),
      ],
    );
  }

  Widget _routePanel({required List<_RouteRow> rows}) {
    return Container(
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
        children: List.generate(rows.length, (index) {
          final r = rows[index];
          return Column(
            children: [
              InkWell(
                key: r.key,
                onTap: r.onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 66),
                  child: Row(
                    children: [
                      Icon(r.icon, size: 17, color: r.iconColor),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.label,
                              style: ShipdeHopTypography.labelSmall.copyWith(
                                fontSize: 11,
                                letterSpacing: .6,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              r.value,
                              style: ShipdeHopTypography.titleSmall.copyWith(
                                fontSize: 15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (r.onTap != null)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: ShipdeHopColors.textMuted,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
              if (index < rows.length - 1)
                const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
            ],
          );
        }),
      ),
    );
  }

  Widget _sizePill(String title, String subtitle, int index, bool selected) {
    return Expanded(
      child: InkWell(
        key: Key('parcel_size_$title'),
        onTap: () => setState(() => _selectedParcelSize = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 56,
          decoration: BoxDecoration(
            color: selected ? ShipdeHopColors.brandDark : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? ShipdeHopColors.brandDark
                  : ShipdeHopColors.borderLight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : ShipdeHopColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white70 : ShipdeHopColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
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
        ],
      ),
    );
  }

  Widget _protectionStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ShipdeHopColors.successBg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_rounded,
            color: ShipdeHopColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'HopShield safety checks are active. HopPay is coming soon in this beta.',
              style: ShipdeHopTypography.bodySmall.copyWith(
                color: ShipdeHopColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyOpportunity({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ShipdeHopColors.brandPrimaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: ShipdeHopColors.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 5),
                Text(subtitle, style: ShipdeHopTypography.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BringItemSheet extends StatefulWidget {
  const _BringItemSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_BringItemSheet> createState() => _BringItemSheetState();
}

class _BringItemSheetState extends State<_BringItemSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What do you need?', style: ShipdeHopTypography.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Describe the product clearly or paste a product URL.',
                style: ShipdeHopTypography.bodyMedium,
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('bring_item_input'),
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Example: 2 boxes of Mysore Pak, 500g each',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  final clean = _controller.text.trim();
                  if (clean.isNotEmpty) Navigator.pop(context, clean);
                },
                child: const Text('Use this item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteRow {
  const _RouteRow(
    this.label,
    this.value,
    this.icon,
    this.iconColor,
    this.onTap, {
    this.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final Key? key;
}
