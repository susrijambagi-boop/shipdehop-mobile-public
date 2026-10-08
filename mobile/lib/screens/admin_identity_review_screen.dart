import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/admin_access.dart';
import '../providers/app_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';

class AdminIdentityReviewScreen extends ConsumerStatefulWidget {
  const AdminIdentityReviewScreen({super.key});

  @override
  ConsumerState<AdminIdentityReviewScreen> createState() => _AdminIdentityReviewScreenState();
}

class _AdminIdentityReviewScreenState extends ConsumerState<AdminIdentityReviewScreen> {
  bool _loading = true;
  String? _error;
  List<_IdentityReviewItem> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final client = ref.read(supabaseProvider);
      final user = client.auth.currentUser;
      if (!isShipdeHopAdmin(user?.appMetadata)) {
        throw const _AdminReviewException('Admin role required.');
      }

      final identityRows = await client
          .from('user_identities')
          .select('id,user_id,identity_method,verification_status,consented_at,updated_at,review_notes')
          .eq('verification_status', 'PENDING_REVIEW')
          .order('updated_at', ascending: true)
          .limit(100);

      final rows = (identityRows as List<dynamic>).cast<Map<String, dynamic>>();
      final userIds = rows
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .toList();

      final profiles = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        try {
          final profileRows = await client
              .from('users')
              .select('id,email,full_name')
              .inFilter('id', userIds);
          for (final row
              in (profileRows as List<dynamic>).cast<Map<String, dynamic>>()) {
            final id = row['id']?.toString();
            if (id != null) profiles[id] = row;
          }
        } catch (_) {
          // Optional display metadata must never hide the admin review queue.
          // The identity RPC is keyed by user_id and remains usable.
        }
      }

      final items = rows.map((row) {
        final userId = row['user_id']?.toString() ?? '';
        final profile = profiles[userId];
        return _IdentityReviewItem(
          id: row['id']?.toString() ?? '',
          userId: userId,
          email: profile?['email']?.toString(),
          fullName: profile?['full_name']?.toString(),
          method: row['identity_method']?.toString() ?? 'OTHER_GOV_ID',
          status: row['verification_status']?.toString() ?? 'PENDING_REVIEW',
          consentedAt: DateTime.tryParse(row['consented_at']?.toString() ?? ''),
        );
      }).toList();

      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is _AdminReviewException ? e.message : 'Could not load identity review requests.';
        _loading = false;
      });
    }
  }

  Future<void> _review(_IdentityReviewItem item, String decision) async {
    final approving = decision == 'APPROVE';
    if (approving) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirm manual verification'),
              content: const Text(
                'This screen does not contain government-ID evidence. Approve only after you have independently completed the approved manual identity check for this person. This records a ShipdeHop manual verification, not an Aadhaar or government verification.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I completed the check')),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
    }

    final controller = TextEditingController(
      text: approving
          ? 'Manual identity check completed by ShipdeHop Ops'
          : 'Manual identity review could not be approved',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approving ? 'Approval note' : 'Rejection note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Audit note', helperText: 'Required. Minimum 10 characters.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 10) Navigator.pop(context, value);
            },
            child: Text(approving ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supabaseProvider).rpc<dynamic>(
        'admin_review_identity',
        params: {'p_user_id': item.userId, 'p_decision': decision, 'p_note': note},
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(approving ? 'Identity request approved and audited.' : 'Identity request rejected and audited.'),
        backgroundColor: approving ? ShipdeHopColors.success : ShipdeHopColors.error,
      ));
      await _load();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not update this verification request.'),
        backgroundColor: ShipdeHopColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authUserProvider).value;
    final isAdmin = isShipdeHopAdmin(authUser?.appMetadata);

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        title: const Text('Verification requests'),
        actions: [IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: !isAdmin
          ? const _AdminRequired()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? const _EmptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return _ReviewCard(
                                item: item,
                                onApprove: () => _review(item, 'APPROVE'),
                                onReject: () => _review(item, 'REJECT'),
                              );
                            },
                          ),
                        ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, required this.onApprove, required this.onReject});
  final _IdentityReviewItem item;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final title = (item.fullName?.trim().isNotEmpty ?? false)
        ? item.fullName!.trim()
        : (item.email?.trim().isNotEmpty ?? false)
            ? item.email!.trim()
            : 'User ${_shortId(item.userId)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShipdeHopColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified_user_outlined, color: ShipdeHopColors.brandPrimary),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: ShipdeHopTypography.titleSmall)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: ShipdeHopColors.warningBg, borderRadius: BorderRadius.circular(99)),
              child: Text(item.status, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: ShipdeHopColors.warning)),
            ),
          ]),
          if (item.email?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(item.email!, style: ShipdeHopTypography.bodySmall),
          ],
          const SizedBox(height: 10),
          Text('Method: ${item.method}', style: ShipdeHopTypography.bodySmall),
          if (item.consentedAt != null)
            Text('Requested: ${_dateLabel(item.consentedAt!)}', style: ShipdeHopTypography.bodySmall),
          const SizedBox(height: 10),
          Text(
            'No government-ID evidence is stored on this screen. Complete the approved manual check before approval.',
            style: ShipdeHopTypography.bodySmall.copyWith(color: ShipdeHopColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: onReject,
              style: OutlinedButton.styleFrom(foregroundColor: ShipdeHopColors.error),
              child: const Text('Reject'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: onApprove, child: const Text('Approve'))),
          ]),
        ],
      ),
    );
  }

  static String _shortId(String value) => value.length <= 8 ? value : value.substring(0, 8);
  static String _dateLabel(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _IdentityReviewItem {
  const _IdentityReviewItem({
    required this.id,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.method,
    required this.status,
    required this.consentedAt,
  });
  final String id;
  final String userId;
  final String? email;
  final String? fullName;
  final String method;
  final String status;
  final DateTime? consentedAt;
}

class _AdminRequired extends StatelessWidget {
  const _AdminRequired();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.all(24), child: Text('Admin access is required to review identity requests.', textAlign: TextAlign.center)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.all(24), child: Text('No identity requests are waiting for review.', textAlign: TextAlign.center)),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class _AdminReviewException implements Exception {
  const _AdminReviewException(this.message);
  final String message;
}