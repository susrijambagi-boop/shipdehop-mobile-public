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

class RouteSelection {
  const RouteSelection({required this.origin, required this.destination});

  final ConfirmedLocation origin;
  final ConfirmedLocation destination;
}

class RouteLocationPicker extends StatefulWidget {
  const RouteLocationPicker({
    super.key,
    this.title = 'Search by city or area',
    this.initialOrigin,
    this.initialDestination,
    this.fromLabel = 'From',
    this.toLabel = 'To',
    required this.geocodingProvider,
    required this.locationService,
  });

  final String title;
  final String? initialOrigin;
  final String? initialDestination;
  final String fromLabel;
  final String toLabel;
  final GeocodingProvider geocodingProvider;
  final LocationService locationService;

  static Future<RouteSelection?> show(
    BuildContext context, {
    String title = 'Search by city or area',
    String? initialOrigin,
    String? initialDestination,
    String fromLabel = 'From',
    String toLabel = 'To',
    required GeocodingProvider geocodingProvider,
    required LocationService locationService,
  }) {
    return showModalBottomSheet<RouteSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RouteLocationPicker(
        title: title,
        initialOrigin: initialOrigin,
        initialDestination: initialDestination,
        fromLabel: fromLabel,
        toLabel: toLabel,
        geocodingProvider: geocodingProvider,
        locationService: locationService,
      ),
    );
  }

  @override
  State<RouteLocationPicker> createState() => _RouteLocationPickerState();
}

class _RouteLocationPickerState extends State<RouteLocationPicker> {
  static const _recentKey = 'shipdehop_recent_route_locations';

  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();

  int _activeField = 0;
  bool _searching = false;
  bool _locating = false;
  String? _errorMessage;
  ConfirmedLocation? _originSelection;
  ConfirmedLocation? _destinationSelection;
  List<ConfirmedLocation> _suggestions = const [];
  List<String> _recentLabels = const [];
  List<SavedPlaceRecord> _savedPlaces = const [];

  String _cleanInitial(String? value, String placeholder) {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty ||
        clean.toLowerCase() == placeholder.toLowerCase() ||
        clean.toLowerCase() == 'current location') {
      return '';
    }
    return clean;
  }

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(
      text: _cleanInitial(widget.initialOrigin, 'Choose origin'),
    );
    _toController = TextEditingController(
      text: _cleanInitial(widget.initialDestination, 'Choose destination'),
    );
    _fromFocus.addListener(() {
      if (_fromFocus.hasFocus) {
        setState(() => _activeField = 0);
        _performSearch(_fromController.text);
      }
    });
    _toFocus.addListener(() {
      if (_toFocus.hasFocus) {
        setState(() => _activeField = 1);
        _performSearch(_toController.text);
      }
    });
    _loadPersonalLocations();
    _performSearch('');
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPersonalLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await LocationFavorites.load();
      final raw = prefs.getStringList(_recentKey) ?? const <String>[];
      final valid = <String>[];
      for (final label in raw.take(8)) {
        final matches = await widget.geocodingProvider.search(label);
        if (matches.any(LaunchMarket.isSupportedLocation)) valid.add(label);
      }
      if (!mounted) return;
      setState(() {
        _savedPlaces = saved;
        _recentLabels = valid.take(6).toList();
      });
      if (valid.length != raw.length) {
        await prefs.setStringList(_recentKey, valid.take(6).toList());
      }
    } catch (_) {
      // Optional convenience data should never block route selection.
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
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _errorMessage = null;
    });
    try {
      final results = await widget.geocodingProvider.search(query.trim());
      if (mounted) {
        setState(() {
          _suggestions = results.where(LaunchMarket.isSupportedLocation).toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Could not search places. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectPlace(ConfirmedLocation place) async {
    if (!LaunchMarket.isSupportedLocation(place)) {
      setState(() => _errorMessage = LaunchMarket.unsupportedMessage);
      return;
    }
    _remember(place);
    if (!mounted) return;
    if (_activeField == 0) {
      setState(() {
        _originSelection = place;
        _fromController.text = place.displayLabel;
        _activeField = 1;
      });
      _toFocus.requestFocus();
      await _performSearch(_toController.text);
    } else {
      setState(() {
        _destinationSelection = place;
        _toController.text = place.displayLabel;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _errorMessage = null;
    });
    try {
      final location = await widget.locationService.getCurrentLocation();
      if (!LaunchMarket.isSupportedLocation(location)) {
        throw const LocationServiceException(
          LaunchMarket.unsupportedMessage,
          type: LocationErrorType.unsupportedRegion,
        );
      }
      _remember(location);
      if (!mounted) return;
      setState(() {
        _originSelection = location;
        _fromController.text = location.displayLabel;
        _activeField = 1;
      });
      _toFocus.requestFocus();
      await _performSearch(_toController.text);
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

  Future<ConfirmedLocation?> _resolveTyped(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) return null;
    final matches = await widget.geocodingProvider.search(clean);
    final valid = matches.where(LaunchMarket.isSupportedLocation).toList();
    return valid.isEmpty ? null : valid.first;
  }

  Future<void> _confirmRoute() async {
    setState(() => _errorMessage = null);
    final origin = _originSelection ?? await _resolveTyped(_fromController.text);
    final destination =
        _destinationSelection ?? await _resolveTyped(_toController.text);
    if (origin == null || destination == null) {
      if (mounted) {
        setState(() => _errorMessage =
            'Choose both origin and destination in India from the search results.');
      }
      return;
    }
    if (!LaunchMarket.isSupportedRoute(origin, destination)) {
      if (mounted) setState(() => _errorMessage = LaunchMarket.unsupportedMessage);
      return;
    }
    _remember(origin);
    _remember(destination);
    if (!mounted) return;
    Navigator.pop(
      context,
      RouteSelection(origin: origin, destination: destination),
    );
  }

  Future<void> _selectRecent(String label) async {
    final matches = await widget.geocodingProvider.search(label);
    final valid = matches.where(LaunchMarket.isSupportedLocation).toList();
    if (valid.isNotEmpty) await _selectPlace(valid.first);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final queryEmpty = _activeField == 0
        ? _fromController.text.trim().isEmpty
        : _toController.text.trim().isEmpty;

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
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _routeField(
            controller: _fromController,
            focusNode: _fromFocus,
            label: widget.fromLabel,
            active: _activeField == 0,
            icon: Icons.trip_origin_rounded,
            onChanged: (value) {
              _originSelection = null;
              if (_activeField == 0) _performSearch(value);
            },
          ),
          const SizedBox(height: 10),
          _routeField(
            controller: _toController,
            focusNode: _toFocus,
            label: widget.toLabel,
            active: _activeField == 1,
            icon: Icons.location_on_outlined,
            onChanged: (value) {
              _destinationSelection = null;
              if (_activeField == 1) _performSearch(value);
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: const Text('Use my current location for From'),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: ShipdeHopColors.brandPrimary,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: ShipdeHopColors.error,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              children: [
                if (queryEmpty && _savedPlaces.isNotEmpty) ...[
                  Text('Saved places', style: ShipdeHopTypography.titleSmall),
                  const SizedBox(height: 6),
                  ..._savedPlaces.map(
                    (saved) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.star_rounded,
                        color: ShipdeHopColors.squirrelOrange,
                      ),
                      title: Text(saved.label, style: ShipdeHopTypography.titleSmall),
                      subtitle: Text(
                        saved.location.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectPlace(saved.location),
                    ),
                  ),
                  const Divider(),
                ],
                if (queryEmpty && _recentLabels.isNotEmpty) ...[
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
                      onTap: () => _selectRecent(label),
                    ),
                  ),
                  const Divider(),
                ],
                Text(
                  queryEmpty ? 'Popular cities in India' : 'Search results',
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
                      onTap: () => _selectPlace(place),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _confirmRoute,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Use this route'),
              style: FilledButton.styleFrom(
                backgroundColor: ShipdeHopColors.brandPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required bool active,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onTap: () {
        setState(() => _activeField = identical(focusNode, _fromFocus) ? 0 : 1);
        _performSearch(controller.text);
      },
      onChanged: onChanged,
      style: ShipdeHopTypography.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'City, station, area or landmark',
        prefixIcon: Icon(
          icon,
          color: active
              ? ShipdeHopColors.brandPrimary
              : ShipdeHopColors.textSecondary,
        ),
        filled: true,
        fillColor: active
            ? ShipdeHopColors.brandPrimaryLight.withValues(alpha: .45)
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: ShipdeHopColors.brandPrimary,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}