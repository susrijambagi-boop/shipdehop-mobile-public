import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_config.dart';
import '../models/gamification_framework.dart';
import 'app_providers.dart';

class HistoryFilterStatusNotifier extends Notifier<String> {
  @override
  String build() => 'ALL';
  void setStatus(String status) => state = status;
}

final unifiedHistoryFilterStatusProvider = NotifierProvider<HistoryFilterStatusNotifier, String>(HistoryFilterStatusNotifier.new);

class HistoryFilterModuleNotifier extends Notifier<String> {
  @override
  String build() => 'ALL';
  void setModule(String module) => state = module;
}

final unifiedHistoryFilterModuleProvider = NotifierProvider<HistoryFilterModuleNotifier, String>(HistoryFilterModuleNotifier.new);

final unifiedHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final statusFilter = ref.watch(unifiedHistoryFilterStatusProvider);
  final moduleFilter = ref.watch(unifiedHistoryFilterModuleProvider);

  List<Map<String, dynamic>> items = [];
  try {
    final client = ref.read(apiClientProvider);
    final query = <String, String>{
      'statusFilter': statusFilter,
      'moduleFilter': moduleFilter,
    };
    final uri = Uri(path: '/history', queryParameters: query);
    final res = await client.get(uri.toString());

    List rawList = [];
    if (res is List) {
      rawList = res;
    } else if (res is Map && res['history'] is List) {
      rawList = res['history'] as List;
    }

    if (rawList.isNotEmpty) {
      items = rawList.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
  } catch (_) {
    // Ignore fallback errors
  }

  if (items.isEmpty) {
    try {
      final legacyOrders = await ref.read(userOrdersProvider.future);
      if (legacyOrders.isNotEmpty) {
        items = legacyOrders;
      }
    } catch (_) {}
  }

  if (AppConfig.showQaFixtures) return items;
  return items.where((e) {
    final title = e['title']?.toString() ?? e['summary']?.toString() ?? '';
    return !AppConfig.isQaFixtureText(title);
  }).toList();
});

final globalChatInboxProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authUser = ref.watch(authUserProvider).value;
  if (authUser == null) return [];

  try {
    final client = ref.read(apiClientProvider);
    final res = await client.get('/chat/threads');
    final threads = (res['threads'] as List? ?? []).cast<dynamic>();
    final items = threads.map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (AppConfig.showQaFixtures) return items;
    return items.where((t) {
      final title = t['title']?.toString() ?? t['last_message']?.toString() ?? t['participant_name']?.toString() ?? '';
      return !AppConfig.isQaFixtureText(title);
    }).toList();
  } catch (e) {
    return [];
  }
});

final unreadMessagesCountProvider = FutureProvider<int>((ref) async {
  final authUser = ref.watch(authUserProvider).value;
  if (authUser == null) return 0;

  try {
    final client = ref.read(apiClientProvider);
    final res = await client.get('/chat/unread-count');
    if (res is Map && res['unreadCount'] != null) {
      return (res['unreadCount'] as num).toInt();
    }
    return 0;
  } catch (e) {
    return 0;
  }
});

final ownProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authUser = ref.watch(authUserProvider).value;

  Map<String, dynamic>? data;
  try {
    final client = ref.read(apiClientProvider);
    final res = await client.get('/profile/me');
    if (res is Map && res.isNotEmpty) {
      data = res.cast<String, dynamic>();
    }
  } catch (_) {}

  final email = data?['email']?.toString() ?? authUser?.email ?? '';
  final metaName = authUser?.userMetadata?['full_name']?.toString() ?? authUser?.userMetadata?['name']?.toString();
  final fallbackName = metaName?.trim().isNotEmpty == true
      ? metaName!.trim()
      : (email.contains('@') ? email.split('@').first.replaceAll('.', ' ') : 'ShipdeHop User');
  final identityVerified = data?['isIdentityVerified'] == true;
  final identityStatus = data?['identityVerificationStatus']?.toString() ?? 'NOT_STARTED';
  final rawTier = data?['ekycTier'] ?? data?['ekyc_tier'];

  return {
    'id': data?['id'] ?? authUser?.id ?? '',
    'email': email,
    'fullName': data?['fullName'] ?? data?['full_name'] ?? fallbackName,
    'phone': data?['phone'],
    'avatarUrl': data?['avatarUrl'] ?? data?['avatar_url'],
    'ekycTier': identityVerified ? (rawTier ?? 'TIER_1') : 'TIER_0',
    'isIdentityVerified': identityVerified,
    'identityVerificationStatus': identityStatus,
    'trustScore': (data?['trustScore'] ?? data?['trust_score'] as num?)?.toDouble() ?? 0.0,
    'xpPoints': (data?['xpPoints'] ?? data?['xp_points'] as num?)?.toInt() ?? 0,
    'completedTransactionsCount': (data?['completedTransactionsCount'] as num?)?.toInt() ?? 0,
    'hasVerifiedPaymentAccount': data?['hasVerifiedPaymentAccount'] ?? false,
    'paymentAccounts': data?['paymentAccounts'] ?? const <dynamic>[],
    'createdAt': data?['createdAt'] ?? data?['created_at'],
  };
});

final publicProfileFamilyProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  if (userId.isEmpty) return {};

  try {
    final client = ref.read(apiClientProvider);
    final res = await client.get('/profile/public/$userId');
    return (res as Map).cast<String, dynamic>();
  } catch (e) {
    return {
      'id': userId,
      'fullName': 'ShipdeHop member',
      'ekycTier': 'UNVERIFIED',
      'trustScore': 0.0,
      'completedTransactionsCount': 0,
    };
  }
});

final gamificationFrameworkProvider = Provider<GamificationFramework>((ref) {
  final profile = ref.watch(ownProfileProvider).value;
  final history = ref.watch(unifiedHistoryProvider).value ?? [];
  final completedCount = history.where((h) => h['status'] == 'COMPLETED' || h['status'] == 'RELEASED').length;

  final xp = ((profile?['xpPoints'] ?? profile?['xp_points']) as num?)?.toInt() ?? (completedCount * 100);
  final isEkyc = profile?['isIdentityVerified'] == true;

  return GamificationFramework.deriveFromRealData(
    isEkycVerified: isEkyc,
    completedJourneysCount: completedCount,
    completedParcelsCount: completedCount,
    completedHandoffsCount: completedCount,
    explicitXp: xp,
  );
});
