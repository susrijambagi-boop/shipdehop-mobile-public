import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('07_marketplace_sell', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const MarketplaceScreen(initialModeIndex: 1),
      filename: '07_marketplace_sell.png',
    );
  });
}
