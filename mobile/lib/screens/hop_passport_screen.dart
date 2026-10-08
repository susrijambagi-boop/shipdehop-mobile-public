import 'package:flutter/material.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';

class HopPassportScreen extends StatefulWidget {
  const HopPassportScreen({super.key});

  @override
  State<HopPassportScreen> createState() => _HopPassportScreenState();
}

class _HopPassportScreenState extends State<HopPassportScreen> {
  // Pre-unlocked cities (qualifying events)
  final Set<String> _unlockedCities = {'Doha', 'Lusail', 'Al Wakrah'};
  final Set<String> _previouslyStamped = {'Doha', 'Lusail', 'Al Wakrah'};

  void _claimNewCityStamp(String city) {
    if (_unlockedCities.contains(city) && !_previouslyStamped.contains(city)) {
      setState(() {
        _previouslyStamped.add(city);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stamp added for $city! +100 XP (First Unlock Only)'),
          backgroundColor: ShipdeHopColors.brandPrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = [
      {'name': 'Doha', 'country': 'Qatar', 'code': 'DOH', 'date': '12 Aug 2026'},
      {'name': 'Lusail', 'country': 'Qatar', 'code': 'LSL', 'date': '18 Aug 2026'},
      {'name': 'Al Wakrah', 'country': 'Qatar', 'code': 'WKR', 'date': '24 Aug 2026'},
      {'name': 'Riyadh', 'country': 'Saudi Arabia', 'code': 'RUH', 'date': 'Locked'},
      {'name': 'Dubai', 'country': 'UAE', 'code': 'DXB', 'date': 'Locked'},
      {'name': 'Istanbul', 'country': 'Turkey', 'code': 'IST', 'date': 'Locked'},
    ];

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Passport Cover Strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ShipdeHopColors.brandDark, Color(0xFF231464)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: ShipdeHopColors.squirrelOrange, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hop Passport',
                        style: ShipdeHopTypography.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Stamps earned through verified city hops',
                        style: ShipdeHopTypography.bodySmall.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ShipdeHopColors.squirrelOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_previouslyStamped.length} Stamps',
                    style: const TextStyle(color: ShipdeHopColors.brandDark, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stamp Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cities.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemBuilder: (context, idx) {
              final c = cities[idx];
              final name = c['name']!;
              final code = c['code']!;
              final isUnlocked = _previouslyStamped.contains(name);

              return GestureDetector(
                onTap: () => _claimNewCityStamp(name),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUnlocked ? ShipdeHopColors.surfaceCard : ShipdeHopColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isUnlocked ? ShipdeHopColors.brandPrimary.withValues(alpha: 0.3) : ShipdeHopColors.borderLight,
                      width: isUnlocked ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            code,
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isUnlocked ? ShipdeHopColors.brandPrimary : Colors.grey,
                            ),
                          ),
                          Icon(
                            isUnlocked ? Icons.verified_rounded : Icons.lock_outline_rounded,
                            size: 18,
                            color: isUnlocked ? ShipdeHopColors.success : Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isUnlocked ? ShipdeHopColors.textPrimary : Colors.grey,
                        ),
                      ),
                      Text(
                        c['country']!,
                        style: TextStyle(fontSize: 11, color: isUnlocked ? ShipdeHopColors.textSecondary : Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c['date']!,
                        style: TextStyle(fontSize: 10, color: isUnlocked ? ShipdeHopColors.success : Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShipdeHopColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ShipdeHopColors.borderLight),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: ShipdeHopColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Passport stamps are earned automatically as you complete verified hops across cities. Persistent cross-session stamp syncing is specified for future backend release.',
                    style: ShipdeHopTypography.bodySmall.copyWith(fontSize: 10, color: ShipdeHopColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
