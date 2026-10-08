import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile_preferences.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/profile/profile_components.dart';

class TravelPreferencesScreen extends ConsumerStatefulWidget {
  const TravelPreferencesScreen({super.key});

  @override
  ConsumerState<TravelPreferencesScreen> createState() => _TravelPreferencesScreenState();
}

class _TravelPreferencesScreenState extends ConsumerState<TravelPreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  String _mode = 'CAR';
  String _capacity = 'MEDIUM';
  double _detour = 5;
  bool _ladiesOnly = false;
  bool _verifiedOnly = true;
  bool _matchAlerts = true;

  ProfilePreferencesStore get _store => ProfilePreferencesStore(ref.read(currentUserIdProvider) ?? 'anonymous');

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final value = await _store.loadTravelPreferences();
    if (!mounted) return;
    setState(() {
      _mode = value.preferredMode;
      _capacity = value.parcelCapacity;
      _detour = value.maxDetourKm;
      _ladiesOnly = value.ladiesOnly;
      _verifiedOnly = value.verifiedOnly;
      _matchAlerts = value.matchAlerts;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _store.saveTravelPreferences(TravelPreferences(
      preferredMode: _mode,
      parcelCapacity: _capacity,
      maxDetourKm: _detour,
      ladiesOnly: _ladiesOnly,
      verifiedOnly: _verifiedOnly,
      matchAlerts: _matchAlerts,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Travel preferences saved.')));
  }

  @override
  Widget build(BuildContext context) {
    return ProfileDetailScaffold(
      title: 'Travel Preferences',
      children: [
        if (_loading)
          const ProfileLoadingCard(label: 'Loading preferences…')
        else ...[
          const ProfileSectionTitle('Journey defaults'),
          const SizedBox(height: 8),
          ProfileControlCard(children: [
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Preferred travel mode', prefixIcon: Icon(Icons.commute_rounded)),
              items: const [
                DropdownMenuItem(value: 'CAR', child: Text('Car')),
                DropdownMenuItem(value: 'TRAIN', child: Text('Train')),
                DropdownMenuItem(value: 'BUS', child: Text('Bus')),
                DropdownMenuItem(value: 'FLIGHT', child: Text('Flight')),
                DropdownMenuItem(value: 'OTHER', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _mode = value ?? 'CAR'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _capacity,
              decoration: const InputDecoration(labelText: 'Usual parcel capacity', prefixIcon: Icon(Icons.luggage_outlined)),
              items: const [
                DropdownMenuItem(value: 'NONE', child: Text('No parcel capacity')),
                DropdownMenuItem(value: 'ENVELOPE', child: Text('Envelope / documents')),
                DropdownMenuItem(value: 'MEDIUM', child: Text('Small box / medium bag')),
                DropdownMenuItem(value: 'LUGGAGE', child: Text('Large luggage')),
              ],
              onChanged: (value) => setState(() => _capacity = value ?? 'MEDIUM'),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Maximum matching detour', style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14))),
              Text('${_detour.round()} km', style: ShipdeHopTypography.labelMedium),
            ]),
            Slider(value: _detour.clamp(1, 25).toDouble(), min: 1, max: 25, divisions: 24, label: '${_detour.round()} km', onChanged: (value) => setState(() => _detour = value)),
          ]),
          const SizedBox(height: 18),
          const ProfileSectionTitle('Matching & comfort'),
          const SizedBox(height: 8),
          ProfileControlCard(children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _ladiesOnly,
              onChanged: (value) => setState(() => _ladiesOnly = value),
              title: const Text('Ladies-only preference'),
              subtitle: const Text('Prefer eligible women-only ride or travel matches where the feature is supported.'),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _verifiedOnly,
              onChanged: (value) => setState(() => _verifiedOnly = value),
              title: const Text('Prefer verified counterparties'),
              subtitle: const Text('Prioritise people with completed identity verification.'),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _matchAlerts,
              onChanged: (value) => setState(() => _matchAlerts = value),
              title: const Text('Match alerts'),
              subtitle: const Text('Keep notifications enabled for relevant route, parcel and ride matches.'),
            ),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save preferences'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 10),
          Text('These defaults are stored separately for each signed-in ShipdeHop account on this device. Parcel capacity and ladies-only defaults are applied when publishing a carrier route.', style: ShipdeHopTypography.bodySmall),
        ],
      ],
    );
  }
}
