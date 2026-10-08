import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../core/app_config.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/profile/profile_components.dart';

class PaymentsPayoutsScreen extends ConsumerWidget {
  const PaymentsPayoutsScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.paymentProvider == 'DISABLED') {
      return const ProfileDetailScaffold(
        title: 'Payments & payouts',
        children: [
          ProfileSectionTitle('How money works right now'),
          SizedBox(height: 8),
          ProfileInfoCard(
            icon: Icons.handshake_outlined,
            title: 'Agree and settle directly',
            body:
                'ShipdeHop does not collect, charge, hold, escrow, release, refund or pay out money in the current release. Buyers, senders, travellers, drivers and sellers agree the amount and payment method directly with each other and settle outside ShipdeHop.',
          ),
          SizedBox(height: 10),
          ProfileInfoCard(
            icon: Icons.shield_outlined,
            title: 'Outside payments are not protected by ShipdeHop',
            body:
                'Matching, chat, route coordination, Trust Score and OTP/QR handoff confirmation do not guarantee or insure a payment made outside the app. Confirm the person, item, amount and handoff terms before paying.',
          ),
          SizedBox(height: 10),
          ProfileInfoCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No payout account is required',
            body:
                'ShipdeHop does not ask you to connect a card or payout account while in-app money movement is disabled. If you choose to pay outside ShipdeHop, use a payment method you trust and handle any refund or payment dispute through that method and the counterparty.',
          ),
        ],
      );
    }

    final ordersAsync = ref.watch(userOrdersProvider);
    final userId = ref.watch(authUserProvider).value?.id ?? '';
    final rawAccounts = profile['paymentAccounts'];
    final accounts = rawAccounts is List ? rawAccounts.whereType<Map>().toList() : const <Map>[];

    return ProfileDetailScaffold(
      title: 'Payments & payouts',
      children: [
        const ProfileSectionTitle('Payments'),
        const SizedBox(height: 8),
        const ProfileInfoCard(
          icon: Icons.info_outline_rounded,
          title: 'Payment activity',
          body:
              'This screen reflects the payment provider configured for this build. Payment status should be treated as provider-backed only when the configured payment flow completes successfully.',
        ),
        const SizedBox(height: 12),
        _PayoutAccountCard(accounts: accounts),
        const SizedBox(height: 22),
        const ProfileSectionTitle('Your transactions'),
        const SizedBox(height: 8),
        ordersAsync.when(
          loading: () => const ProfileLoadingCard(label: 'Loading payment activity…'),
          error: (error, stackTrace) => ProfileRetryCard(
            title: 'Could not load payment activity',
            onRetry: () => ref.invalidate(userOrdersProvider),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return const ProfileInfoCard(
                icon: Icons.receipt_long_outlined,
                title: 'No payment activity yet',
                body: 'Orders, refunds and released payments will appear here automatically.',
              );
            }
            final locked = orders.where((o) => o['escrow_status']?.toString() == 'LOCKED').length;
            final released = orders.where((o) => o['escrow_status']?.toString() == 'RELEASED').length;
            final refunded = orders.where((o) => o['escrow_status']?.toString() == 'REFUNDED').length;
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: ProfileMetricCard(label: 'Protected', value: '$locked', icon: Icons.lock_outline_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: ProfileMetricCard(label: 'Released', value: '$released', icon: Icons.check_circle_outline_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: ProfileMetricCard(label: 'Refunded', value: '$refunded', icon: Icons.replay_rounded)),
                  ],
                ),
                const SizedBox(height: 12),
                ...orders.take(20).map((order) => _TransactionCard(order: order, userId: userId)),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Amounts shown come from your ShipdeHop order records. Sensitive card or bank numbers are never displayed here.',
          style: ShipdeHopTypography.bodySmall,
        ),
      ],
    );
  }
}

class _PayoutAccountCard extends StatelessWidget {
  const _PayoutAccountCard({required this.accounts});

  final List<Map> accounts;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const ProfileInfoCard(
        icon: Icons.account_balance_outlined,
        title: 'No payout account connected',
        body: 'You can still use ShipdeHop as a buyer or sender. A verified payout account is required before money can be released to you as a seller, driver or carrier.',
      );
    }

    return Column(
      children: accounts.map((account) {
        final provider = account['provider']?.toString().trim();
        final verified = account['verified'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: verified ? ShipdeHopColors.successBg : ShipdeHopColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.account_balance_wallet_outlined, color: verified ? ShipdeHopColors.success : ShipdeHopColors.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider == null || provider.isEmpty ? 'Payout account' : provider.toUpperCase(), style: ShipdeHopTypography.titleSmall),
                    const SizedBox(height: 3),
                    Text(verified ? 'Verified and eligible for payouts' : 'Verification required before payouts', style: ShipdeHopTypography.bodySmall),
                  ],
                ),
              ),
              Icon(verified ? Icons.verified_rounded : Icons.info_outline_rounded, color: verified ? ShipdeHopColors.success : ShipdeHopColors.textMuted),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.order, required this.userId});

  final Map<String, dynamic> order;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final status = order['escrow_status']?.toString() ?? 'PENDING';
    final type = order['order_type']?.toString() ?? 'ORDER';
    final amount = (order['total_amount'] as num?)?.toDouble();
    final currency = order['currency']?.toString() ?? '';
    final providerId = order['provider_id']?.toString() ?? '';
    final incoming = providerId.isNotEmpty && providerId == userId;
    final created = profileFormatDate(order['created_at']?.toString());
    final decimals = amount != null && amount.truncateToDouble() != amount;
    final amountLabel = amount == null ? 'Amount unavailable' : '${currency.isEmpty ? '' : '$currency '}${amount.toStringAsFixed(decimals ? 2 : 0)}';

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'RELEASED':
        statusColor = ShipdeHopColors.success;
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'REFUNDED':
        statusColor = ShipdeHopColors.warning;
        statusIcon = Icons.replay_rounded;
        break;
      case 'LOCKED':
        statusColor = ShipdeHopColors.brandPrimary;
        statusIcon = Icons.lock_outline_rounded;
        break;
      case 'DISPUTED':
        statusColor = ShipdeHopColors.error;
        statusIcon = Icons.report_problem_outlined;
        break;
      default:
        statusColor = ShipdeHopColors.textMuted;
        statusIcon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${profileHumanize(type)} · ${incoming ? 'Receiving' : 'Paying'}', style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14)),
                const SizedBox(height: 3),
                Text('${profileHumanize(status)}${created.isEmpty ? '' : ' · $created'}', style: ShipdeHopTypography.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(amountLabel, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
