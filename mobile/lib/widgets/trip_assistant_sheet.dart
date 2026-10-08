import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';

class TripQuery {
  const TripQuery({
    required this.raw,
    this.origin,
    this.destination,
    this.dateText,
  });

  final String raw;
  final String? origin;
  final String? destination;
  final String? dateText;

  static TripQuery parse(String input) {
    final raw = input.trim();
    String? origin;
    String? destination;
    String? dateText;

    final route = RegExp(
      r'from\s+(.+?)\s+to\s+(.+?)(?=\s+(?:on|at|by|with|using|via)\b|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (route != null) {
      origin = route.group(1)?.trim();
      destination = route.group(2)?.trim();
    } else {
      final loose = RegExp(
        r'\b([A-Za-z][A-Za-z .-]{1,40})\s+to\s+([A-Za-z][A-Za-z .-]{1,40})(?=\s+(?:on|at|by|with|using|via)\b|$)',
        caseSensitive: false,
      ).firstMatch(raw);
      origin = loose?.group(1)?.trim();
      destination = loose?.group(2)?.trim();
    }

    final date = RegExp(
      r'\bon\s+(.+?)(?=\s+(?:with|using|via|for)\b|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    dateText = date?.group(1)?.trim();

    return TripQuery(raw: raw, origin: origin, destination: destination, dateText: dateText);
  }
}

class TripAssistantSheet extends StatefulWidget {
  const TripAssistantSheet({
    super.key,
    required this.initialQuery,
    required this.onOpenParcelPool,
    required this.onOpenCarPool,
  });

  final String initialQuery;
  final void Function(String origin, String destination) onOpenParcelPool;
  final void Function(String origin, String destination) onOpenCarPool;

  static Future<void> show(
    BuildContext context, {
    required String query,
    required void Function(String origin, String destination) onOpenParcelPool,
    required void Function(String origin, String destination) onOpenCarPool,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TripAssistantSheet(
        initialQuery: query,
        onOpenParcelPool: onOpenParcelPool,
        onOpenCarPool: onOpenCarPool,
      ),
    );
  }

  @override
  State<TripAssistantSheet> createState() => _TripAssistantSheetState();
}

class _TripAssistantSheetState extends State<TripAssistantSheet> {
  static const _recentKey = 'shipdehop_recent_assistant_queries';

  late final TextEditingController _originController;
  late final TextEditingController _destinationController;
  late final TextEditingController _dateController;
  String? _transportMode;
  int _travellers = 1;
  List<String> _recentQueries = const [];

  static const _modes = [
    ('Car', Icons.directions_car_rounded),
    ('Bus', Icons.directions_bus_rounded),
    ('Train', Icons.train_rounded),
    ('Flight', Icons.flight_rounded),
    ('Bike', Icons.two_wheeler_rounded),
    ('Other', Icons.route_rounded),
  ];

  @override
  void initState() {
    super.initState();
    final parsed = TripQuery.parse(widget.initialQuery);
    _originController = TextEditingController(text: parsed.origin ?? '');
    _destinationController = TextEditingController(text: parsed.destination ?? '');
    _dateController = TextEditingController(text: parsed.dateText ?? '');
    _loadRecentQueries();
    _rememberQuery(widget.initialQuery);
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recentQueries = prefs.getStringList(_recentKey) ?? const []);
  }

  Future<void> _rememberQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_recentKey) ?? const <String>[];
    final updated = <String>[clean, ...existing.where((e) => e != clean)].take(5).toList();
    await prefs.setStringList(_recentKey, updated);
    if (mounted) setState(() => _recentQueries = updated);
  }

  bool get _routeReady => _originController.text.trim().isNotEmpty && _destinationController.text.trim().isNotEmpty;
  bool get _canRecommend => _routeReady && _transportMode != null;
  bool get _carpoolRelevant => _transportMode == 'Car';

  String get _recommendationTitle {
    if (!_canRecommend) return 'Tell me a little more';
    if (_carpoolRelevant) return 'Combine ParcelPool + CarPool';
    return 'Use ParcelPool along this trip';
  }

  String get _recommendationBody {
    if (!_routeReady) return 'Confirm your origin and destination first.';
    if (_transportMode == null) return 'Choose how you are travelling so ShipdeHop can suggest the right earning and cost-sharing options.';
    if (_carpoolRelevant) {
      return 'You can carry parcels and also share empty seats on the same route. Matching parcel rewards and seat contributions can offset a meaningful share of your travel cost, and strong demand can sometimes cover more. Exact savings and earnings depend on real matches.';
    }
    return 'ShipdeHop can look for parcels and Buy-for-Me requests that fit your route. Matching rewards can help offset your travel cost. Exact savings and earnings depend on real demand and available matches.';
  }

  void _openParcelPool() {
    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();
    if (origin.isEmpty || destination.isEmpty) return;
    Navigator.pop(context);
    widget.onOpenParcelPool(origin, destination);
  }

  void _openCarPool() {
    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();
    if (origin.isEmpty || destination.isEmpty) return;
    Navigator.pop(context);
    widget.onOpenCarPool(origin, destination);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + keyboard),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(color: ShipdeHopColors.borderLight, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_rounded, color: ShipdeHopColors.brandPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ShipdeHop Trip Assistant', style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 20)),
                    Text('Turn one trip into parcels, rides and savings.', style: ShipdeHopTypography.bodySmall),
                  ],
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: ShipdeHopColors.surfaceSubtle, borderRadius: BorderRadius.circular(16)),
                  child: Text('“${widget.initialQuery.trim()}”', style: ShipdeHopTypography.bodyMedium.copyWith(fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 16),
                Text('1. Confirm your trip', style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _textField(_originController, 'From', Icons.trip_origin_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: _textField(_destinationController, 'To', Icons.location_on_outlined)),
                  ],
                ),
                const SizedBox(height: 8),
                _textField(_dateController, 'Date or timing (optional)', Icons.calendar_month_rounded),
                const SizedBox(height: 20),
                Text('2. How are you travelling?', style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _modes.map((mode) {
                    final selected = _transportMode == mode.$1;
                    return ChoiceChip(
                      key: Key('trip_mode_${mode.$1.toLowerCase()}'),
                      selected: selected,
                      avatar: Icon(mode.$2, size: 17, color: selected ? Colors.white : ShipdeHopColors.brandPrimary),
                      label: Text(mode.$1),
                      selectedColor: ShipdeHopColors.brandPrimary,
                      labelStyle: TextStyle(color: selected ? Colors.white : ShipdeHopColors.textPrimary, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _transportMode = mode.$1),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text('3. How many people are travelling?', style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: ShipdeHopColors.borderLight), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.group_outlined, color: ShipdeHopColors.brandPrimary),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Travellers')),
                      IconButton(
                        onPressed: _travellers > 1 ? () => setState(() => _travellers--) : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      Text('$_travellers', style: ShipdeHopTypography.titleMedium),
                      IconButton(
                        onPressed: _travellers < 8 ? () => setState(() => _travellers++) : null,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _canRecommend ? ShipdeHopColors.brandPrimaryLight : ShipdeHopColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _canRecommend ? ShipdeHopColors.brandPrimary.withValues(alpha: .25) : ShipdeHopColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_canRecommend ? Icons.lightbulb_rounded : Icons.tips_and_updates_outlined, color: ShipdeHopColors.brandPrimary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_recommendationTitle, style: ShipdeHopTypography.titleSmall)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_recommendationBody, style: ShipdeHopTypography.bodyMedium),
                      if (_canRecommend) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Route: ${_originController.text.trim()} → ${_destinationController.text.trim()}${_dateController.text.trim().isEmpty ? '' : ' · ${_dateController.text.trim()}'} · $_travellers traveller${_travellers == 1 ? '' : 's'} · $_transportMode',
                          style: ShipdeHopTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: ShipdeHopColors.brandPrimary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_recentQueries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Recent trip searches', style: ShipdeHopTypography.titleSmall),
                  const SizedBox(height: 6),
                  ..._recentQueries.take(3).map((q) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded, color: ShipdeHopColors.textMuted),
                        title: Text(q, maxLines: 2, overflow: TextOverflow.ellipsis),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('trip_assistant_parcelpool_button'),
            onPressed: _canRecommend ? _openParcelPool : null,
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(_carpoolRelevant ? 'Find parcels for this trip' : 'Open ParcelPool for this trip'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: ShipdeHopColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          if (_carpoolRelevant) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('trip_assistant_carpool_button'),
              onPressed: _canRecommend ? _openCarPool : null,
              icon: const Icon(Icons.directions_car_rounded),
              label: const Text('Add CarPool seat sharing too'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: ShipdeHopColors.brandPrimary,
                side: const BorderSide(color: ShipdeHopColors.brandPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: ShipdeHopColors.brandPrimary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: ShipdeHopColors.borderLight)),
      ),
    );
  }
}
