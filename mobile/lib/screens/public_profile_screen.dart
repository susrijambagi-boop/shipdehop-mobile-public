import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/phase15_providers.dart';

class PublicProfileSheet extends ConsumerWidget {
  const PublicProfileSheet({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicProfileAsync = ref.watch(publicProfileFamilyProvider(userId));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: publicProfileAsync.when(
        loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        error: (err, stack) => SizedBox(
          height: 200,
          child: Center(child: Text('Failed to load profile: $err')),
        ),
        data: (profile) {
          final fullName = profile['fullName']?.toString() ?? 'ShipdeHop User';
          final ekycTier = profile['ekycTier']?.toString() ?? 'TIER_1';
          final trustScore = (profile['trustScore'] as num?)?.toDouble() ?? 50.0;
          final completedCount = (profile['completedTransactionsCount'] as num?)?.toInt() ?? 0;
          final createdAt = profile['createdAt']?.toString() ?? '';

          Color tierColor;
          switch (ekycTier) {
            case 'TIER_3':
              tierColor = Colors.purple;
              break;
            case 'TIER_2':
              tierColor = Colors.blue;
              break;
            default:
              tierColor = Colors.orange;
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),

              // Avatar & Name
              CircleAvatar(
                radius: 36,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                fullName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Member since ${createdAt.length >= 10 ? createdAt.substring(0, 10) : "2026"}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // Trust & Verification Stats Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Trust Score
                    Column(
                      children: [
                        const Text('Trust Score', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.shield, color: Colors.green, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${trustScore.toStringAsFixed(1)} / 100',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),

                    // eKYC Tier
                    Column(
                      children: [
                        const Text('Verification', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tierColor),
                          ),
                          child: Text(
                            ekycTier,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: tierColor),
                          ),
                        ),
                      ],
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.shade300),

                    // Completed Transactions
                    Column(
                      children: [
                        const Text('Completed', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          '$completedCount Orders',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close Profile'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
