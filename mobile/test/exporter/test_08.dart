import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/orders_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('08_history', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const OrdersScreen(),
      filename: '08_history.png',
    );
  });
}
