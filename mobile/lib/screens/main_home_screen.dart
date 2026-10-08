import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/shipdehop_colors.dart';
import '../widgets/global_header.dart';
import 'carpool_screen.dart';
import 'explore_screen.dart';
import 'marketplace_screen.dart';
import 'orders_screen.dart';
import 'parcelpool_screen.dart';

class MainHomeScreen extends ConsumerStatefulWidget {
  const MainHomeScreen({super.key});

  @override
  ConsumerState<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends ConsumerState<MainHomeScreen> {
  int _currentIndex = 0;
  int _parcelPoolModeIndex = 0;
  int _carpoolModeIndex = 0;
  int _marketplaceModeIndex = 0;
  String? _prefilledOrigin;
  String? _prefilledDestination;

  void _onSelectTab(
    int tabIndex, {
    int? modeIndex,
    String? origin,
    String? destination,
  }) {
    setState(() {
      _currentIndex = tabIndex;
      if (origin?.trim().isNotEmpty == true) _prefilledOrigin = origin!.trim();
      if (destination?.trim().isNotEmpty == true) _prefilledDestination = destination!.trim();
      if (tabIndex == 1) _parcelPoolModeIndex = modeIndex ?? 0;
      if (tabIndex == 2) _carpoolModeIndex = modeIndex ?? 0;
      if (tabIndex == 3) _marketplaceModeIndex = modeIndex ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ExploreScreen(onSelectTab: _onSelectTab),
      ParcelPoolScreen(
        initialModeIndex: _parcelPoolModeIndex,
        prefilledOrigin: _prefilledOrigin,
        prefilledDestination: _prefilledDestination,
      ),
      CarPoolScreen(
        initialModeIndex: _carpoolModeIndex,
        prefilledOrigin: _prefilledOrigin,
        prefilledDestination: _prefilledDestination,
      ),
      MarketplaceScreen(initialModeIndex: _marketplaceModeIndex),
      const OrdersTabWrapper(),
    ];

    final tabTitles = ['Explore', 'ParcelPool', 'CarPool', 'Marketplace', 'Activity'];

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: GlobalHeader(
        onSelectTab: (idx) => _onSelectTab(idx),
        showBrand: _currentIndex == 0,
        title: tabTitles[_currentIndex],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 60,
          elevation: 4,
          backgroundColor: ShipdeHopColors.surfaceCard,
          indicatorColor: ShipdeHopColors.brandPrimaryLight,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(size: 20, color: ShipdeHopColors.brandPrimary);
            }
            return const IconThemeData(size: 20, color: ShipdeHopColors.textSecondary);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ShipdeHopColors.brandPrimary);
            }
            return const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ShipdeHopColors.textSecondary);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'ParcelPool',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_car_outlined),
              selectedIcon: Icon(Icons.directions_car_rounded),
              label: 'CarPool',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Marketplace',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersTabWrapper extends StatelessWidget {
  const OrdersTabWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const OrdersScreen();
  }
}
