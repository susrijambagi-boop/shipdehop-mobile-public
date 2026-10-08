import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ShdLocationHeader extends StatelessWidget {
  final String locationName;
  final VoidCallback onTapLocation;
  final VoidCallback? onTapNotification;
  final int unreadNotificationsCount;

  const ShdLocationHeader({
    super.key,
    this.locationName = 'Choose your city',
    required this.onTapLocation,
    this.onTapNotification,
    this.unreadNotificationsCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('home_location_header'),
        onTap: onTapLocation,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ShipdeHopColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ShipdeHopColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ShipdeHopColors.brandPrimaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: ShipdeHopColors.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXPLORE FROM',
                      style: ShipdeHopTypography.labelSmall.copyWith(
                        color: ShipdeHopColors.brandPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationName,
                      style: ShipdeHopTypography.titleMedium.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Tap to change city, area or current location',
                      style: ShipdeHopTypography.bodySmall.copyWith(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: ShipdeHopColors.textSecondary),
              if (onTapNotification != null) ...[
                const SizedBox(width: 6),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: onTapNotification,
                      icon: const Icon(Icons.notifications_none_rounded, color: ShipdeHopColors.textPrimary),
                      tooltip: 'Notifications',
                    ),
                    if (unreadNotificationsCount > 0)
                      Positioned(
                        right: 6,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: ShipdeHopColors.error, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            unreadNotificationsCount > 9 ? '9+' : '$unreadNotificationsCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
