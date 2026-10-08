import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/ui/shd_skeleton.dart';
import '../core/money_formatter.dart';
import '../providers/app_providers.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/location_picker.dart';
import '../widgets/trip_assistant_sheet.dart';
import '../widgets/ui/shd_image.dart';
import '../widgets/ui/shd_location_header.dart';
import '../widgets/ui/shd_status_badge.dart';
import 'delivery_details_screen.dart';
import 'hop_club_screen.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({
    super.key,
    required this.onSelectTab,
  });

  final void Function(int tabIndex, {int? modeIndex, String? origin, String? destination}) onSelectTab;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _currentLocality = 'Your location';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    FocusScope.of(context).unfocus();

    await TripAssistantSheet.show(
      context,
      query: clean,
      onOpenParcelPool: (origin, destination) {
        widget.onSelectTab(
          1,
          modeIndex: 2,
          origin: origin,
          destination: destination,
        );
      },
      onOpenCarPool: (origin, destination) {
        widget.onSelectTab(
          2,
          modeIndex: 1,
          origin: origin,
          destination: destination,
        );
      },
    );
  }

  Future<void> _openLocationPicker() async {
    final confirmed = await LocationPicker.show(
      context,
      title: 'Choose your ShipdeHop location',
      initialQuery: _currentLocality == 'Your location' ? null : _currentLocality,
      geocodingProvider: ref.read(geocodingProvider),
      locationService: ref.read(locationServiceProvider),
    );
    if (confirmed == null || !mounted) return;
    setState(() => _currentLocality = confirmed.displayLabel);
    ref.read(selectedLocationProvider.notifier).state = confirmed;
  }

  @override
  Widget build(BuildContext context) {
    final activeOrders = ref.watch(unifiedHistoryProvider).value ?? [];
    final activeOrder = activeOrders.isNotEmpty ? activeOrders.first : null;

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: ShipdeHopColors.brandPrimary,
          onRefresh: () async {
            ref.invalidate(shipmentFeedProvider);
            ref.invalidate(marketplaceFeedProvider);
            ref.invalidate(unifiedHistoryProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              ShdLocationHeader(
                locationName: _currentLocality,
                onTapLocation: _openLocationPicker,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ShipdeHopColors.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ShipdeHopColors.borderLight),
                  boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: ShipdeHopColors.brandPrimaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: ShipdeHopColors.brandPrimary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ask ShipdeHop', style: ShipdeHopTypography.titleMedium.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                'Describe a trip or task. I’ll turn it into ParcelPool, CarPool and marketplace actions.',
                                style: ShipdeHopTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('home_assistant_input'),
                      controller: _searchController,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleSearch,
                      decoration: InputDecoration(
                        hintText: 'Example: I’m travelling from Bengaluru to Mangaluru on 20 Sep',
                        hintStyle: ShipdeHopTypography.bodyMedium.copyWith(color: ShipdeHopColors.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded, color: ShipdeHopColors.brandPrimary),
                        suffixIcon: IconButton(
                          tooltip: 'Plan with ShipdeHop',
                          onPressed: () => _handleSearch(_searchController.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          color: ShipdeHopColors.squirrelOrange,
                        ),
                        filled: true,
                        fillColor: ShipdeHopColors.surfaceSubtle,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'It can ask your travel mode and group size, then suggest parcels and seat-sharing opportunities for the same route.',
                      style: ShipdeHopTypography.bodySmall.copyWith(color: ShipdeHopColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('QUICK ACTIONS', style: ShipdeHopTypography.labelSmall.copyWith(fontWeight: FontWeight.w700, color: ShipdeHopColors.textMuted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildQuickActionTile(icon: Icons.inventory_2_outlined, title: 'Send Parcel', color: ShipdeHopColors.brandPrimary, bgColor: ShipdeHopColors.brandPrimaryLight, onTap: () => widget.onSelectTab(1, modeIndex: 0)),
                  const SizedBox(width: 8),
                  _buildQuickActionTile(icon: Icons.directions_car_outlined, title: 'Find Ride', color: ShipdeHopColors.carpoolAccent, bgColor: ShipdeHopColors.carpoolBg, onTap: () => widget.onSelectTab(2, modeIndex: 0)),
                  const SizedBox(width: 8),
                  _buildQuickActionTile(icon: Icons.flight_takeoff_rounded, title: 'Travelling', color: ShipdeHopColors.brandPrimary, bgColor: ShipdeHopColors.brandPrimaryLight, onTap: () => widget.onSelectTab(1, modeIndex: 2)),
                  const SizedBox(width: 8),
                  _buildQuickActionTile(icon: Icons.storefront_outlined, title: 'Market', color: ShipdeHopColors.marketplaceAccent, bgColor: ShipdeHopColors.marketplaceBg, onTap: () => widget.onSelectTab(3, modeIndex: 0)),
                ],
              ),
              const SizedBox(height: 20),
              if (activeOrder != null) ...[
                Text('ACTIVE ACTIVITY', style: ShipdeHopTypography.labelSmall.copyWith(fontWeight: FontWeight.w700, color: ShipdeHopColors.textMuted)),
                const SizedBox(height: 8),
                _buildActiveOrderLiveCard(context, activeOrder),
                const SizedBox(height: 20),
              ],
              _buildUpcomingJourneyCard(context),
              const SizedBox(height: 16),
              _buildHopClubHeroCard(context),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Opportunities along your journeys', style: ShipdeHopTypography.titleLarge)),
                  TextButton(
                    onPressed: () => widget.onSelectTab(1),
                    child: const Text('See All', style: TextStyle(color: ShipdeHopColors.brandPrimary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildShipmentList(ref),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Marketplace Discoveries', style: ShipdeHopTypography.titleLarge)),
                  TextButton(
                    onPressed: () => widget.onSelectTab(3),
                    child: const Text('Browse Market', style: TextStyle(color: ShipdeHopColors.brandPrimary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildMarketplaceFeed(ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionTile({required IconData icon, required String title, required Color color, required Color bgColor, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Column(
          children: [
            AspectRatio(aspectRatio: 1, child: Container(decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(17)), child: Icon(icon, color: color, size: 24))),
            const SizedBox(height: 7),
            Text(title, textAlign: TextAlign.center, maxLines: 2, style: ShipdeHopTypography.labelMedium.copyWith(fontSize: 11, color: ShipdeHopColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrderLiveCard(BuildContext context, Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'CREATED';
    final orderId = order['id']?.toString() ?? '';
    final module = order['module']?.toString() ?? 'PARCELPOOL';
    final title = order['title']?.toString();
    final origin = order['originName']?.toString() ?? order['origin_name']?.toString();
    final dest = order['destName']?.toString() ?? order['dest_name']?.toString();
    final route = origin?.isNotEmpty == true && dest?.isNotEmpty == true ? '$origin → $dest' : null;
    final displayTitle = route ?? (title?.isNotEmpty == true ? title! : module == 'CARPOOL' ? 'Your ride' : module == 'MARKETPLACE' ? 'Marketplace delivery' : 'Your parcel');
    final upperStatus = status.toUpperCase();
    final isComplete = upperStatus.contains('COMPLETE') || upperStatus.contains('RELEASE');
    final progress = isComplete ? 1.0 : upperStatus.contains('HANDOFF') ? .9 : upperStatus.contains('TRANSIT') ? .65 : upperStatus.contains('PICK') ? .45 : upperStatus.contains('PAYMENT') || upperStatus.contains('LOCK') ? .3 : .15;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 20, offset: Offset(0, 6))]),
      child: Column(children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: isComplete ? ShipdeHopColors.textMuted : ShipdeHopColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(isComplete ? 'COMPLETED' : 'IN PROGRESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: isComplete ? ShipdeHopColors.textMuted : ShipdeHopColors.success)),
          const Spacer(),
          ShdStatusBadge(status: status, compact: true),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(14)), child: Icon(module == 'CARPOOL' ? Icons.directions_car_rounded : module == 'MARKETPLACE' ? Icons.shopping_bag_rounded : Icons.inventory_2_rounded, color: ShipdeHopColors.brandPrimary)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayTitle, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('Tap Track for the latest journey status', style: ShipdeHopTypography.bodySmall),
          ])),
          const SizedBox(width: 8),
          SizedBox(height: 44, child: FilledButton(onPressed: orderId.isEmpty ? null : () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => DeliveryDetailsScreen(orderId: orderId))), style: FilledButton.styleFrom(backgroundColor: ShipdeHopColors.brandDark, foregroundColor: Colors.white, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 17)), child: const Text('Track', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)))),
        ]),
        const SizedBox(height: 13),
        ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress, minHeight: 5, backgroundColor: const Color(0xFFF0EEF7), color: ShipdeHopColors.success)),
        const SizedBox(height: 7),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Matched', style: ShipdeHopTypography.labelSmall),
          Text(isComplete ? 'Delivered' : 'In transit', style: ShipdeHopTypography.labelSmall.copyWith(color: ShipdeHopColors.textPrimary)),
          Text('Handoff', style: ShipdeHopTypography.labelSmall),
        ]),
      ]),
    );
  }

  Widget _buildHopClubHeroCard(BuildContext context) {
    final framework = ref.watch(gamificationFrameworkProvider);
    final levelNum = framework.currentLevel.index + 1;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HopClubScreen())),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ShipdeHopColors.borderLight)),
          child: Row(children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: ShipdeHopColors.squirrelOrange.withValues(alpha: .14), shape: BoxShape.circle), child: const Icon(Icons.local_fire_department_rounded, color: ShipdeHopColors.squirrelOrange, size: 19)),
            const SizedBox(width: 10),
            Expanded(child: Text('Hop Club · Level $levelNum · ${framework.xp} XP', style: ShipdeHopTypography.labelMedium.copyWith(fontWeight: FontWeight.w700, color: ShipdeHopColors.textPrimary))),
            Text('View', style: ShipdeHopTypography.labelMedium.copyWith(color: ShipdeHopColors.brandPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, color: ShipdeHopColors.textMuted, size: 19),
          ]),
        ),
      ),
    );
  }

  Widget _buildUpcomingJourneyCard(BuildContext context) {
    final routesAsync = ref.watch(myRoutesProvider);
    return routesAsync.when(
      data: (routes) {
        final route = routes.isNotEmpty ? routes.first : null;
        final origin = route?['origin_name']?.toString();
        final dest = route?['dest_name']?.toString();
        final routeLabel = origin != null && origin.isNotEmpty && dest != null && dest.isNotEmpty ? '$origin → $dest' : 'Publish your next journey';
        final subtitle = route == null ? 'Matching parcel and ride opportunities will appear after you publish.' : 'We will surface real opportunities that match this route.';
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF27235F), Color(0xFF3A1FD1)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: ShipdeHopColors.shadowElevated, blurRadius: 14, offset: Offset(0, 5))]),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.route_rounded, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(route == null ? 'YOUR NEXT JOURNEY' : 'YOUR UPCOMING JOURNEY', style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .7)),
              const SizedBox(height: 5),
              Text(routeLabel, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w700), maxLines: 2),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11.5), maxLines: 2),
            ])),
            const SizedBox(width: 8),
            SizedBox(height: 44, child: ElevatedButton(onPressed: () => widget.onSelectTab(1, modeIndex: 2), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: ShipdeHopColors.brandDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text(route == null ? 'Publish' : 'View', style: const TextStyle(fontWeight: FontWeight.w700)))),
          ]),
        );
      },
      loading: () => Container(height: 106, decoration: BoxDecoration(color: ShipdeHopColors.brandDark, borderRadius: BorderRadius.circular(22)), alignment: Alignment.center, child: const CircularProgressIndicator(color: Colors.white)),
      error: (_, _) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: ShipdeHopColors.brandDark, borderRadius: BorderRadius.circular(22)), child: Text('Publish a journey to unlock matching opportunities.', style: ShipdeHopTypography.bodyMedium.copyWith(color: Colors.white70))),
    );
  }

  Widget _buildShipmentList(WidgetRef ref) {
    final feedAsync = ref.watch(shipmentFeedProvider);
    return feedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ShipdeHopColors.borderLight)), child: const Center(child: Text('No active opportunities nearby right now.', style: ShipdeHopTypography.bodyMedium)));
        }
        return SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length > 5 ? 5 : items.length,
            separatorBuilder: (ctx, idx) => const SizedBox(width: 12),
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final title = item.itemType;
              final origin = item.pickup;
              final dest = item.drop;
              final reward = item.reward;
              return Container(
                width: 260,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ShipdeHopColors.borderLight), boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(8)), child: const Text('PARCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ShipdeHopColors.brandPrimary))),
                    const Spacer(),
                    Text(MoneyFormatter.formatINR(reward), style: ShipdeHopTypography.moneyCard),
                  ]),
                  const SizedBox(height: 8),
                  Text(title, style: ShipdeHopTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.place_outlined, size: 14, color: ShipdeHopColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text('$origin → $dest', style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const Spacer(),
                  SizedBox(width: double.infinity, height: 32, child: OutlinedButton(onPressed: () => widget.onSelectTab(1), style: OutlinedButton.styleFrom(side: const BorderSide(color: ShipdeHopColors.brandPrimary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: EdgeInsets.zero), child: const Text('View opportunity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ShipdeHopColors.brandPrimary)))),
                ]),
              );
            },
          ),
        );
      },
      loading: () => ShdSkeleton(enabled: true, child: SizedBox(height: 155, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: 3, separatorBuilder: (ctx, idx) => const SizedBox(width: 12), itemBuilder: (ctx, idx) => Container(width: 260, decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.all(14), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 150, height: 16), SizedBox(height: 8), SizedBox(width: 190, height: 12)]))))),
      error: (err, stack) => const Text('Unable to load opportunities', style: ShipdeHopTypography.bodySmall),
    );
  }

  Widget _buildMarketplaceFeed(WidgetRef ref) {
    final mktAsync = ref.watch(marketplaceFeedProvider);
    return mktAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ShipdeHopColors.borderLight)), child: const Center(child: Text('No marketplace items available nearby.', style: ShipdeHopTypography.bodyMedium)));
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: items.length > 4 ? 4 : items.length,
          itemBuilder: (ctx, idx) {
            final item = items[idx];
            final title = item.title;
            final price = item.price;
            return InkWell(
              onTap: () => widget.onSelectTab(3),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: ShipdeHopColors.borderLight), boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(child: ShdImage(imageUrl: null, borderRadius: 16, width: double.infinity)),
                  Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(MoneyFormatter.formatINR(price), style: ShipdeHopTypography.moneyCard),
                    const SizedBox(height: 2),
                    Text(title, style: ShipdeHopTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                ]),
              ),
            );
          },
        );
      },
      loading: () => ShdSkeleton(enabled: true, child: GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: 4, itemBuilder: (ctx, idx) => Container(decoration: BoxDecoration(color: ShipdeHopColors.surfaceCard, borderRadius: BorderRadius.circular(16))))),
      error: (err, stack) => const Text('Unable to load marketplace feed', style: ShipdeHopTypography.bodySmall),
    );
  }
}
