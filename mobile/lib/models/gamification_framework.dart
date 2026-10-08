import 'package:flutter/foundation.dart';

enum UserLevel {
  newcomer,
  explorer,
  hopper,
  pathfinder,
  navigator,
  legend,
}

extension UserLevelExtension on UserLevel {
  String get title {
    switch (this) {
      case UserLevel.newcomer:
        return 'Newcomer';
      case UserLevel.explorer:
        return 'Explorer';
      case UserLevel.hopper:
        return 'Hopper';
      case UserLevel.pathfinder:
        return 'Pathfinder';
      case UserLevel.navigator:
        return 'Navigator';
      case UserLevel.legend:
        return 'Legend';
    }
  }

  int get minXp {
    switch (this) {
      case UserLevel.newcomer:
        return 0;
      case UserLevel.explorer:
        return 100;
      case UserLevel.hopper:
        return 500;
      case UserLevel.pathfinder:
        return 1500;
      case UserLevel.navigator:
        return 4000;
      case UserLevel.legend:
        return 10000;
    }
  }
}

class BadgeItem {
  const BadgeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.criteria,
    required this.isUnlocked,
    required this.iconName,
  });

  final String id;
  final String title;
  final String description;
  final String criteria;
  final bool isUnlocked;
  final String iconName;
}

class ChallengeItem {
  const ChallengeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.progressCurrent,
    required this.progressTarget,
    required this.xpReward,
  });

  final String id;
  final String title;
  final String description;
  final int progressCurrent;
  final int progressTarget;
  final int xpReward;

  bool get isCompleted => progressCurrent >= progressTarget;
}

@immutable
class GamificationFramework {
  const GamificationFramework({
    required this.xp,
    required this.badges,
    required this.challenges,
    this.isProvisional = true,
  });

  final int xp;
  final List<BadgeItem> badges;
  final List<ChallengeItem> challenges;
  final bool isProvisional;

  UserLevel get currentLevel {
    if (xp >= 10000) return UserLevel.legend;
    if (xp >= 4000) return UserLevel.navigator;
    if (xp >= 1500) return UserLevel.pathfinder;
    if (xp >= 500) return UserLevel.hopper;
    if (xp >= 100) return UserLevel.explorer;
    return UserLevel.newcomer;
  }

  String get levelTitle => currentLevel.title;

  static GamificationFramework deriveFromRealData({
    required bool isEkycVerified,
    required int completedJourneysCount,
    required int completedParcelsCount,
    required int completedHandoffsCount,
    int? explicitXp,
  }) {
    int totalXp = explicitXp ?? 0;
    if (explicitXp == null) {
      if (isEkycVerified) totalXp += 50;
      totalXp += (completedJourneysCount * 100);
      totalXp += (completedParcelsCount * 100);
      totalXp += (completedHandoffsCount * 150);
    }

    final badges = [
      BadgeItem(
        id: 'trusted_traveller',
        title: 'Trusted Traveller',
        description: 'Verified traveller with proven journey history',
        criteria: 'Verify identity & complete 5 journeys',
        isUnlocked: isEkycVerified && completedJourneysCount >= 5,
        iconName: 'verified_user',
      ),
      BadgeItem(
        id: 'road_regular',
        title: 'Road Regular',
        description: 'Frequent corridor traveller',
        criteria: 'Complete 10 journeys',
        isUnlocked: completedJourneysCount >= 10,
        iconName: 'commute',
      ),
      BadgeItem(
        id: 'super_shipster',
        title: 'Super Shipster',
        description: 'Active parcel sender',
        criteria: 'Send 25 parcel shipments',
        isUnlocked: completedParcelsCount >= 25,
        iconName: 'local_shipping',
      ),
      BadgeItem(
        id: 'perfect_handoff',
        title: 'Perfect Handoff',
        description: 'Flawless OTP/QR handoff record',
        criteria: 'Complete 10 verified handoffs',
        isUnlocked: completedHandoffsCount >= 10,
        iconName: 'qr_code_2',
      ),
      BadgeItem(
        id: 'early_hopper',
        title: 'Early Hopper',
        description: 'Joined ShipdeHop beta network',
        criteria: 'Participate in initial release',
        isUnlocked: true,
        iconName: 'star',
      ),
    ];

    final challenges = [
      ChallengeItem(
        id: 'c_ekyc',
        title: 'Verify Your Profile',
        description: 'Complete eKYC identity verification',
        progressCurrent: isEkycVerified ? 1 : 0,
        progressTarget: 1,
        xpReward: 50,
      ),
      ChallengeItem(
        id: 'c_first_journey',
        title: 'First Journey',
        description: 'Publish and complete your first carrier journey',
        progressCurrent: completedJourneysCount > 0 ? 1 : 0,
        progressTarget: 1,
        xpReward: 100,
      ),
      ChallengeItem(
        id: 'c_first_parcel',
        title: 'First Parcel Send',
        description: 'Send a parcel via ParcelPool',
        progressCurrent: completedParcelsCount > 0 ? 1 : 0,
        progressTarget: 1,
        xpReward: 100,
      ),
    ];

    return GamificationFramework(
      xp: totalXp,
      badges: badges,
      challenges: challenges,
      isProvisional: totalXp == 0,
    );
  }
}
