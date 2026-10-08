import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('02_parcelpool_send', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const ParcelPoolScreen(initialModeIndex: 0),
      filename: '02_parcelpool_send.png',
    );
  });
}
