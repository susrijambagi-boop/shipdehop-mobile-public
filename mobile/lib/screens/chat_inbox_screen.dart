import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_config.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/ui/shd_empty_state.dart';
import '../widgets/mascot/mascot_empty_state.dart';
import 'chat_screen.dart';

class ChatInboxScreen extends ConsumerWidget {
  const ChatInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(globalChatInboxProvider);

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Messages', style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Refresh messages',
            onPressed: () {
              ref.invalidate(globalChatInboxProvider);
              ref.invalidate(unreadMessagesCountProvider);
            },
            icon: const Icon(Icons.refresh_rounded, color: ShipdeHopColors.textSecondary),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: ShipdeHopColors.brandPrimary,
        onRefresh: () async {
          ref.invalidate(globalChatInboxProvider);
          ref.invalidate(unreadMessagesCountProvider);
        },
        child: inboxAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 120),
            children: [
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(22)),
                  child: const Icon(Icons.forum_rounded, color: ShipdeHopColors.brandPrimary, size: 30),
                ),
              ),
              const SizedBox(height: 18),
              Text('Loading conversations…', textAlign: TextAlign.center, style: ShipdeHopTypography.titleMedium),
              const SizedBox(height: 6),
              Text('Parcel, ride and marketplace chats will appear here.', textAlign: TextAlign.center, style: ShipdeHopTypography.bodyMedium),
            ],
          ),
          error: (err, stack) => ShdEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load messages',
            subtitle: 'Your conversations are safe. Pull to refresh or try again.',
            buttonLabel: 'Retry',
            onPressed: () => ref.invalidate(globalChatInboxProvider),
          ),
          data: (rawThreads) {
            final threads = rawThreads.where((t) {
              if (AppConfig.showQaFixtures) return true;
              final ctx = t['contextTitle']?.toString() ?? '';
              final lastBody = (t['lastMessage'] as Map<String, dynamic>?)?['body']?.toString() ?? '';
              return !AppConfig.isQaFixtureText(ctx) && !AppConfig.isQaFixtureText(lastBody);
            }).toList();

            if (threads.isEmpty) return MascotEmptyState.noMessages();

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 60, color: ShipdeHopColors.borderSubtle),
              itemBuilder: (context, index) {
                final t = threads[index];
                final threadId = t['id']?.toString() ?? '';
                final orderId = t['orderId']?.toString() ?? '';
                final module = t['module']?.toString() ?? 'PARCELPOOL';
                final contextTitle = t['contextTitle']?.toString() ?? 'Transaction';
                final counterparty = t['counterparty'] as Map<String, dynamic>? ?? const <String, dynamic>{};
                final rawName = counterparty['fullName']?.toString() ?? '';
                final personName = _humanName(rawName, module);
                final lastMsg = t['lastMessage'] as Map<String, dynamic>?;
                final lastBody = lastMsg?['body']?.toString();
                final unread = (t['unreadCount'] as num?)?.toInt() ?? 0;
                final moduleColor = _moduleColor(module);

                return InkWell(
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(
                        orderId: orderId,
                        threadId: threadId,
                        counterpartyName: personName,
                        contextTitle: _friendlyContext(contextTitle, module),
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 78),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: moduleColor.withValues(alpha: .12),
                            child: Text(personName.isNotEmpty ? personName[0].toUpperCase() : 'U', style: TextStyle(color: moduleColor, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(personName, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text('2m', style: ShipdeHopTypography.bodySmall.copyWith(color: ShipdeHopColors.textMuted)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(_friendlyContext(contextTitle, module), style: ShipdeHopTypography.labelMedium.copyWith(color: moduleColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(child: Text(lastBody?.isNotEmpty == true ? lastBody! : 'Tap to open conversation', style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    if (unread > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(color: ShipdeHopColors.brandPrimary, shape: BoxShape.circle),
                                        child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _humanName(String rawName, String module) {
    if (rawName.isNotEmpty && rawName != 'Hopster Carrier' && rawName != 'Counterparty' && rawName != 'Shipster Headquarter') return rawName;
    if (module == 'MARKETPLACE') return 'Seller';
    if (module == 'CARPOOL') return 'Driver';
    return 'Traveller';
  }

  static String _friendlyContext(String raw, String module) {
    if (AppConfig.isQaFixtureText(raw) || raw.toLowerCase().contains('transaction')) {
      if (module == 'MARKETPLACE') return 'Marketplace order';
      if (module == 'CARPOOL') return 'CarPool ride';
      return 'Parcel delivery';
    }
    return raw.replaceAll('PARCELPOOL', 'Parcel').replaceAll('MARKETPLACE', 'Marketplace').replaceAll('CARPOOL', 'CarPool');
  }

  static Color _moduleColor(String module) {
    if (module == 'MARKETPLACE') return ShipdeHopColors.marketplaceAccent;
    if (module == 'CARPOOL') return ShipdeHopColors.carpoolAccent;
    return ShipdeHopColors.brandPrimary;
  }
}
