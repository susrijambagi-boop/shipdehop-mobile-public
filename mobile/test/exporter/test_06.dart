import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('06_marketplace_browse', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const MarketplaceScreen(initialModeIndex: 0),
      filename: '06_marketplace_browse.png',
    );
  });
}
