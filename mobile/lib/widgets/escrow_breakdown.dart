import 'package:flutter/material.dart';
import '../core/money_formatter.dart';

class EscrowBreakdown extends StatelessWidget {
  const EscrowBreakdown({
    super.key,
    required this.base,
    required this.reward,
    required this.platformFee,
    required this.currency,
    this.showTitle = true,
  });

  final double base;
  final double reward;
  final double platformFee;
  final String currency;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final total = base + reward + platformFee;

    Widget buildRow(String label, double value, {bool strong = false}) {
      if (value <= 0 && !strong) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.bold : FontWeight.normal,
                color: strong ? Colors.black87 : Colors.black54,
              ),
            ),
            Text(
              MoneyFormatter.format(value, currency, showDecimalsIfNeeded: true),
              style: TextStyle(
                fontSize: strong ? 15 : 13,
                fontWeight: strong ? FontWeight.bold : FontWeight.w600,
                color: strong ? Colors.green.shade800 : Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.blue.shade50.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Text(
                    'Payment protection',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (base > 0) buildRow('Item reimbursement', base),
            if (reward > 0) buildRow('Traveller reward', reward),
            if (platformFee > 0) buildRow('ShipdeHop fee', platformFee),
            const Divider(height: 16),
            buildRow('Total secured', total, strong: true),
            const SizedBox(height: 8),
            Text(
              'Payment stays protected until the handoff is confirmed.',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
