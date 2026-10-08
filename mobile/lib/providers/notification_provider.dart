import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_config.dart';
import '../core/profile_preferences.dart';
import '../models/notification_item.dart';
import 'app_providers.dart';

final notificationsProvider = FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return [];
  }

  try {
    final response = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final rows = response as List<dynamic>;
    var items = rows.map((e) => NotificationItem.fromJson(e as Map<String, dynamic>)).toList();

    final preferences = await ProfilePreferencesStore(userId).loadAccountPreferences();
    items = items.where((item) {
      final type = item.type.toUpperCase();
      final entity = item.entityType.toUpperCase();
      final isPayment = type.contains('PAYMENT') || type.contains('PAYOUT') || type.contains('ESCROW') || type.contains('REFUND') || type.contains('DISPUTE') || entity.contains('PAYMENT');
      final isMessage = type.contains('MESSAGE') || type.contains('CHAT') || entity.contains('CHAT');
      if (isPayment) return preferences.paymentAlerts;
      if (isMessage) return preferences.messageAlerts;
      return preferences.journeyUpdates;
    }).toList();

    if (AppConfig.showQaFixtures) return items;
    return items.where((n) => !AppConfig.isQaFixtureText(n.title) && !AppConfig.isQaFixtureText(n.body)).toList();
  } catch (_) {
    return [];
  }
});

final unreadNotificationsCountProvider = Provider.autoDispose<int>((ref) {
  final asyncNotifications = ref.watch(notificationsProvider);
  return asyncNotifications.maybeWhen(
    data: (list) => list.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});

class NotificationActions {
  final WidgetRef ref;
  NotificationActions(this.ref);

  Future<void> markRead(String notificationId) async {
    final supabase = ref.read(supabaseProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase.rpc<void>('mark_notification_read', params: {
        'p_notification_id': notificationId,
      });
      ref.invalidate(notificationsProvider);
    } catch (_) {
      try {
        await supabase
            .from('notifications')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('id', notificationId)
            .eq('user_id', userId);
        ref.invalidate(notificationsProvider);
      } catch (_) {}
    }
  }

  Future<void> markAllRead() async {
    final supabase = ref.read(supabaseProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await supabase.rpc<void>('mark_all_notifications_read');
      ref.invalidate(notificationsProvider);
    } catch (_) {
      try {
        await supabase
            .from('notifications')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('user_id', userId)
            .isFilter('read_at', null);
        ref.invalidate(notificationsProvider);
      } catch (_) {}
    }
  }
}
