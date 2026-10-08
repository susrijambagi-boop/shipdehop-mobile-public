import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('03_parcelpool_bring', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const ParcelPoolScreen(initialModeIndex: 1),
      filename: '03_parcelpool_bring.png',
    );
  });
}
