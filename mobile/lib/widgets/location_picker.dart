import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/geocoding_provider.dart';
import '../core/launch_market.dart';
import '../core/location_favorites.dart';
import '../core/location_service.dart';
import '../core/profile_preferences.dart';
import '../models/confirmed_location.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import 'location_map_confirmation_widget.dart';

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.title,
    this.initialQuery,
    this.initialLocation,
    required this.onLocationConfirmed,
    required this.geocodingProvider,
    required this.locationService,
  });

  final String title;
  final String? initialQuery;
  final ConfirmedLocation? initialLocation;
  final void Function(ConfirmedLocation location) onLocationConfirmed;
  final GeocodingProvider geocodingProvider;
  final LocationService locationService;

  static Future<ConfirmedLocation?> show(
    BuildContext context, {
    String title = 'Search location',
    String? initialQuery,
    ConfirmedLocation? initialLocation,
    required GeocodingProvider geocodingProvider,
    required LocationService locationService,
  }) {
    return showModalBottomSheet<ConfirmedLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _LocationSearchModal(
        title: title,
        initialQuery: initialQuery,
        geocodingProvider: geocodingProvider,
        locationService: locationService,
        onSelected: (selected) async {
          final confirmed = await Navigator.of(sheetContext).push<ConfirmedLocation>(
            MaterialPageRoute<ConfirmedLocation>(
              builder: (mapContext) => LocationMapConfirmationWidget(
                initialLocation: selected,
                geocodingProvider: geocodingProvider,
                onConfirmed: (location) => Navigator.pop(mapContext, location),
                onCancel: () => Navigator.pop(mapContext),
              ),
            ),
          );
          if (confirmed != null && sheetContext.mounted) {
            Navigator.pop(sheetContext, confirmed);
          }
        },
      ),
    );
  }

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  ConfirmedLocation? _confirmedLocation;

  @override
  void initState() {
    super.initState();
    _confirmedLocation = widget.initialLocation;
  }

  @override
  void didUpdateWidget(LocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLocation != oldWidget.initialLocation) {
      _confirmedLocation = widget.initialLocation;
    }
  }

  Future<void> _openSearchSheet() async {
    final confirmed = await LocationPicker.show(
      context,
      title: widget.title,
      initialQuery: widget.initialQuery,
      initialLocation: widget.initialLocation,
      geocodingProvider: widget.geocodingProvider,
      locationService: widget.locationService,
    );
    if (confirmed == null || !mounted) return;
    setState(() => _confirmedLocation = confirmed);
    widget.onLocationConfirmed(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _confirmedLocation != null &&
        LaunchMarket.isSupportedLocation(_confirmedLocation!);

    return InkWell(
      onTap: _openSearchSheet,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasLocation
                ? ShipdeHopColors.brandPrimary
                : ShipdeHopColors.borderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
          color: hasLocation
              ? ShipdeHopColors.brandPrimaryLight
              : ShipdeHopColors.surfaceCard,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hasLocation
                    ? ShipdeHopColors.brandPrimary
                    : ShipdeHopColors.surfaceSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasLocation ? Icons.location_on_rounded : Icons.search_rounded,
                color: hasLocation
                    ? ShipdeHopColors.textOnPrimary
                    : ShipdeHopColors.brandPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: ShipdeHopTypography.labelSmall.copyWith(
                      color: hasLocation
                          ? ShipdeHopColors.brandPrimary
                          : ShipdeHopColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasLocation
                        ? _confirmedLocation!.displayLabel
                        : (widget.initialQuery ??
                            'Search city, area, landmark or address'),
                    style: ShipdeHopTypography.titleMedium.copyWith(
                      fontWeight: hasLocation ? FontWeight.w700 : FontWeight.w500,
                      color: hasLocation
                          ? ShipdeHopColors.textPrimary
                          : ShipdeHopColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasLocation)
                    Text(
                      _confirmedLocation!.formattedAddress,
                      style: ShipdeHopTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ShipdeHopColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationSearchModal extends StatefulWidget {
  const _LocationSearchModal({
    required this.title,
    this.initialQuery,
    required this.geocodingProvider,
    required this.locationService,
    required this.onSelected,
  });

  final String title;
  final String? initialQuery;
  final GeocodingProvider geocodingProvider;
  final LocationService locationService;
  final Future<void> Function(ConfirmedLocation location) onSelected;

  @override
  State<_LocationSearchModal> createState() => _LocationSearchModalState();
}

class _LocationSearchModalState extends State<_LocationSearchModal> {
  static const _recentKey = 'shipdehop_recent_locations';

  late final TextEditingController _searchController;
  List<ConfirmedLocation> _suggestions = const [];
  List<String> _recentLabels = const [];
  List<SavedPlaceRecord> _savedPlaces = const [];
  bool _searching = false;
  bool _locating = false;
  bool _openingMap = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _loadPersonalLocations();
    _performSearch(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonalLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await LocationFavorites.load();
      final storedRecents = prefs.getStringList(_recentKey) ?? const <String>[];
      final validRecents = <String>[];
      for (final label in storedRecents.take(8)) {
        final matches = await widget.geocodingProvider.search(label);
        if (matches.any(LaunchMarket.isSupportedLocation)) {
          validRecents.add(label);
        }
      }
      if (!mounted) return;
      setState(() {
        _savedPlaces = saved;
        _recentLabels = validRecents.take(6).toList();
      });
      if (validRecents.length != storedRecents.length) {
        await prefs.setStringList(_recentKey, validRecents.take(6).toList());
      }
    } catch (_) {
      // Saved/recent places are conveniences; never block core location search.
    }
  }

  Future<void> _remember(ConfirmedLocation location) async {
    if (!LaunchMarket.isSupportedLocation(location)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = <String>[
        location.displayLabel,
        ..._recentLabels.where((e) => e != location.displayLabel),
      ].take(6).toList();
      await prefs.setStringList(_recentKey, updated);
      if (mounted) setState(() => _recentLabels = updated);
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _performSearch(String query) async {
    if (mounted) {
      setState(() {
        _searching = true;
        _errorMessage = null;
      });
    }
    try {
      final results = await widget.geocodingProvider.search(query.trim());
      if (mounted) {
        setState(() {
          _suggestions = results.where(LaunchMarket.isSupportedLocation).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not search places. Try again.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _select(ConfirmedLocation location) async {
    if (_openingMap || !mounted) return;
    if (!LaunchMarket.isSupportedLocation(location)) {
      setState(() => _errorMessage = LaunchMarket.unsupportedMessage);
      return;
    }
    setState(() {
      _openingMap = true;
      _errorMessage = null;
    });
    try {
      final mapFlow = widget.onSelected(location);
      _remember(location);
      await mapFlow;
    } finally {
      if (mounted) setState(() => _openingMap = false);
    }
  }

  Future<void> _selectRecent(String label) async {
    try {
      final results = await widget.geocodingProvider.search(label);
      final matches = results.where(LaunchMarket.isSupportedLocation).toList();
      if (matches.isNotEmpty) {
        await _select(matches.first);
      } else if (mounted) {
        setState(() => _errorMessage =
            'That recent place is outside the India launch area. Search again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage =
            'Could not reopen that recent place. Search again.');
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _errorMessage = null;
    });
    try {
      final currentLocation = await widget.locationService.getCurrentLocation();
      await _select(currentLocation);
    } on LocationServiceException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage =
            'Current location is unavailable. Search for an Indian city instead.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.90;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
          child: Column(
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 23),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: ShipdeHopColors.brandPrimaryLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'INDIA',
                      style: TextStyle(
                        color: ShipdeHopColors.brandPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _openingMap ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('location_search_field'),
                controller: _searchController,
                autofocus: true,
                enabled: !_openingMap,
                style: ShipdeHopTypography.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search city, area, landmark or address in India',
                  hintStyle: ShipdeHopTypography.bodyMedium.copyWith(
                    color: ShipdeHopColors.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: ShipdeHopColors.brandPrimary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: _openingMap
                              ? null
                              : () {
                                  _searchController.clear();
                                  _performSearch('');
                                  setState(() {});
                                },
                        )
                      : null,
                  filled: true,
                  fillColor: ShipdeHopColors.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  _performSearch(value);
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _locating || _openingMap ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: const Text('Use my current location'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: ShipdeHopColors.brandPrimary,
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: ShipdeHopColors.error,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    if (_savedPlaces.isNotEmpty) ...[
                      Text('Saved places', style: ShipdeHopTypography.titleSmall),
                      const SizedBox(height: 6),
                      ..._savedPlaces.map(
                        (place) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.star_rounded,
                            color: ShipdeHopColors.squirrelOrange,
                          ),
                          title: Text(place.label, style: ShipdeHopTypography.titleSmall),
                          subtitle: Text(
                            place.location.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _openingMap ? null : () => _select(place.location),
                        ),
                      ),
                      const Divider(),
                    ],
                    if (_recentLabels.isNotEmpty) ...[
                      Text('Recent searches', style: ShipdeHopTypography.titleSmall),
                      const SizedBox(height: 6),
                      ..._recentLabels.map(
                        (label) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.history_rounded,
                            color: ShipdeHopColors.textMuted,
                          ),
                          title: Text(label, style: ShipdeHopTypography.bodyLarge),
                          trailing: const Icon(
                            Icons.north_west_rounded,
                            size: 17,
                            color: ShipdeHopColors.textMuted,
                          ),
                          onTap: _openingMap ? null : () => _selectRecent(label),
                        ),
                      ),
                      const Divider(),
                    ],
                    Text(
                      _searchController.text.trim().isEmpty
                          ? 'Popular places in India'
                          : 'Search results',
                      style: ShipdeHopTypography.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_suggestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No matching places in India yet.',
                          style: ShipdeHopTypography.bodyMedium,
                        ),
                      )
                    else
                      ..._suggestions.map(
                        (place) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.location_city_rounded,
                            color: ShipdeHopColors.brandPrimary,
                          ),
                          title: Text(
                            place.displayLabel,
                            style: ShipdeHopTypography.titleSmall,
                          ),
                          subtitle: Text(
                            place.formattedAddress,
                            style: ShipdeHopTypography.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _openingMap ? null : () => _select(place),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}