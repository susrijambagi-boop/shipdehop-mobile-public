import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('10_profile', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const ProfileScreen(),
      filename: '10_profile.png',
    );
  });
}
