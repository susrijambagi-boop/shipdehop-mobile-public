import 'dart:convert';
import '../core/currency_catalog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/money_formatter.dart';
import '../models/confirmed_location.dart';
import '../models/domain.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/location_picker.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/payment_review_modal.dart';
import '../widgets/ui/shd_image.dart';
import '../widgets/ui/shd_primary_button.dart';
import '../widgets/ui/shd_skeleton.dart';

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key, this.initialModeIndex = 0});

  final int initialModeIndex;

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  late int _selectedModeIndex;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  bool _myListingsOnly = false;

  static const _categories = <String>[
    'All',
    'Electronics',
    'Fashion',
    'Home & Garden',
    'Vehicles',
    'Books & Games',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedModeIndex = widget.initialModeIndex;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Marketplace', style: ShipdeHopTypography.displayLarge.copyWith(fontSize: 27)),
                    const SizedBox(height: 4),
                    Text('Buy nearby, or send it with a traveller.', style: ShipdeHopTypography.bodyMedium),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ShipdeHopColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _buildSegmentTab(0, 'Browse Market', Icons.storefront_rounded),
                    _buildSegmentTab(1, 'Sell an Item', Icons.sell_rounded),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedModeIndex,
                children: [
                  _buildMarketplaceBrowseView(context),
                  _SellItemView(
                    onListed: () {
                      ref.invalidate(marketplaceFeedProvider);
                      setState(() => _selectedModeIndex = 0);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label, IconData icon) {
    final isSelected = _selectedModeIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedModeIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? ShipdeHopColors.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 4, offset: Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? ShipdeHopColors.textPrimary : ShipdeHopColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarketplaceBrowseView(BuildContext context) {
    final feed = ref.watch(marketplaceFeedProvider);
    final userId = ref.watch(authUserProvider).value?.id;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: ShipdeHopTypography.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Search items, categories, locations...',
              hintStyle: ShipdeHopTypography.bodyMedium.copyWith(color: ShipdeHopColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: ShipdeHopColors.brandPrimary),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: ShipdeHopColors.surfaceCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (userId != null) ...[
                FilterChip(
                  label: const Text('My listings'),
                  selected: _myListingsOnly,
                  onSelected: (value) => setState(() => _myListingsOnly = value),
                  selectedColor: ShipdeHopColors.brandPrimaryLight,
                  checkmarkColor: ShipdeHopColors.brandPrimary,
                  side: BorderSide(
                    color: _myListingsOnly ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ..._categories.map((category) {
                final selected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    selectedColor: ShipdeHopColors.brandPrimaryLight,
                    backgroundColor: ShipdeHopColors.surfaceCard,
                    labelStyle: TextStyle(
                      color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    side: BorderSide(color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight),
                    onSelected: (_) => setState(() => _selectedCategory = category),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: ShipdeHopColors.brandPrimary,
            onRefresh: () async {
              ref.invalidate(marketplaceFeedProvider);
              await ref.read(marketplaceFeedProvider.future);
            },
            child: (const bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false) && feed.isLoading)
                ? GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: 4,
                    itemBuilder: (_, index) {
                      const sampleItems = [
                        MarketplaceCardModel(id: 'm1', sellerId: 's1', title: 'Mysore Silk Saree', description: 'Authentic silk saree from Mysore', price: 3500.0, currency: 'INR', category: 'Fashion', condition: 'NEW', locationName: 'Mysuru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 1, shipEligible: true, images: []),
                        MarketplaceCardModel(id: 'm2', sellerId: 's2', title: 'Terracotta Tea Set', description: 'Traditional 6-piece clay kulhad set', price: 850.0, currency: 'INR', category: 'Home & Garden', condition: 'NEW', locationName: 'Bengaluru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 3, shipEligible: true, images: []),
                        MarketplaceCardModel(id: 'm3', sellerId: 's3', title: 'Kindle Paperwhite', description: 'Like new condition with leather cover', price: 6200.0, currency: 'INR', category: 'Electronics', condition: 'LIKE_NEW', locationName: 'Bengaluru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 1, shipEligible: true, images: []),
                        MarketplaceCardModel(id: 'm4', sellerId: 's4', title: 'Brass Coffee Filter', description: 'Pure heavy brass 4-cup coffee filter set', price: 1200.0, currency: 'INR', category: 'Home & Garden', condition: 'NEW', locationName: 'Chennai, Tamil Nadu', jurisdictionCode: 'IN', availableQuantity: 2, shipEligible: true, images: []),
                      ];
                      return _MarketplaceCard(item: sampleItems[index], isMine: false, onTap: () {});
                    },
                  )
                : feed.when(
              loading: () => ShdSkeleton(
                enabled: true,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, _) => Container(
                    decoration: BoxDecoration(
                      color: ShipdeHopColors.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              error: (error, _) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 100),
                children: [
                  const Icon(Icons.storefront_outlined, size: 52, color: ShipdeHopColors.textMuted),
                  const SizedBox(height: 16),
                  Text('Marketplace could not load', textAlign: TextAlign.center, style: ShipdeHopTypography.titleLarge),
                  const SizedBox(height: 8),
                  Text('$error', textAlign: TextAlign.center, style: ShipdeHopTypography.bodySmall),
                  const SizedBox(height: 18),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => ref.invalidate(marketplaceFeedProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              ),
              data: (items) {
                final query = _searchController.text.trim().toLowerCase();
                final filtered = items.where((item) {
                  if (_myListingsOnly && item.sellerId != userId) return false;
                  if (_selectedCategory != 'All' && item.category != _selectedCategory) return false;
                  if (query.isEmpty) return true;
                  return '${item.title} ${item.description} ${item.category} ${item.locationName}'
                      .toLowerCase()
                      .contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 42, 24, 120),
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              width: 184,
                              height: 84,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE4DFF2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 26),
                              child: ShipdeHopMascot(pose: MascotPose.idle, motion: MascotMotion.none, size: 118),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        items.isEmpty ? 'Nothing nearby yet' : 'No matching listings',
                        textAlign: TextAlign.center,
                        style: ShipdeHopTypography.displayMedium.copyWith(fontSize: 23),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        items.isEmpty
                            ? 'Your area is quiet right now. Be the first to list something.'
                            : 'Try a different search or remove a filter.',
                        textAlign: TextAlign.center,
                        style: ShipdeHopTypography.bodyMedium,
                      ),
                      const SizedBox(height: 22),
                      if (items.isEmpty)
                        Center(
                          child: FilledButton(
                            onPressed: () => setState(() => _selectedModeIndex = 1),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                              backgroundColor: ShipdeHopColors.squirrelOrange,
                              foregroundColor: ShipdeHopColors.brandDark,
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('Sell an item', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        )
                      else
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _selectedCategory = 'All';
                                _myListingsOnly = false;
                              });
                            },
                            icon: const Icon(Icons.filter_alt_off_rounded),
                            label: const Text('Clear filters'),
                          ),
                        ),
                    ],
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.70,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, index) => _MarketplaceCard(
                    item: filtered[index],
                    isMine: filtered[index].sellerId == userId,
                    onTap: () => _showListingDetail(context, filtered[index]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showListingDetail(BuildContext context, MarketplaceCardModel item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarketplaceListingSheet(item: item),
    );
    if (mounted) ref.invalidate(marketplaceFeedProvider);
  }
}

class _MarketplaceCard extends StatelessWidget {
  const _MarketplaceCard({required this.item, required this.isMine, required this.onTap});

  final MarketplaceCardModel item;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: ShipdeHopColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ShipdeHopColors.borderLight),
          boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _MarketplaceImage(
                    imageUrl: item.images.isEmpty ? null : item.images.first,
                    borderRadius: 16,
                    width: double.infinity,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMine ? Icons.person_rounded : (item.shipEligible ? Icons.local_shipping_outlined : Icons.handshake_outlined),
                            color: ShipdeHopColors.brandPrimary,
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMine ? 'Yours' : (item.shipEligible ? 'Can ship' : 'Local'),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(MoneyFormatter.format(item.price, item.currency), style: ShipdeHopTypography.moneyCard),
                  const SizedBox(height: 2),
                  Text(item.title, style: ShipdeHopTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${item.condition} · ${item.category}', style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 14, color: ShipdeHopColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(item.locationName, style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
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

class _MarketplaceListingSheet extends ConsumerStatefulWidget {
  const _MarketplaceListingSheet({required this.item});

  final MarketplaceCardModel item;

  @override
  ConsumerState<_MarketplaceListingSheet> createState() => _MarketplaceListingSheetState();
}

class _MarketplaceListingSheetState extends ConsumerState<_MarketplaceListingSheet> {
  String _fulfillmentMode = 'LOCAL_HANDOFF';
  ConfirmedLocation? _destination;
  final TextEditingController _rewardController = TextEditingController(text: '0');
  final TextEditingController _weightController = TextEditingController(text: '1');
  bool _reserving = false;

  @override
  void dispose() {
    _rewardController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _buy() async {
    final user = ref.read(authUserProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to buy marketplace items.')));
      return;
    }
    if (user.id == widget.item.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot buy your own listing.')));
      return;
    }

    final parcelPool = _fulfillmentMode == 'PARCELPOOL';
    final reward = double.tryParse(_rewardController.text.trim()) ?? -1;
    final weight = double.tryParse(_weightController.text.trim()) ?? -1;
    if (parcelPool && _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a delivery destination.')));
      return;
    }
    if (parcelPool && (reward < 0 || weight <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid delivery reward and item weight.')));
      return;
    }

    setState(() => _reserving = true);
    Map<String, dynamic>? reservation;
    try {
      final idempotencyKey = 'mkt:${widget.item.id}:${user.id}:${DateTime.now().millisecondsSinceEpoch}';
      reservation = await ref.read(apiClientProvider).post('/marketplace/purchases', {
        'itemId': widget.item.id,
        'quantity': 1,
        'fulfillmentMode': _fulfillmentMode,
        'deliveryReward': parcelPool ? reward : 0.0,
        'idempotencyKey': idempotencyKey,
        if (parcelPool) 'destName': _destination!.formattedAddress,
        if (parcelPool) 'destLat': _destination!.latitude,
        if (parcelPool) 'destLng': _destination!.longitude,
        if (parcelPool) 'weightKg': weight,
      });

      final purchase = (reservation['purchase'] as Map).cast<String, dynamic>();
      final order = (reservation['escrow_order'] as Map).cast<String, dynamic>();
      final orderId = order['id'].toString();
      final purchaseId = purchase['id'].toString();
      final base = (order['base_price'] as num?)?.toDouble() ?? widget.item.price;
      final deliveryReward = (order['reward_fee'] as num?)?.toDouble() ?? 0.0;
      final platformFee = (order['platform_fee'] as num?)?.toDouble() ?? 0.0;
      final currency = order['currency']?.toString() ?? widget.item.currency;

      if (!mounted) return;
      final paid = await PaymentReviewModal.show(
        context,
        title: widget.item.title,
        counterpartyName: 'Marketplace seller',
        baseAmount: base,
        rewardAmount: deliveryReward,
        platformFee: platformFee,
        currency: currency,
        onConfirmPayment: () async {
          final funding = await ref.read(apiClientProvider).post('/orders/$orderId/fund', {});
          await ref.read(paymentCoordinatorProvider).completeReservation(funding);
          return true;
        },
      );

      if (paid != true) {
        await ref.read(apiClientProvider).post('/marketplace/purchases/$purchaseId/cancel', {});
        return;
      }

      ref.invalidate(marketplaceFeedProvider);
      ref.invalidate(userOrdersProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parcelPool ? 'Purchase secured. ParcelPool delivery is ready for matching.' : 'Purchase secured. Arrange the local handoff in ShipdeHop.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _reserving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final userId = ref.watch(authUserProvider).value?.id;
    final isMine = userId != null && item.sellerId == userId;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: ShipdeHopColors.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: ShipdeHopColors.borderLight, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _MarketplaceImage(
                  imageUrl: item.images.isEmpty ? null : item.images.first,
                  height: 220,
                  width: double.infinity,
                  borderRadius: 18,
                ),
                const SizedBox(height: 16),
                Text(MoneyFormatter.format(item.price, item.currency), style: ShipdeHopTypography.displayLarge.copyWith(color: ShipdeHopColors.brandPrimary)),
                const SizedBox(height: 4),
                Text(item.title, style: ShipdeHopTypography.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoChip(Icons.sell_outlined, item.condition),
                    _infoChip(Icons.category_outlined, item.category),
                    _infoChip(Icons.inventory_2_outlined, '${item.availableQuantity} available'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 18, color: ShipdeHopColors.brandPrimary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item.locationName, style: ShipdeHopTypography.bodyMedium)),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const Divider(height: 30, color: ShipdeHopColors.borderSubtle),
                  Text('About this item', style: ShipdeHopTypography.titleMedium),
                  const SizedBox(height: 7),
                  Text(item.description, style: ShipdeHopTypography.bodyMedium),
                ],
                const Divider(height: 30, color: ShipdeHopColors.borderSubtle),
                if (isMine) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(16)),
                    child: const Row(
                      children: [
                        Icon(Icons.storefront_rounded, color: ShipdeHopColors.brandPrimary),
                        SizedBox(width: 10),
                        Expanded(child: Text('This is your listing. Buyers will see purchase and delivery options here.')),
                      ],
                    ),
                  ),
                ] else ...[
                  Text('How do you want it?', style: ShipdeHopTypography.titleMedium),
                  const SizedBox(height: 10),
                  _fulfillmentTile(
                    value: 'LOCAL_HANDOFF',
                    icon: Icons.handshake_outlined,
                    title: 'Local handoff',
                    subtitle: 'Meet the seller and verify the handoff in ShipdeHop.',
                  ),
                  if (item.shipEligible) ...[
                    const SizedBox(height: 8),
                    _fulfillmentTile(
                      value: 'PARCELPOOL',
                      icon: Icons.local_shipping_outlined,
                      title: 'Send with ParcelPool',
                      subtitle: 'Secure the purchase now, then match a Hopster for delivery.',
                    ),
                  ],
                  if (_fulfillmentMode == 'PARCELPOOL') ...[
                    const SizedBox(height: 14),
                    LocationPicker(
                      title: 'Delivery destination',
                      geocodingProvider: ref.read(geocodingProvider),
                      locationService: ref.read(locationServiceProvider),
                      onLocationConfirmed: (location) => setState(() => _destination = location),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rewardController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Hopster reward', prefixIcon: Icon(Icons.payments_outlined)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Weight (kg)', prefixIcon: Icon(Icons.scale_outlined)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: ShipdeHopColors.successBg, borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: ShipdeHopColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'HopPay calculates the real platform fee and holds funds until the verified handoff.',
                            style: ShipdeHopTypography.bodySmall.copyWith(color: ShipdeHopColors.success),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isMine)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: ShdPrimaryButton(
                  label: _reserving ? 'Securing item...' : 'Continue to secure purchase',
                  icon: Icons.lock_outline_rounded,
                  onPressed: _reserving ? null : _buy,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: ShipdeHopColors.surfaceSubtle, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: ShipdeHopColors.textSecondary),
            const SizedBox(width: 5),
            Text(text, style: ShipdeHopTypography.bodySmall),
          ],
        ),
      );

  Widget _fulfillmentTile({required String value, required IconData icon, required String title, required String subtitle}) {
    final selected = _fulfillmentMode == value;
    return InkWell(
      onTap: () => setState(() => _fulfillmentMode = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? ShipdeHopColors.brandPrimaryLight : ShipdeHopColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: ShipdeHopColors.surfaceSubtle, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: ShipdeHopColors.brandPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ShipdeHopTypography.titleSmall),
                  const SizedBox(height: 3),
                  Text(subtitle, style: ShipdeHopTypography.bodySmall),
                ],
              ),
            ),
            Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceImage extends StatelessWidget {
  const _MarketplaceImage({
    required this.imageUrl,
    required this.borderRadius,
    this.width,
    this.height,
  });

  final String? imageUrl;
  final double borderRadius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final value = imageUrl?.trim() ?? '';
    if (value.startsWith('data:image/')) {
      try {
        final comma = value.indexOf(',');
        if (comma > 0) {
          final bytes = base64Decode(value.substring(comma + 1));
          return ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }
      } catch (_) {
        // Fall through to the standard image widget.
      }
    }
    return ShdImage(
      imageUrl: value.isEmpty ? null : value,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

class _SellItemView extends ConsumerStatefulWidget {
  const _SellItemView({required this.onListed});

  final VoidCallback onListed;

  @override
  ConsumerState<_SellItemView> createState() => _SellItemViewState();
}

class _PickedListingPhoto {
  const _PickedListingPhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

class _SellItemViewState extends ConsumerState<_SellItemView> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String _category = 'Electronics';
  String _condition = 'Like new';
  ConfirmedLocation? _location;
  String? _selectedCurrency;
  bool _shipEligible = false;
  bool _submitting = false;
  int _quantity = 1;
  final List<_PickedListingPhoto> _photos = [];

  static const _categories = <String>[
    'Electronics',
    'Fashion',
    'Home & Garden',
    'Vehicles',
    'Books & Games',
    'Other',
  ];
  static const _conditions = <String>['New', 'Like new', 'Good', 'Fair', 'Poor'];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_photos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can add up to 4 photos.')),
      );
      return;
    }

    try {
      final files = await _imagePicker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (files.isEmpty || !mounted) return;

      final remaining = 4 - _photos.length;
      final selected = files.take(remaining);
      final additions = <_PickedListingPhoto>[];
      for (final file in selected) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final mime = file.mimeType ?? _mimeFromName(file.name);
        additions.add(_PickedListingPhoto(bytes: bytes, mimeType: mime));
      }
      if (!mounted) return;
      setState(() => _photos.addAll(additions));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add photos: $e')),
      );
    }
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String? _currencyForLocation() {
    return CurrencyCatalog.defaultForCountryCode(_location?.countryCode);
  }

  String? _jurisdictionForLocation() {
    final country = (_location?.countryCode ?? '').trim().toUpperCase();
    return switch (country) {
      'QAT' => 'QA',
      'IND' => 'IN',
      'ARE' || 'UAE' => 'AE',
      'QA' || 'IN' || 'AE' => country,
      _ => null,
    };
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose where the item is located.')),
      );
      return;
    }

    final normalized = _jurisdictionForLocation();
    final currency = _selectedCurrency ?? _currencyForLocation();
    if (normalized == null || currency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marketplace listings currently support India locations.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).post('/marketplace/items', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'price': double.parse(_price.text.trim()),
        'quantity': _quantity,
        'category': _category,
        'condition': switch (_condition) {
          'New' => 'NEW',
          'Like new' => 'LIKE_NEW',
          'Good' => 'GOOD',
          'Fair' => 'FAIR',
          'Poor' => 'POOR',
          _ => throw StateError('Unsupported marketplace condition: $_condition'),
        },
        'currency': currency,
        'locationName': _location!.formattedAddress,
        'jurisdictionCode': normalized,
        'shipEligible': _shipEligible,
        'lat': _location!.latitude,
        'lng': _location!.longitude,
        'images': _photos.map((photo) => photo.dataUrl).toList(growable: false),
      });

      _title.clear();
      _description.clear();
      _price.clear();
      setState(() {
        _category = 'Electronics';
        _condition = 'Like new';
        _location = null;
        _selectedCurrency = null;
        _shipEligible = false;
        _quantity = 1;
        _photos.clear();
      });
      ref.invalidate(marketplaceFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your item is live in Marketplace.')),
        );
        widget.onListed();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = _selectedCurrency ?? _currencyForLocation();
    return Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionEyebrow('PHOTOS'),
                const SizedBox(height: 4),
                Text('Show buyers the real item', style: ShipdeHopTypography.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Add up to 4 clear photos. The first photo becomes the cover.',
                  style: ShipdeHopTypography.bodySmall,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length + (_photos.length < 4 ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index == _photos.length) return _addPhotoTile();
                      return _photoTile(index);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionEyebrow('ITEM DETAILS'),
                const SizedBox(height: 12),
                _fieldLabel('Title'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration('What are you selling?'),
                  validator: (value) {
                    final length = (value ?? '').trim().length;
                    if (length < 3) {
                      return 'Title must be at least 3 characters';
                    }
                    if (length > 140) {
                      return 'Title must be 140 characters or fewer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _fieldLabel('Description'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: _inputDecoration('Condition, age, accessories and anything the buyer should know'),
                  validator: (value) => (value ?? '').trim().length < 2 ? 'Add a short description' : null,
                ),
                const SizedBox(height: 14),
                _fieldLabel('Category'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: _inputDecoration('Choose category'),
                  borderRadius: BorderRadius.circular(16),
                  items: _categories
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setState(() => _category = value ?? _category),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionEyebrow('PRICE & CONDITION'),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Price'),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 104,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedCurrency ?? currency,
                                  isExpanded: true,
                                  decoration: _inputDecoration('Currency'),
                                  items: CurrencyCatalog.all
                                      .map(
                                        (code) => DropdownMenuItem<String>(
                                          value: code,
                                          child: Text(
                                            code,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _selectedCurrency = value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _price,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(decimal: true),
                                  decoration: _inputDecoration(
                                    '${_selectedCurrency ?? currency ?? 'USD'} 0',
                                  ),
                                  validator: (value) {
                                    final n =
                                        double.tryParse((value ?? '').trim());
                                    return n == null || n <= 0
                                        ? 'Enter a valid price'
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Quantity'),
                          const SizedBox(height: 6),
                          Container(
                            height: 54,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: ShipdeHopColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: ShipdeHopColors.borderLight),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _quantityButton(Icons.remove_rounded, _quantity > 1 ? () => setState(() => _quantity--) : null),
                                Text('$_quantity', style: ShipdeHopTypography.titleMedium),
                                _quantityButton(Icons.add_rounded, () => setState(() => _quantity++)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _fieldLabel('Condition'),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 18) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _conditions.map((condition) {
                        final selected = condition == _condition;
                        return SizedBox(
                          width: width,
                          child: InkWell(
                            onTap: () => setState(() => _condition = condition),
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              height: 46,
                              decoration: BoxDecoration(
                                color: selected ? ShipdeHopColors.brandPrimaryLight : ShipdeHopColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (selected) ...[
                                    const Icon(Icons.check_rounded, size: 17, color: ShipdeHopColors.brandPrimary),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    condition,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: selected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionEyebrow('HANDOFF'),
                const SizedBox(height: 12),
                LocationPicker(
                  key: ValueKey(_location?.formattedAddress ?? 'empty-listing-location'),
                  title: 'Item location',
                  initialLocation: _location,
                  geocodingProvider: ref.read(geocodingProvider),
                  locationService: ref.read(locationServiceProvider),
                  onLocationConfirmed: (location) => setState(() {
                    _location = location;
                    _selectedCurrency =
                        CurrencyCatalog.defaultForCountryCode(location.countryCode) ??
                        _selectedCurrency;
                  }),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => setState(() => _shipEligible = !_shipEligible),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _shipEligible ? ShipdeHopColors.brandPrimaryLight : ShipdeHopColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _shipEligible ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight,
                        width: _shipEligible ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: ShipdeHopColors.surfaceCard,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.local_shipping_outlined, color: ShipdeHopColors.brandPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Allow ParcelPool delivery', style: ShipdeHopTypography.titleSmall),
                              const SizedBox(height: 3),
                              Text(
                                'Buyers can match a Hopster to carry this item after purchase.',
                                style: ShipdeHopTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _shipEligible,
                          onChanged: (value) => setState(() => _shipEligible = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: ShipdeHopColors.successBg,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_rounded, color: ShipdeHopColors.success, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'HopPay protects the buyer payment until the verified handoff is complete.',
                          style: ShipdeHopTypography.bodySmall.copyWith(color: ShipdeHopColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ShdPrimaryButton(
            label: _submitting ? 'Publishing...' : 'List item for sale',
            icon: Icons.check_circle_outline_rounded,
            backgroundColor: ShipdeHopColors.brandPrimary,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 8),
          Text(
            'You can edit or remove your listing later from My listings.',
            textAlign: TextAlign.center,
            style: ShipdeHopTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _section({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShipdeHopColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ShipdeHopColors.borderSubtle),
          boxShadow: const [
            BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        child: child,
      );

  Widget _sectionEyebrow(String text) => Text(
        text,
        style: ShipdeHopTypography.labelSmall.copyWith(
          color: ShipdeHopColors.textMuted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      );

  Widget _fieldLabel(String text) => Text(
        text,
        style: ShipdeHopTypography.labelMedium.copyWith(
          color: ShipdeHopColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: ShipdeHopTypography.bodyMedium.copyWith(color: ShipdeHopColors.textMuted),
        filled: true,
        fillColor: ShipdeHopColors.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShipdeHopColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShipdeHopColors.brandPrimary, width: 1.5),
        ),
      );

  Widget _quantityButton(IconData icon, VoidCallback? onPressed) => SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        ),
      );

  Widget _addPhotoTile() => InkWell(
        onTap: _pickPhotos,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 92,
          decoration: BoxDecoration(
            color: ShipdeHopColors.brandPrimaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ShipdeHopColors.brandPrimary.withValues(alpha: 0.35)),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: ShipdeHopColors.brandPrimary),
              SizedBox(height: 6),
              Text('Add photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ShipdeHopColors.brandPrimary)),
            ],
          ),
        ),
      );

  Widget _photoTile(int index) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _photos[index].bytes,
              width: 92,
              height: 92,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: InkWell(
              onTap: () => setState(() => _photos.removeAt(index)),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
          if (index == 0)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      );
}
