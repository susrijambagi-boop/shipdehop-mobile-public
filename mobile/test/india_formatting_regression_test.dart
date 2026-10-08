import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/money_formatter.dart';
import 'package:shipdehop_mobile/core/india_time.dart';

void main() {
  test('Indian grouping keeps the sign and historical currency', () {
    expect(MoneyFormatter.format(-100, 'INR'), '₹-100');
    expect(MoneyFormatter.format(-150000.5, 'INR'), '₹-1,50,000.50');
    expect(MoneyFormatter.format(150000, 'INR'), '₹1,50,000');
    expect(MoneyFormatter.format(100, 'QAR'), 'QAR 100');
  });
  test('IST picker input and display are independent of device timezone', () {
    final instant = IndiaTime.fromWallClock(2026, 10, 1, 9);
    expect(instant, DateTime.utc(2026, 10, 1, 3, 30));
    expect(IndiaTime.format(instant), '1 Oct 2026, 09:00 IST');
    expect(IndiaTime.format(DateTime.utc(2026, 9, 30, 20)), '1 Oct 2026, 01:30 IST');
  });
}
