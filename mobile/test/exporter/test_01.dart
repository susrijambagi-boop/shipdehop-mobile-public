import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('01_explore', (tester) async {
    await exportWidget(
      tester: tester,
      widget: ExploreScreen(onSelectTab: (_, {destination, modeIndex, origin}) {}),
      filename: '01_explore.png',
    );
  });
}
