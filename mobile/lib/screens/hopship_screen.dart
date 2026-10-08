import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../core/policy_resolver.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../providers/app_providers.dart';
import '../providers/hopship_provider.dart';
import '../widgets/contextual_help_button.dart';
import '../widgets/date_flexibility_picker.dart';
import '../widgets/escrow_breakdown.dart';
import '../widgets/location_picker.dart';
import '../widgets/policy_summary_card.dart';
import '../widgets/route_preview_widget.dart';
import 'create_journey_screen.dart';

class HopShipScreen extends ConsumerStatefulWidget {
  const HopShipScreen({
    super.key,
    this.prefilledPickup,
    this.prefilledDropoff,
    this.initialBuyForMe = false,
  });

  final String? prefilledPickup;
  final String? prefilledDropoff;
  final bool initialBuyForMe;

  @override
  ConsumerState<HopShipScreen> createState() => _HopShipScreenState();
}

class _HopShipScreenState extends ConsumerState<HopShipScreen> {
  final _formKey = GlobalKey<FormState>();
  late bool buyForMe;
  bool _prohibitedItemsConfirmed = false;

  ConfirmedLocation? _pickupLoc;
  ConfirmedLocation? _dropLoc;
  DateFlexibility _timingFlexibility = DateFlexibility(
    earliestDateTime: DateTime.now().add(const Duration(hours: 1)),
    latestDateTime: DateTime.now().add(const Duration(days: 2)),
    isFlexible: true,
    flexibilityWindowHours: 24,
  );

  final productUrl = TextEditingController();
  final declared = TextEditingController(text: '0');
  final reward = TextEditingController();
  final weight = TextEditingController();
  final currency = TextEditingController(text: 'INR');
  final pickupName = TextEditingController();
  final pickupLat = TextEditingController();
  final pickupLon = TextEditingController();
  final dropName = TextEditingController();
  final dropLat = TextEditingController();
  final dropLon = TextEditingController();

  XFile? _selectedImageFile;

  @override
  void initState() {
    super.initState();
    buyForMe = widget.initialBuyForMe;
  }

  @override
  void dispose() {
    for (final c in [
      productUrl,
      declared,
      reward,
      weight,
      currency,
      pickupName,
      pickupLat,
      pickupLon,
      dropName,
      dropLat,
      dropLon
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _calculateBreakdown() async {
    final dv = double.tryParse(declared.text.trim());
    final rw = double.tryParse(reward.text.trim());
    if (dv == null || rw == null || rw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid declared value and positive reward amount.')),
      );
      return;
    }

    try {
      await ref.read(hopShipNotifierProvider.notifier).calculateQuote(
            isBuyForMe: buyForMe,
            declaredValue: dv,
            rewardAmount: rw,
            currency: currency.text.trim(),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pricing error: $e')));
      }
    }
  }

  Future<ImageSource?> _chooseImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take inspection photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose photo from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final source = await _chooseImageSource();
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file != null) {
      setState(() {
        _selectedImageFile = file;
      });
    }
  }

  Future<void> _createAndInspectShipment() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_prohibitedItemsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must confirm that this parcel does not contain prohibited or dangerous items.')),
      );
      return;
    }
    if (_selectedImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or capture a parcel inspection photo for HopShield scan.')),
      );
      return;
    }

    final dv = double.parse(declared.text.trim());
    final rw = double.parse(reward.text.trim());
    final kg = double.parse(weight.text.trim());
    final pLat = double.parse(pickupLat.text.trim());
    final pLon = double.parse(pickupLon.text.trim());
    final dLat = double.parse(dropLat.text.trim());
    final dLon = double.parse(dropLon.text.trim());

    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(hopShipNotifierProvider.notifier);

    try {
      final task = await notifier.createDraftTask(
        isBuyForMe: buyForMe,
        productUrl: buyForMe ? productUrl.text.trim() : null,
        declaredValue: dv,
        rewardAmount: rw,
        currency: currency.text.trim(),
        pickupName: pickupName.text.trim(),
        pickupLat: pLat,
        pickupLon: pLon,
        dropName: dropName.text.trim(),
        dropLat: dLat,
        dropLon: dLon,
        weightKg: kg,
      );

      final taskId = task['id'].toString();
      final bytes = await _selectedImageFile!.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('Image is too large. Please select a smaller photo.');
      }

      final lowerPath = _selectedImageFile!.path.toLowerCase();
      final mime = _selectedImageFile!.mimeType ??
          (lowerPath.endsWith('.png')
              ? 'image/png'
              : lowerPath.endsWith('.webp')
                  ? 'image/webp'
                  : 'image/jpeg');

      final inspection = await notifier.inspectShipmentParcel(
        taskId: taskId,
        imageBytes: bytes,
        imageMimeType: mime,
      );

      if (!mounted) return;

      if (inspection.decision == 'APPROVED') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Safety checks passed. Parcel is OPEN and visible for carrier matching.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Safety check result: ${inspection.decision}. Request saved as DRAFT.'),
            backgroundColor: Colors.amber.shade900,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Submission error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hopShipNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(buyForMe ? 'Buy-for-Me Request' : 'Send a Parcel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.teal),
            onPressed: () => ContextualHelpButton.showHelpModal(context, 'parcelpool'),
          ),
          if (state.createdTask != null || state.inspectionResult != null)
            IconButton(
              tooltip: 'Reset Form',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _selectedImageFile = null;
                });
                ref.read(hopShipNotifierProvider.notifier).reset();
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('Send (Shipster)'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.shopping_bag_outlined),
                  label: Text('Request an item'),
                ),
              ],
              selected: {buyForMe},
              onSelectionChanged: (val) => setState(() => buyForMe = val.first),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.indigo.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.indigo),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Are you travelling?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Publish a journey to carry parcels, passengers & shopping requests.', style: TextStyle(fontSize: 11, color: Colors.black87)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(builder: (_) => const CreateJourneyScreen(initialParcels: true)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text('Publish Journey', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (buyForMe) ...[
              TextFormField(
                controller: productUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Product URL',
                  hintText: 'https://example.com/product/123',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: (v) {
                  if (buyForMe) {
                    if (v == null || v.trim().isEmpty) return 'Product URL is required for Buy-for-Me';
                    if (!v.trim().startsWith('https://')) return 'Must be a valid HTTPS URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: declared,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: buyForMe ? 'Product value' : 'Declared value',
                      prefixIcon: const Icon(Icons.attach_money),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: reward,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Traveller reward',
                      prefixIcon: Icon(Icons.card_giftcard),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter reward (> 0)';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      prefixIcon: Icon(Icons.scale),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter weight (> 0)';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: currency,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      hintText: 'INR',
                      prefixIcon: Icon(Icons.currency_exchange),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length != 3) return '3-letter code';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LocationPicker(
              title: 'Pickup Location',
              initialQuery: widget.prefilledPickup,
              geocodingProvider: ref.read(geocodingProvider),
              locationService: ref.read(locationServiceProvider),
              onLocationConfirmed: (loc) {
                setState(() => _pickupLoc = loc);
                pickupName.text = loc.displayLabel;
                pickupLat.text = loc.latitude.toString();
                pickupLon.text = loc.longitude.toString();
              },
            ),
            const SizedBox(height: 12),
            LocationPicker(
              title: 'Drop-off Location',
              initialQuery: widget.prefilledDropoff,
              geocodingProvider: ref.read(geocodingProvider),
              locationService: ref.read(locationServiceProvider),
              onLocationConfirmed: (loc) {
                setState(() => _dropLoc = loc);
                dropName.text = loc.displayLabel;
                dropLat.text = loc.latitude.toString();
                dropLon.text = loc.longitude.toString();
              },
            ),
            if (_pickupLoc != null && _dropLoc != null) ...[
              const SizedBox(height: 16),
              PolicySummaryCard(policy: PolicyResolver.resolvePolicy(_pickupLoc!, _dropLoc!)),
              const SizedBox(height: 16),
              RoutePreviewWidget(
                origin: _pickupLoc!,
                destination: _dropLoc!,
                onRouteConfirmed: (route) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Route confirmed (${route.formattedDistance}, ${route.formattedDuration})'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                onEditOrigin: () => setState(() => _pickupLoc = null),
                onEditDestination: () => setState(() => _dropLoc = null),
              ),
            ],
            const SizedBox(height: 16),
            DateFlexibilityPicker(
              title: 'Pickup & Delivery Timing Window',
              initialValue: _timingFlexibility,
              onChanged: (flex) => setState(() => _timingFlexibility = flex),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.isBusy ? null : _calculateBreakdown,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Estimate fees (HopPay coming soon)'),
            ),
            if (state.quote != null) ...[
              const SizedBox(height: 12),
              EscrowBreakdown(
                base: (state.quote!['base'] as num).toDouble(),
                reward: (state.quote!['reward'] as num).toDouble(),
                platformFee: (state.quote!['platformFee'] as num).toDouble(),
                currency: state.quote!['currency'].toString(),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'HopShield Parcel Safety Inspection',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_selectedImageFile == null) ...[
                      const Icon(Icons.add_a_photo_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('Photo required for HopShield vision scan before publishing.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Select / Take Parcel Photo'),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          const Icon(Icons.image, color: Colors.deepPurple),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedImageFile!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(onPressed: _pickImage, child: const Text('Change')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (state.inspectionResult != null) ...[
              const SizedBox(height: 16),
              _HopShieldResultCard(
                result: state.inspectionResult!,
                taskStatus: state.createdTask?['status']?.toString() ?? 'DRAFT',
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(state.error!, style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _prohibitedItemsConfirmed,
              onChanged: (v) => setState(() => _prohibitedItemsConfirmed = v ?? false),
              title: const Text(
                'I confirm this parcel does not contain prohibited or dangerous items (weapons, explosives, illegal drugs, hazardous chemicals, cash, or stolen goods).',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.isBusy ? null : _createAndInspectShipment,
              icon: state.isBusy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.shield_outlined),
              label: Text(
                state.isBusy
                    ? 'Performing parcel safety checks...'
                    : (buyForMe ? 'Submit Buy-for-Me & Scan' : 'Submit Parcel & Scan'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ShipdeHop performs the currently available parcel safety checks. The prohibited-item confirmation is a user declaration, not proof of contents. Exact pickup/drop coordinates are kept private until claimed by a matched traveller. Payments are disabled in this beta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _HopShieldResultCard extends StatelessWidget {
  const _HopShieldResultCard({
    required this.result,
    required this.taskStatus,
  });

  final HopShieldResult result;
  final String taskStatus;

  @override
  Widget build(BuildContext context) {
    final isApproved = result.decision == 'APPROVED';
    final isReview = result.decision == 'REVIEW';

    final badgeColor = isApproved
        ? Colors.green
        : isReview
            ? Colors.amber.shade900
            : Colors.red;

    final badgeIcon = isApproved
        ? Icons.check_circle_outline
        : isReview
            ? Icons.warning_amber_outlined
            : Icons.block_outlined;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: badgeColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(badgeIcon, color: badgeColor, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HopShield Decision: ${result.decision}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: badgeColor),
                      ),
                      Text(
                        'Shipment Status: ${isApproved ? 'OPEN / APPROVED' : taskStatus}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    '${(result.confidence * 100).toStringAsFixed(0)}% Match',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: badgeColor.withAlpha(30),
                ),
              ],
            ),
            const Divider(height: 20),
            Text('Rationale:', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(result.rationale),
            if (result.contentMismatch) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                child: const Row(
                  children: [
                    Icon(Icons.report_problem, size: 18, color: Colors.amber),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Content Mismatch Detected: Visible item may differ from declared request.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (result.prohibitedCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Flagged Categories:', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: result.prohibitedCategories
                    .map((cat) => Chip(label: Text(cat, style: const TextStyle(fontSize: 11)), backgroundColor: Colors.red.shade100))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            if (isApproved)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Safety checks passed. This request can proceed to eligible carrier matching.',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This request is kept in DRAFT state and is not visible to travellers until safety review clears.',
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
