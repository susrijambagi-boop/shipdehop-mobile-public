import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/main.dart';

void main() {
  testWidgets('ShipdeHop App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ShipdeHopApp(),
      ),
    );

    expect(find.text('ShipdeHop Environment Setup Required'), findsOneWidget);
  });
}
