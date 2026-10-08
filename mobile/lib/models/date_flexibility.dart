import '../core/india_time.dart';
import 'package:flutter/foundation.dart';

@immutable
class DateFlexibility {
  const DateFlexibility({
    required this.earliestDateTime,
    required this.latestDateTime,
    this.isFlexible = false,
    this.flexibilityWindowHours = 0,
    this.labelContext,
  });

  final DateTime earliestDateTime;
  final DateTime latestDateTime;
  final bool isFlexible;
  final int flexibilityWindowHours;
  final String? labelContext;

  String? get validationError {
    final now = DateTime.now().subtract(const Duration(minutes: 10));
    if (earliestDateTime.isBefore(now)) {
      return 'Earliest departure/pickup date cannot be in the past';
    }
    if (latestDateTime.isBefore(earliestDateTime)) {
      return 'Latest delivery/arrival date cannot precede earliest pickup/departure';
    }
    return null;
  }

  bool get isValid => validationError == null;

  String get formattedFlexibility {
    if (!isFlexible || flexibilityWindowHours == 0) {
      return _formatSingleDateTime(earliestDateTime);
    }
    if (flexibilityWindowHours > 0 && flexibilityWindowHours < 24) {
      return '${_formatSingleDateTime(earliestDateTime)} (±$flexibilityWindowHours hr${flexibilityWindowHours > 1 ? 's' : ''})';
    }
    return 'Flexible: Any time between ${_formatShortDate(earliestDateTime)} and ${_formatShortDate(latestDateTime)}';
  }

  String _formatSingleDateTime(DateTime dt) => IndiaTime.format(dt);
  String _formatShortDate(DateTime dt) => IndiaTime.format(dt);

  Map<String, dynamic> toJson() => {
        'earliestDateTime': earliestDateTime.toUtc().toIso8601String(),
        'latestDateTime': latestDateTime.toUtc().toIso8601String(),
        'isFlexible': isFlexible,
        'flexibilityWindowHours': flexibilityWindowHours,
        'labelContext': labelContext,
      };

  factory DateFlexibility.fromJson(Map<String, dynamic> json) {
    final earliestStr = json['earliestDateTime']?.toString() ?? json['departureTime']?.toString() ?? json['departure_time']?.toString();
    final latestStr = json['latestDateTime']?.toString() ?? earliestStr;
    final earliest = earliestStr != null ? DateTime.parse(earliestStr) : DateTime.now();
    final latest = latestStr != null ? DateTime.parse(latestStr) : earliest;
    return DateFlexibility(
      earliestDateTime: earliest,
      latestDateTime: latest,
      isFlexible: json['isFlexible'] as bool? ?? false,
      flexibilityWindowHours: json['flexibilityWindowHours'] as int? ?? 0,
      labelContext: json['labelContext'] as String?,
    );
  }
}

