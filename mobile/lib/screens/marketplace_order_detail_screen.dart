import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/money_formatter.dart';
import 'chat_screen.dart';
import 'delivery_details_screen.dart';

class MarketplaceOrderDetailScreen extends ConsumerWidget {
  const MarketplaceOrderDetailScreen({
    super.key,
    required this.orderId,
    this.orderData,
  });

  final String orderId;
  final Map<String, dynamic>? orderData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = orderData ?? {};
    final title = item['title']?.toString() ?? item['itemDescription']?.toString() ?? 'Marketplace Item';
    final roleLabel = item['roleLabel']?.toString() ?? 'Buyer';
    final quantity = (item['quantity'] as num?)?.toInt() ?? (item['listingQuantity'] as num?)?.toInt() ?? 1;
    final totalAmount = (item['amount'] as num?)?.toDouble() ?? (item['total_amount'] as num?)?.toDouble() ?? 0.0;
    final basePrice = (item['base_price'] as num?)?.toDouble() ?? (totalAmount * 0.8);
    final rewardFee = (item['reward_fee'] as num?)?.toDouble() ?? (totalAmount * 0.15);
    final platformFee = (item['platform_fee'] as num?)?.toDouble() ?? (totalAmount * 0.05);
    final currency = item['currency']?.toString() ?? 'INR';
    final fulfillmentMode = item['fulfillment_mode']?.toString() ?? item['fulfillmentMode']?.toString() ?? 'LOCAL_HANDOFF';
    final userStatusLabel = item['userStatusLabel']?.toString() ?? item['fulfillment_status']?.toString() ?? 'Payment Secured • Local Handoff Pending';
    final escrowStatus = item['escrow_status']?.toString() ?? 'LOCKED';
    final threadId = item['threadId']?.toString();
    final counterparty = item['counterparty'] as Map<String, dynamic>? ?? {};
    final counterpartyName = counterparty['fullName']?.toString() ?? 'Marketplace Partner';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace Transaction Detail'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Primary Header Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.purple.shade300),
                              ),
                              child: Text(
                                'MARKETPLACE • $roleLabel',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade800,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade600),
                              ),
                              child: Text(
                                userStatusLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Quantity Purchased: $quantity',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fulfillment Mode: ${fulfillmentMode == 'LOCAL_HANDOFF' ? 'Local Handoff (Direct Escrow)' : 'Hopster Crowdship Delivery'}',
                          style: TextStyle(fontSize: 14, color: Colors.indigo.shade800, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Financial & Escrow Breakdown Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Financial & Escrow Breakdown',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const Divider(height: 24),
                        _buildRow('Item Base Price (x$quantity)', MoneyFormatter.format(basePrice, currency)),
                        if (rewardFee > 0) ...[
                          const SizedBox(height: 8),
                          _buildRow('Delivery Reward Fee', MoneyFormatter.format(rewardFee, currency)),
                        ],
                        const SizedBox(height: 8),
                        _buildRow('Platform Service Fee', MoneyFormatter.format(platformFee, currency)),
                        const Divider(height: 24),
                        _buildRow(
                          'Total Transaction Amount',
                          MoneyFormatter.format(totalAmount, currency),
                          isBold: true,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_clock_outlined, color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Escrow Payment Status: $escrowStatus • Funds held safely in HopPay escrow until handoff verification.',
                                  style: TextStyle(fontSize: 12, color: Colors.brown.shade900, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Actions Card (Shipment & Chat)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Counterparty & Actions: $counterpartyName',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (threadId != null && threadId.isNotEmpty) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: const Icon(Icons.chat_bubble_outline),
                                  label: const Text('Open Conversation'),
                                  onPressed: () {
                                    Navigator.push<void>(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => ChatScreen(
                                          threadId: threadId,
                                          orderId: orderId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (fulfillmentMode == 'HOPSTER_DELIVERY' || orderId.isNotEmpty)
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: const Icon(Icons.local_shipping_outlined),
                                  label: const Text('View Delivery Tracking'),
                                  onPressed: () {
                                    Navigator.push<void>(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => DeliveryDetailsScreen(orderId: orderId),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: Colors.grey.shade800,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
