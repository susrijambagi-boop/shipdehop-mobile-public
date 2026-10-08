import 'package:flutter/material.dart';

/// Available poses for the ShipdeHop squirrel mascot.
enum MascotPose {
  idle,
  wave,
  hop,
  run,
  carryParcel,
  ride,
  point,
  celebrate,
  ringBell,
  typing,
  sleepWait,
  success,
  searching,
  confused,
  warning,
}

extension MascotPoseX on MascotPose {
  String get assetPath {
    return 'assets/mascot/shipdehop_squirrel_canonical.png';
  }

  String get semanticLabel {
    switch (this) {
      case MascotPose.idle:
        return 'ShipdeHop Mascot';
      case MascotPose.wave:
        return 'Waving ShipdeHop Mascot';
      case MascotPose.hop:
      case MascotPose.run:
      case MascotPose.carryParcel:
        return 'ShipdeHop Mascot carrying a parcel';
      case MascotPose.ride:
      case MascotPose.point:
        return 'ShipdeHop Mascot on a journey';
      case MascotPose.celebrate:
      case MascotPose.success:
        return 'Celebrating ShipdeHop Mascot';
      case MascotPose.ringBell:
        return 'ShipdeHop Mascot with notification bell';
      case MascotPose.typing:
        return 'ShipdeHop Mascot typing';
      case MascotPose.sleepWait:
      case MascotPose.searching:
        return 'Searching ShipdeHop Mascot';
      case MascotPose.confused:
      case MascotPose.warning:
        return 'ShipdeHop Mascot helper';
    }
  }

  /// Optional contextual badge overlay icon when layered body assets are unavailable.
  IconData? get badgeIcon {
    switch (this) {
      case MascotPose.wave:
        return Icons.mark_email_read_rounded;
      case MascotPose.warning:
      case MascotPose.sleepWait:
        return Icons.shield_rounded;
      case MascotPose.ringBell:
        return Icons.notifications_active_rounded;
      case MascotPose.carryParcel:
        return Icons.inventory_2_rounded;
      case MascotPose.ride:
        return Icons.directions_car_rounded;
      case MascotPose.success:
      case MascotPose.celebrate:
        return Icons.verified_rounded;
      case MascotPose.typing:
        return Icons.mark_unread_chat_alt_rounded;
      case MascotPose.searching:
        return Icons.search_rounded;
      default:
        return null;
    }
  }
}
