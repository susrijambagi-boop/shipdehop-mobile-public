import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/chat_inbox_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('09_messages', (tester) async {
    await exportWidget(
      tester: tester,
      widget: const ChatInboxScreen(),
      filename: '09_messages.png',
    );
  });
}
