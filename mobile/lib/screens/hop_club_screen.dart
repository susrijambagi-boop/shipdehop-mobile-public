import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';
import 'hop_passport_screen.dart';

class HopClubScreen extends ConsumerStatefulWidget {
  const HopClubScreen({super.key});

  @override
  ConsumerState<HopClubScreen> createState() => _HopClubScreenState();
}

class _HopClubScreenState extends ConsumerState<HopClubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _claimedXp = 0;
  final Set<String> _claimedQuests = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _claimQuest(String id, int xp) {
    if (_claimedQuests.contains(id)) return;
    setState(() {
      _claimedQuests.add(id);
      _claimedXp += xp;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: ShipdeHopColors.squirrelOrange),
            const SizedBox(width: 8),
            Text('+$xp XP claimed!'),
          ],
        ),
        backgroundColor: ShipdeHopColors.brandDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final framework = ref.watch(gamificationFrameworkProvider);
    final levelNumber = framework.currentLevel.index + 1;
    final levelTitle = framework.levelTitle;
    final totalXp = framework.xp + _claimedXp;

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.brandDark,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(
          'Hop Club',
          style: ShipdeHopTypography.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // LEVEL & XP BANNER
          Container(
            color: ShipdeHopColors.brandDark,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ShipdeHopColors.squirrelOrange,
                      ),
                      child: const Center(
                        child: Icon(Icons.local_fire_department_rounded, color: ShipdeHopColors.brandDark, size: 30),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Level $levelNumber · $levelTitle',
                                  style: ShipdeHopTypography.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ShipdeHopColors.squirrelOrange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$totalXp XP',
                                  style: const TextStyle(color: ShipdeHopColors.brandDark, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            framework.isProvisional
                                ? 'Complete verified hops to level up!'
                                : 'Verified community activity level',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const ShipdeHopMascot(
                      pose: MascotPose.celebrate,
                      motion: MascotMotion.idleFloat,
                      size: 46,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text('Progress to Level 7', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('${totalXp % 500} / 500 XP', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (totalXp % 500) / 500.0,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(ShipdeHopColors.squirrelOrange),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // TAB BAR
          Container(
            color: ShipdeHopColors.brandDark,
            child: TabBar(
              controller: _tabController,
              indicatorColor: ShipdeHopColors.squirrelOrange,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Quests'),
                Tab(text: 'Badges'),
                Tab(text: 'Passport'),
                Tab(text: 'Rewards'),
              ],
            ),
          ),

          // TAB VIEWS
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. QUESTS
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('DAILY QUESTS', style: ShipdeHopTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.textMuted)),
                    const SizedBox(height: 10),
                    _buildQuestCard(
                      id: 'q1',
                      title: 'Complete 1 HopShip Parcel',
                      subtitle: 'Send or carry a parcel safely',
                      xp: 150,
                      progress: 1.0,
                      isCompleted: true,
                    ),
                    _buildQuestCard(
                      id: 'q2',
                      title: 'Check Corridor Opportunities',
                      subtitle: 'View active routes from Doha to Lusail',
                      xp: 50,
                      progress: 1.0,
                      isCompleted: true,
                    ),
                    const SizedBox(height: 20),
                    Text('WEEKLY CHALLENGES', style: ShipdeHopTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.textMuted)),
                    const SizedBox(height: 10),
                    _buildQuestCard(
                      id: 'q3',
                      title: 'Share 3 CarPool Rides',
                      subtitle: 'Offer empty seats on your commute',
                      xp: 300,
                      progress: 0.66,
                      isCompleted: false,
                    ),
                    _buildQuestCard(
                      id: 'q4',
                      title: 'Unlock 2 Passport Stamps',
                      subtitle: 'Complete verified hops to new cities',
                      xp: 250,
                      progress: 0.50,
                      isCompleted: false,
                    ),
                  ],
                ),

                // 2. BADGES
                GridView.count(
                  crossAxisCount: 3,
                  padding: const EdgeInsets.all(16),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _buildBadgeCard('Pathfinder', Icons.explore_rounded, ShipdeHopColors.brandPrimary, true),
                    _buildBadgeCard('Pioneer', Icons.military_tech_rounded, ShipdeHopColors.squirrelOrange, true),
                    _buildBadgeCard('Shield Master', Icons.shield_rounded, ShipdeHopColors.success, true),
                    _buildBadgeCard('Speedy Hopper', Icons.bolt_rounded, ShipdeHopColors.info, false),
                    _buildBadgeCard('Global Carrier', Icons.public_rounded, Colors.purple, false),
                    _buildBadgeCard('Eco Commuter', Icons.eco_rounded, Colors.teal, false),
                  ],
                ),

                // 3. PASSPORT
                const HopPassportScreen(),

                // 4. REWARDS
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('SAFE REWARDS & COSMETICS', style: ShipdeHopTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.textMuted)),
                    const SizedBox(height: 10),
                    _buildRewardCard('Pathfinder Profile Frame', 'Exclusive indigo avatar ring', Icons.workspace_premium_rounded, true),
                    _buildRewardCard('Hop Club Title: Master Hopper', 'Displayable status on public profile', Icons.stars_rounded, true),
                    _buildRewardCard('Doha → Dubai Challenge Pass', 'Access city achievement leaderboard', Icons.flag_rounded, false),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestCard({
    required String id,
    required String title,
    required String subtitle,
    required int xp,
    required double progress,
    required bool isCompleted,
  }) {
    final isClaimed = _claimedQuests.contains(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShipdeHopColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShipdeHopColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ShipdeHopTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: ShipdeHopTypography.bodySmall),
                  ],
                ),
              ),
              if (isCompleted && !isClaimed)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShipdeHopColors.squirrelOrange,
                    foregroundColor: ShipdeHopColors.brandDark,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => _claimQuest(id, xp),
                  child: Text('+$xp XP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                )
              else if (isClaimed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ShipdeHopColors.successBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Claimed ✓', style: TextStyle(color: ShipdeHopColors.success, fontWeight: FontWeight.bold, fontSize: 11)),
                )
              else
                Text('+$xp XP', style: const TextStyle(color: ShipdeHopColors.brandPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: ShipdeHopColors.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(isCompleted ? ShipdeHopColors.success : ShipdeHopColors.brandPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(String title, IconData icon, Color color, bool unlocked) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked ? ShipdeHopColors.surfaceCard : ShipdeHopColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: unlocked ? color.withValues(alpha: 0.3) : ShipdeHopColors.borderLight),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: unlocked ? color.withValues(alpha: 0.15) : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: unlocked ? color : Colors.grey, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: unlocked ? ShipdeHopColors.textPrimary : Colors.grey),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard(String title, String sub, IconData icon, bool unlocked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShipdeHopColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShipdeHopColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: unlocked ? ShipdeHopColors.squirrelOrange : Colors.grey, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ShipdeHopTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
                Text(sub, style: ShipdeHopTypography.bodySmall),
              ],
            ),
          ),
          if (unlocked)
            const Text('Unlocked', style: TextStyle(color: ShipdeHopColors.success, fontWeight: FontWeight.bold, fontSize: 11))
          else
            const Text('Locked', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
