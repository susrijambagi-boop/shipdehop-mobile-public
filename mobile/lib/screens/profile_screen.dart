import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/admin_access.dart';
import '../core/app_config.dart';
import '../providers/app_providers.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import 'hop_club_screen.dart';
import 'help_support_screen.dart';
import 'profile_option_screens.dart';
import 'lifecycle_simulator_screen.dart';
import 'identity_verification_screen.dart';
import 'admin_identity_review_screen.dart';
import 'admin_whatsapp_bridge_screen.dart';

final _adminPendingIdentityCountProvider = FutureProvider<int>((ref) async {
  final authUser = ref.watch(authUserProvider).value;
  if (!isShipdeHopAdmin(authUser?.appMetadata)) return 0;

  final rows = await ref
      .watch(supabaseProvider)
      .from('user_identities')
      .select('id')
      .eq('verification_status', 'PENDING_REVIEW')
      .limit(100);

  return (rows as List<dynamic>).length;
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  Future<void> _switchDevAccount(String targetEmail) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supabaseProvider).auth.signOut();
      final response = await ref.read(apiClientProvider).post('/dev/auth/login-as-test-user', {'email': targetEmail});
      final sessionMap = (response['session'] as Map).cast<String, dynamic>();
      await ref.read(supabaseProvider).auth.setSession(sessionMap['refresh_token'].toString());
      ref.invalidate(ownProfileProvider);
      ref.invalidate(unifiedHistoryProvider);
      ref.invalidate(globalChatInboxProvider);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Switched identity to $targetEmail'), backgroundColor: ShipdeHopColors.success));
    } on ApiException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Failed to switch account: ${e.message}'), backgroundColor: ShipdeHopColors.error));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Error switching account: $e'), backgroundColor: ShipdeHopColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(ownProfileProvider);
    final authUser = ref.watch(authUserProvider).value;
    final framework = ref.watch(gamificationFrameworkProvider);

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('My Account', style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Settings', onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const AccountSettingsScreen())), icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: profileAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(24, 70, 24, 120),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: ShipdeHopColors.brandPrimaryLight),
                child: const Icon(Icons.person_rounded, size: 36, color: ShipdeHopColors.brandPrimary),
              ),
            ),
            const SizedBox(height: 18),
            Text('Loading your account…', textAlign: TextAlign.center, style: ShipdeHopTypography.titleMedium),
            const SizedBox(height: 6),
            Text('Trust, progress and account settings will appear here.', textAlign: TextAlign.center, style: ShipdeHopTypography.bodyMedium),
          ],
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_off_outlined, size: 44, color: ShipdeHopColors.textMuted),
                const SizedBox(height: 12),
                Text('Could not load your account', style: ShipdeHopTypography.titleMedium),
                const SizedBox(height: 6),
                Text('Your data is safe. Try again when the connection is available.', textAlign: TextAlign.center, style: ShipdeHopTypography.bodyMedium),
                const SizedBox(height: 14),
                TextButton(onPressed: () => ref.invalidate(ownProfileProvider), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (profile) {
          final fullName = profile['fullName']?.toString() ?? profile['full_name']?.toString() ?? 'ShipdeHop User';
          final email = profile['email']?.toString() ?? authUser?.email ?? '';
          final trustScore = ((profile['trustScore'] ?? profile['trust_score']) as num?)?.toDouble() ?? 0;
          final xpPoints = ((profile['xpPoints'] ?? profile['xp_points']) as num?)?.toInt() ?? 0;
          final completed = (profile['completedTransactionsCount'] as num?)?.toInt() ?? 0;
          final identityStatus =
              profile['identityVerificationStatus']?.toString().toUpperCase() ??
                  'NOT_STARTED';
          final identityVerified = profile['isIdentityVerified'] == true ||
              identityStatus == 'VERIFIED';
          final identityPending =
              identityStatus == 'PENDING_REVIEW' || identityStatus == 'IN_PROGRESS';
          final identityNeedsAttention =
              identityStatus == 'REJECTED' || identityStatus == 'BLOCKED';
          final isAdmin = isShipdeHopAdmin(authUser?.appMetadata);
          final adminPendingCount = isAdmin
              ? ref.watch(_adminPendingIdentityCountProvider).maybeWhen(
                    data: (count) => count,
                    orElse: () => null,
                  )
              : null;
          final identityLabel = identityVerified
              ? 'ShipdeHop Verified'
              : identityPending
                  ? 'Identity under review'
                  : identityNeedsAttention
                      ? 'Verification needs attention'
                      : 'Verification not completed';
          final levelNum = framework.currentLevel.index + 1;
          final progress = _levelProgress(framework.xp, framework.currentLevel.index);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [ShipdeHopColors.brandPrimary, Color(0xFF7A5CF0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    alignment: Alignment.center,
                    child: Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName, style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 21), maxLines: 2),
                        const SizedBox(height: 5),
                        if (email.isNotEmpty) Text(email, style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: identityVerified ? ShipdeHopColors.successBg : ShipdeHopColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(identityVerified ? Icons.verified_user_rounded : Icons.shield_outlined, size: 14, color: identityVerified ? ShipdeHopColors.success : ShipdeHopColors.textMuted),
                              const SizedBox(width: 6),
                              Flexible(child: Text(identityLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: identityVerified ? ShipdeHopColors.success : ShipdeHopColors.textSecondary))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!identityVerified) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const IdentityVerificationScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(identityPending ? 'View verification' : 'Verify identity'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: ShipdeHopColors.brandPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Trust Score',
                      '${trustScore.toInt()} / 100',
                      Icons.shield_rounded,
                      ShipdeHopColors.success,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SafetyPrivacyScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stat(
                      'XP Points',
                      '$xpPoints',
                      Icons.bolt_rounded,
                      ShipdeHopColors.squirrelOrange,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const HopClubScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stat(
                      'HOPS',
                      '$completed',
                      Icons.route_rounded,
                      ShipdeHopColors.brandPrimary,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const HopClubScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                key: const Key('profile_level_card'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const HopClubScreen(),
                  ),
                ),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Level $levelNum · ${framework.levelTitle}', style: ShipdeHopTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text('$xpPoints XP', style: ShipdeHopTypography.labelMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: progress, minHeight: 9, backgroundColor: const Color(0xFFF0EEF7), color: ShipdeHopColors.squirrelOrange),
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HopClubScreen())),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: const Color(0xFF3A1FD1), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.workspace_premium_rounded, color: ShipdeHopColors.squirrelOrange)),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Hop Club', style: ShipdeHopTypography.titleSmall.copyWith(color: Colors.white, fontSize: 15)),
                          const SizedBox(height: 5),
                          Text('Quests, badges and Hop Passport', style: ShipdeHopTypography.bodySmall.copyWith(color: Colors.white70)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('ACCOUNT', style: ShipdeHopTypography.labelSmall.copyWith(letterSpacing: 1.1)),
              const SizedBox(height: 10),
              _group([
                _ProfileRow(
                  Icons.account_balance_wallet_outlined,
                  'Payments & payouts',
                  'In-app payments not enabled',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => PaymentsPayoutsScreen(profile: profile))),
                ),
                _ProfileRow(
                  Icons.bookmark_outline_rounded,
                  'Saved Places',
                  'Pickup and drop-off addresses',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const SavedPlacesScreen())),
                ),
                _ProfileRow(
                  Icons.flight_takeoff_rounded,
                  'Travel Preferences',
                  'Corridors and luggage limits',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const TravelPreferencesScreen())),
                ),
                _ProfileRow(
                  Icons.settings_outlined,
                  'Settings',
                  'App and security preferences',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const AccountSettingsScreen())),
                ),
              ]),
              if (isAdmin) ...[
                const SizedBox(height: 18),
                Text('ADMIN', style: ShipdeHopTypography.labelSmall.copyWith(letterSpacing: 1.1)),
                const SizedBox(height: 10),
                _group([
                  _ProfileRow(
                    Icons.admin_panel_settings_outlined,
                    'Verification requests',
                    adminPendingCount == null
                        ? 'Checking pending requests…'
                        : adminPendingCount == 0
                            ? 'No pending requests'
                            : adminPendingCount.toString() + ' pending request' + (adminPendingCount == 1 ? '' : 's'),
                    onTap: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminIdentityReviewScreen(),
                        ),
                      );
                      ref.invalidate(_adminPendingIdentityCountProvider);
                    },
                  ),
                  _ProfileRow(
                    Icons.chat_rounded,
                    'WhatsApp OTP sender',
                    'Connection, pairing and health',
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminWhatsAppBridgeScreen(),
                      ),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 18),
              Text('SUPPORT', style: ShipdeHopTypography.labelSmall.copyWith(letterSpacing: 1.1)),
              const SizedBox(height: 10),
              _group([
                _ProfileRow(
                  Icons.help_outline_rounded,
                  'Help & support',
                  '',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HelpSupportScreen())),
                ),
                _ProfileRow(
                  Icons.privacy_tip_outlined,
                  'Safety & privacy',
                  '',
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const SafetyPrivacyScreen())),
                ),
              ]),
              if (AppConfig.enableDevTestAuth) ...[
                const SizedBox(height: 22),
                Material(
                  color: ShipdeHopColors.warningBg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: ShipdeHopColors.warning)),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.developer_mode_rounded, color: ShipdeHopColors.warning),
                    title: const Text('Developer Options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ShipdeHopColors.warning)),
                    subtitle: const Text('Test identities and lifecycle tools', style: TextStyle(fontSize: 11, color: ShipdeHopColors.warning)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_busy) const Center(child: CircularProgressIndicator()) else ...[
                              _devButton('Switch to User A', 'shipsterheadquarter@gmail.com'),
                              const SizedBox(height: 8),
                              _devButton('Switch to User B', 'susrijambagi@gmail.com'),
                              const SizedBox(height: 8),
                              _devButton('Switch to User C', 'e2e_carrier_user_c@shipdehop.internal'),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const LifecycleSimulatorScreen())),
                                icon: const Icon(Icons.developer_board_outlined),
                                label: const Text('Delivery Lifecycle Simulator'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(sessionManagerProvider.notifier).signOut();
                  try {
                    await ref.read(supabaseProvider).auth.signOut();
                  } catch (_) {}
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(foregroundColor: ShipdeHopColors.error, side: const BorderSide(color: ShipdeHopColors.error), minimumSize: const Size(double.infinity, 48)),
              ),
            ],
          );
        },
      ),
    );
  }

  double _levelProgress(int xp, int levelIndex) {
    const mins = [0, 100, 500, 1500, 4000, 10000];
    if (levelIndex >= mins.length - 1) return 1;
    final start = mins[levelIndex];
    final end = mins[levelIndex + 1];
    if (end <= start) return 1;
    return ((xp - start) / (end - start)).clamp(0.0, 1.0).toDouble();
  }

  Widget _stat(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : '$label, $value. Open details.',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          key: Key('profile_stat_${label.toLowerCase().replaceAll(' ', '_')}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        style: ShipdeHopTypography.labelSmall,
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: ShipdeHopColors.textMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style:
                        ShipdeHopTypography.displayMedium.copyWith(fontSize: 19),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(List<_ProfileRow> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          return Column(children: [
            InkWell(
              onTap: row.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Row(children: [
                  Icon(row.icon, size: 20, color: ShipdeHopColors.brandPrimary),
                  const SizedBox(width: 13),
                  Expanded(child: Text(row.label, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14.5))),
                  if (row.hint.isNotEmpty) Flexible(child: Text(row.hint, style: ShipdeHopTypography.bodySmall, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFC7C4D9)),
                ]),
              ),
            ),
            if (index < rows.length - 1) const Divider(height: 1, color: ShipdeHopColors.borderSubtle),
          ]);
        }),
      ),
    );
  }

  Widget _devButton(String label, String email) {
    return ElevatedButton(onPressed: () => _switchDevAccount(email), child: Text(label));
  }
}

class _ProfileRow {
  const _ProfileRow(this.icon, this.label, this.hint, {required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
}
