import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'export_helper.dart';

void main() {
  setUpAll(setupFonts);

  testWidgets('11_delivery_tracking', (tester) async {
    await exportWidget(
      tester: tester,
      widget: DeliveryDetailsScreen(
        orderId: '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        repository: SimulatedDeliveryRepository(),
      ),
      filename: '11_delivery_tracking.png',
    );
  });
}
