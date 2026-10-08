/// India has a fixed UTC+05:30 offset. Keep stored instants in UTC.
class IndiaTime {
  static const offset = Duration(hours: 5, minutes: 30);
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Wall-clock fields for display/pickers, never a persisted instant.
  static DateTime wallClock(DateTime instant) => instant.toUtc().add(offset);

  static DateTime fromWallClock(int year, int month, int day,
          [int hour = 0, int minute = 0]) =>
      DateTime.utc(year, month, day, hour, minute).subtract(offset);

  static String format(DateTime instant) {
    final dt = wallClock(instant);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} IST';
  }

  /// Converts any UTC or local DateTime instant to IST DateTime representation.
  static DateTime toIst(DateTime dateTime) {
    final utc = dateTime.isUtc ? dateTime : dateTime.toUtc();
    return utc.add(istOffset);
  }

  static DateTime toIST(DateTime dateTime) => toIst(dateTime);

  /// Converts a wall-clock date and time selected in IST into UTC DateTime for storage/API requests.
  static DateTime istPickerToUtc(DateTime date, {int hour = 0, int minute = 0}) {
    final istWallClock = DateTime.utc(date.year, date.month, date.day, hour, minute);
    return istWallClock.subtract(istOffset);
  }

  static DateTime istToUTC(DateTime istWallClock) {
    final utcInstant = DateTime.utc(
      istWallClock.year,
      istWallClock.month,
      istWallClock.day,
      istWallClock.hour,
      istWallClock.minute,
    );
    return utcInstant.subtract(istOffset);
  }

  /// Formats an instant into standardized IST display format (e.g. '09:00 IST' or '21 Sep 2026, 09:00 IST').
  static String formatIst(DateTime dateTime, {bool includeDate = false}) {
    final ist = toIst(dateTime);
    final h = ist.hour.toString().padLeft(2, '0');
    final m = ist.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m IST';
    if (!includeDate) return timeStr;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${ist.day} ${months[ist.month - 1]} ${ist.year}, $timeStr';
  }

  static String formatIST(DateTime dateTime, {bool includeDate = false}) =>
      formatIst(dateTime, includeDate: includeDate);
}
