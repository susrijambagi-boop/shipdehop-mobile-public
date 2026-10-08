import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../providers/notification_provider.dart';
import '../providers/phase15_providers.dart';
import '../screens/chat_inbox_screen.dart';
import '../screens/notifications_sheet.dart';
import '../screens/profile_screen.dart';
import '../theme/shipdehop_colors.dart';

class GlobalHeader extends ConsumerWidget implements PreferredSizeWidget {
  const GlobalHeader({
    super.key,
    required this.onSelectTab,
    this.title,
    this.showBrand = true,
  });

  final void Function(int tabIndex) onSelectTab;
  final String? title;
  final bool showBrand;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final userEmail = user?.email ?? '';
    final framework = ref.watch(gamificationFrameworkProvider);
    final level = framework.currentLevel.index + 1;
    final unreadMessages = ref.watch(unreadMessagesCountProvider).value ?? 0;
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);

    return AppBar(
      toolbarHeight: 60,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: ShipdeHopColors.background,
      titleSpacing: 16,
      title: showBrand
          ? RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.7),
                children: [
                  TextSpan(text: 'Shipde', style: TextStyle(color: ShipdeHopColors.textPrimary)),
                  TextSpan(text: 'Hop', style: TextStyle(color: ShipdeHopColors.squirrelOrange)),
                ],
              ),
            )
          : Text(
              title ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShipdeHopColors.textSecondary),
            ),
      actions: [
        _HeaderSquare(
          tooltip: 'Notifications',
          icon: Icons.notifications_none_rounded,
          badgeCount: unreadNotifications,
          badgeColor: ShipdeHopColors.squirrelOrange,
          badgeTextColor: ShipdeHopColors.brandDark,
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: ShipdeHopColors.surfaceCard,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (_) => const NotificationsSheet(),
            );
          },
        ),
        const SizedBox(width: 8),
        _HeaderSquare(
          tooltip: 'Messages',
          icon: Icons.chat_bubble_outline_rounded,
          badgeCount: unreadMessages,
          badgeColor: ShipdeHopColors.brandPrimary,
          badgeTextColor: Colors.white,
          onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const ChatInboxScreen())),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Semantics(
            label: 'Profile, level $level',
            button: true,
            child: InkWell(
              onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          startAngle: 0,
                          endAngle: 6.283185307179586,
                          stops: [0, .71, .71, 1],
                          colors: [ShipdeHopColors.squirrelOrange, ShipdeHopColors.squirrelOrange, Color(0xFFE4E1EE), Color(0xFFE4E1EE)],
                        ),
                      ),
                    ),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ShipdeHopColors.background, width: 2.5),
                        gradient: const LinearGradient(colors: [ShipdeHopColors.brandPrimary, Color(0xFF7A5CF0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: ShipdeHopColors.brandDark, borderRadius: BorderRadius.circular(99), border: Border.all(color: ShipdeHopColors.background, width: 2)),
                        alignment: Alignment.center,
                        child: Text('$level', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderSquare extends StatelessWidget {
  const _HeaderSquare({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.badgeCount,
    required this.badgeColor,
    required this.badgeTextColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final Color badgeColor;
  final Color badgeTextColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 8, offset: Offset(0, 2))],
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: ShipdeHopColors.textPrimary, size: 20),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 6,
                  right: 5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 1.5)),
                    alignment: Alignment.center,
                    child: Text(badgeCount > 99 ? '99+' : '$badgeCount', style: TextStyle(color: badgeTextColor, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
