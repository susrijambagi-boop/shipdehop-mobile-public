import 'package:flutter/material.dart';
import '../core/policy_resolver.dart';

class PolicySummaryCard extends StatelessWidget {
  const PolicySummaryCard({
    super.key,
    required this.policy,
  });

  final ResolvedPolicy policy;

  @override
  Widget build(BuildContext context) {
    if (!policy.isSupported) {
      return Card(
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.public_off_rounded, color: Colors.brown),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outside ShipdeHop launch area',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      policy.unsupportedReason ??
                          'ShipdeHop is currently available only in India.',
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: Colors.indigo, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'India launch area',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${policy.countryName} • Currency: ${policy.currency}',
                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                policy.currency,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
