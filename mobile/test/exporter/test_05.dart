import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/carpool_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('05_carpool_find', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const CarPoolScreen(initialModeIndex: 0),
      filename: '05_carpool_find.png',
    );
  });
}
