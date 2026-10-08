import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile_preferences.dart';
import '../models/confirmed_location.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/location_picker.dart';
import '../widgets/profile/profile_components.dart';

class SavedPlacesScreen extends ConsumerStatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  ConsumerState<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends ConsumerState<SavedPlacesScreen> {
  List<SavedPlaceRecord> _places = const [];
  bool _loading = true;

  ProfilePreferencesStore get _store => ProfilePreferencesStore(ref.read(currentUserIdProvider) ?? 'anonymous');

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final places = await _store.loadSavedPlaces();
    if (mounted) setState(() { _places = places; _loading = false; });
  }

  Future<void> _edit({SavedPlaceRecord? existing}) async {
    final result = await Navigator.push<SavedPlaceRecord>(
      context,
      MaterialPageRoute<SavedPlaceRecord>(builder: (_) => _SavedPlaceEditor(existing: existing)),
    );
    if (result == null) return;
    final updated = [..._places];
    final index = updated.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      updated[index] = result;
    } else {
      updated.add(result);
    }
    await _store.saveSavedPlaces(updated);
    if (mounted) setState(() => _places = updated);
  }

  Future<void> _delete(SavedPlaceRecord place) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${place.label}?'),
        content: Text(place.location.formattedAddress),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    final updated = _places.where((item) => item.id != place.id).toList();
    await _store.saveSavedPlaces(updated);
    if (mounted) setState(() => _places = updated);
  }

  @override
  Widget build(BuildContext context) {
    return ProfileDetailScaffold(
      title: 'Saved Places',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: ShipdeHopColors.brandPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add place'),
      ),
      children: [
        Text('Save places you use often so you do not have to search for the address again.', style: ShipdeHopTypography.bodyMedium),
        const SizedBox(height: 16),
        if (_loading)
          const ProfileLoadingCard(label: 'Loading saved places…')
        else if (_places.isEmpty)
          const ProfileInfoCard(
            icon: Icons.bookmark_outline_rounded,
            title: 'No saved places yet',
            body: 'Add Home, Work, an airport, a pickup point or any location you use regularly.',
          )
        else
          ..._places.map((place) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: ListTile(
                  minTileHeight: 72,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(13)),
                    child: Icon(_placeIcon(place.label), color: ShipdeHopColors.brandPrimary),
                  ),
                  title: Text(place.label, style: ShipdeHopTypography.titleSmall),
                  subtitle: Text(place.location.formattedAddress, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _edit(existing: place),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _edit(existing: place);
                      if (value == 'delete') _delete(place);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 72),
      ],
    );
  }
}

class _SavedPlaceEditor extends ConsumerStatefulWidget {
  const _SavedPlaceEditor({this.existing});

  final SavedPlaceRecord? existing;

  @override
  ConsumerState<_SavedPlaceEditor> createState() => _SavedPlaceEditorState();
}

class _SavedPlaceEditorState extends ConsumerState<_SavedPlaceEditor> {
  late final TextEditingController _label;
  ConfirmedLocation? _location;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.existing?.label ?? '');
    _location = widget.existing?.location;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    if (label.length < 2 || _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a place name and confirm its location.')));
      return;
    }
    Navigator.pop(
      context,
      SavedPlaceRecord(
        id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        label: label,
        location: _location!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(title: Text(widget.existing == null ? 'Add saved place' : 'Edit saved place')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Home, Work, Airport…', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          LocationPicker(
            title: 'Location',
            initialLocation: _location,
            initialQuery: _location?.displayLabel,
            geocodingProvider: ref.read(geocodingProvider),
            locationService: ref.read(locationServiceProvider),
            onLocationConfirmed: (location) => setState(() => _location = location),
          ),
          if (_location != null) ...[
            const SizedBox(height: 12),
            ProfileInfoCard(icon: Icons.pin_drop_outlined, title: _location!.displayLabel, body: _location!.formattedAddress),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(widget.existing == null ? 'Save place' : 'Save changes'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
        ],
      ),
    );
  }
}

IconData _placeIcon(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('home')) return Icons.home_outlined;
  if (lower.contains('work') || lower.contains('office')) return Icons.work_outline_rounded;
  if (lower.contains('airport')) return Icons.flight_outlined;
  return Icons.place_outlined;
}
