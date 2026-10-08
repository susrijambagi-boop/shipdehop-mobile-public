import 'package:flutter/material.dart';
import 'shipdehop_mascot.dart';
import 'mascot_pose.dart';
import 'mascot_motion.dart';

/// Reusable empty state component featuring the ShipdeHop squirrel mascot.
class MascotEmptyState extends StatelessWidget {
  final MascotPose pose;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double mascotSize;

  const MascotEmptyState({
    super.key,
    this.pose = MascotPose.searching,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.mascotSize = 130.0,
  });

  factory MascotEmptyState.noRides({VoidCallback? onAction}) {
    return MascotEmptyState(
      pose: MascotPose.searching,
      title: 'No rides found on this route',
      description: 'Check back soon or publish your own ride offer to share costs with others.',
      actionLabel: 'Offer a Ride',
      onAction: onAction,
    );
  }

  factory MascotEmptyState.noParcels({VoidCallback? onAction}) {
    return MascotEmptyState(
      pose: MascotPose.carryParcel,
      title: 'No parcel opportunities nearby',
      description: 'Travelling soon? Post your journey to earn rewards carrying items for neighbors.',
      actionLabel: 'Add Journey',
      onAction: onAction,
    );
  }

  factory MascotEmptyState.noMarketplace({VoidCallback? onAction}) {
    return MascotEmptyState(
      pose: MascotPose.searching,
      title: 'No items found in Marketplace',
      description: 'Explore other categories or request a Buy-for-Me order.',
      actionLabel: 'Browse All Items',
      onAction: onAction,
    );
  }

  factory MascotEmptyState.noMessages({VoidCallback? onAction}) {
    return MascotEmptyState(
      pose: MascotPose.typing,
      title: 'No messages yet',
      description: 'When you match with a traveller or buyer, your conversations will appear here.',
      actionLabel: 'Explore Services',
      onAction: onAction,
    );
  }

  factory MascotEmptyState.noHistory({VoidCallback? onAction}) {
    return MascotEmptyState(
      pose: MascotPose.idle,
      title: 'No active orders or history',
      description: 'Your completed deliveries, rides, and marketplace purchases will show here.',
      actionLabel: 'Start Hopping',
      onAction: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShipdeHopMascot(
              pose: pose,
              motion: MascotMotion.idleFloat,
              size: mascotSize,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B), // ShipdeHop indigo
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF312E81), // ShipdeHop indigo primary
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
