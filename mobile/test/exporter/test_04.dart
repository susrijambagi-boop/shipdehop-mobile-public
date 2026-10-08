import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('04_parcelpool_travel', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const ParcelPoolScreen(initialModeIndex: 2),
      filename: '04_parcelpool_travel.png',
    );
  });
}
