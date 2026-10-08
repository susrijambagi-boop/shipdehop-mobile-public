import 'package:flutter/material.dart';
import '../core/app_config.dart';
import '../core/money_formatter.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import 'escrow_breakdown.dart';

enum PaymentState { review, processing, success, failure }

class PaymentReviewModal extends StatefulWidget {
  const PaymentReviewModal({
    super.key,
    required this.title,
    required this.counterpartyName,
    required this.baseAmount,
    required this.rewardAmount,
    required this.platformFee,
    required this.currency,
    required this.onConfirmPayment,
  });

  final String title;
  final String counterpartyName;
  final double baseAmount;
  final double rewardAmount;
  final double platformFee;
  final String currency;
  final Future<bool> Function() onConfirmPayment;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String counterpartyName,
    required double baseAmount,
    required double rewardAmount,
    required double platformFee,
    required String currency,
    required Future<bool> Function() onConfirmPayment,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentReviewModal(
        title: title,
        counterpartyName: counterpartyName,
        baseAmount: baseAmount,
        rewardAmount: rewardAmount,
        platformFee: platformFee,
        currency: currency,
        onConfirmPayment: onConfirmPayment,
      ),
    );
  }

  @override
  State<PaymentReviewModal> createState() => _PaymentReviewModalState();
}

class _PaymentReviewModalState extends State<PaymentReviewModal> {
  PaymentState _state = PaymentState.review;
  String _errorMessage = '';

  Future<void> _processPayment() async {
    setState(() => _state = PaymentState.processing);
    try {
      final ok = await widget.onConfirmPayment();
      if (ok && mounted) {
        setState(() => _state = PaymentState.success);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        setState(() {
          _state = PaymentState.failure;
          _errorMessage = 'Payment authorization could not be completed with the payment provider.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = PaymentState.failure;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.baseAmount + widget.rewardAmount + widget.platformFee;

    return Container(
      decoration: const BoxDecoration(
        color: ShipdeHopColors.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ShipdeHopColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_state == PaymentState.review) ...[
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Payment Review', style: ShipdeHopTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Order & Counterparty Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ShipdeHopColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ShipdeHopColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: ShipdeHopColors.brandPrimary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: ShipdeHopTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
                        Text('With ${widget.counterpartyName}', style: ShipdeHopTypography.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Escrow Breakdown
            EscrowBreakdown(
              base: widget.baseAmount,
              reward: widget.rewardAmount,
              platformFee: widget.platformFee,
              currency: widget.currency,
              showTitle: true,
            ),
            const SizedBox(height: 14),

            // Payment Method Selector
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ShipdeHopColors.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ShipdeHopColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_rounded, color: ShipdeHopColors.brandDark, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HopPay Escrow Account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        Text(AppConfig.enableDevTestAuth ? 'Visa •••• 4281 (Test Provider)' : 'Select Payment Method', style: const TextStyle(fontSize: 11, color: ShipdeHopColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded, color: ShipdeHopColors.success, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // One Dominant CTA
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShipdeHopColors.brandPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _processPayment,
                child: Text(
                  'Pay ${MoneyFormatter.format(total, widget.currency)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else if (_state == PaymentState.processing) ...[
            const SizedBox(height: 30),
            const Center(
              child: CircularProgressIndicator(color: ShipdeHopColors.brandPrimary),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Securing funds in HopPay Escrow...',
                style: ShipdeHopTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Please do not close this window.',
                style: ShipdeHopTypography.bodySmall,
              ),
            ),
            const SizedBox(height: 30),
          ] else if (_state == PaymentState.success) ...[
            const SizedBox(height: 20),
            const Center(
              child: Icon(Icons.check_circle_rounded, color: ShipdeHopColors.success, size: 56),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Payment Secured',
                style: ShipdeHopTypography.titleLarge.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.success),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${MoneyFormatter.format(total, widget.currency)} held safely until confirmed handoff.',
                textAlign: TextAlign.center,
                style: ShipdeHopTypography.bodyMedium,
              ),
            ),
            const SizedBox(height: 20),
          ] else if (_state == PaymentState.failure) ...[
            const SizedBox(height: 20),
            const Center(
              child: Icon(Icons.error_outline_rounded, color: ShipdeHopColors.error, size: 56),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Payment Could Not Be Completed',
                style: ShipdeHopTypography.titleLarge.copyWith(fontWeight: FontWeight.bold, color: ShipdeHopColors.error),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ShipdeHopColors.errorBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(_errorMessage, style: const TextStyle(color: ShipdeHopColors.error, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  const Text('No funds were charged. Your transaction remains safe in draft state.', style: TextStyle(fontSize: 11, color: ShipdeHopColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: ShipdeHopColors.brandPrimary, foregroundColor: Colors.white),
                    onPressed: () => setState(() => _state = PaymentState.review),
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
