// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'package:shipdehop_mobile/screens/carpool_screen.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';
import 'package:shipdehop_mobile/screens/create_journey_screen.dart';
import 'package:shipdehop_mobile/screens/hopship_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';

class MockUrlLauncherPlatform extends Fake with MockPlatformInterfaceMixin implements UrlLauncherPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(true);
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  void close({bool force = false}) {}
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => kTransparentPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.fromIterable([kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final Uint8List kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
]);

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = TestHttpOverrides();
    UrlLauncherPlatform.instance = MockUrlLauncherPlatform();
    Animate.defaultDuration = Duration.zero;
    FlutterError.onError = (details) {};

    final fontLoaderRoboto = FontLoader('Roboto');
    final robotoFile = File('/usr/local/share/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (robotoFile.existsSync()) {
      fontLoaderRoboto.addFont(Future.value(ByteData.sublistView(robotoFile.readAsBytesSync())));
      await fontLoaderRoboto.load();
    }

    final fontLoaderIcons = FontLoader('MaterialIcons');
    final iconFile = File('/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconFile.existsSync()) {
      fontLoaderIcons.addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
      await fontLoaderIcons.load();
    }
  });

  final mockOrder = {
    'id': '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
    'order_type': 'SHIPMENT',
    'buyer_id': 'sender-1',
    'provider_id': 'carrier-1',
    'total_amount': 275.0,
    'base_price': 0.0,
    'reward_fee': 250.0,
    'platform_fee': 25.0,
    'currency': 'QAR',
    'escrow_status': 'LOCKED',
    'status': 'LOCKED',
    'fulfillment_status': 'CREATED',
    'payment_provider': 'MOCK',
    'title': 'Doha → Al Wakrah Parcel Delivery',
    'createdAt': '2026-09-13T10:00:00Z',
    'roleLabel': 'Shipster',
    'module': 'PARCELPOOL',
  };

  TextTheme applyRobotoFallback(TextTheme base) {
    return base.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Roboto']);
  }

  Future<void> captureStoreScreenshot({
    required WidgetTester tester,
    required Widget widget,
    required String filename,
    Size size = const Size(412, 915),
  }) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Suppress minor rendering/overflow errors in screenshot snapshot test
    };
    try {
      tester.view.physicalSize = Size(size.width * 2.625, size.height * 2.625);
      tester.view.devicePixelRatio = 2.625;

    final GlobalKey repaintKey = GlobalKey();
    final baseTheme = ThemeData(fontFamily: 'Roboto', useMaterial3: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          unifiedHistoryProvider.overrideWith((ref) => [mockOrder]),
          userOrdersProvider.overrideWith((ref) => [mockOrder]),
          marketplaceFeedProvider.overrideWith((ref) => []),
          shipmentFeedProvider.overrideWith((ref) => []),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            textTheme: applyRobotoFallback(baseTheme.textTheme),
            primaryTextTheme: applyRobotoFallback(baseTheme.primaryTextTheme),
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFF0B0F19),
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: TickerMode(
                  enabled: false,
                  child: widget,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();

    await tester.runAsync(() async {
      try {
        final BuildContext context = repaintKey.currentContext!;
        final RenderRepaintBoundary boundary = context.findRenderObject()! as RenderRepaintBoundary;
        final ui.Image image = await boundary.toImage(pixelRatio: 2.625);
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final Uint8List pngBytes = byteData!.buffer.asUint8List();

        final outDir = Directory('../store/screenshots/android');
        if (!outDir.existsSync()) {
          outDir.createSync(recursive: true);
        }

        final file = File('../store/screenshots/android/$filename');
        file.writeAsBytesSync(pngBytes);
        debugPrint('STORE SCREENSHOT EXPORTED: $filename (${pngBytes.length} bytes)');
      } catch (e) {
        debugPrint('ERROR exporting $filename: $e');
      }
    });
    tester.takeException();
    } finally {
      FlutterError.onError = originalOnError;
    }
  }

  testWidgets('Export 01-home.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: ExploreScreen(onSelectTab: (_, {destination, modeIndex, origin}) {}),
      filename: '01-home.png',
    );
  });

  testWidgets('Export 02-hopship.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const ParcelPoolScreen(initialModeIndex: 0),
      filename: '02-hopship.png',
    );
  });

  testWidgets('Export 03-hopride.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const CarPoolScreen(initialModeIndex: 0),
      filename: '03-hopride.png',
    );
  });

  testWidgets('Export 04-hopshop.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const MarketplaceScreen(initialModeIndex: 0),
      filename: '04-hopshop.png',
    );
  });

  testWidgets('Export 05-carry.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const CreateJourneyScreen(),
      filename: '05-carry.png',
    );
  });

  testWidgets('Export 06-buy-for-me.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const HopShipScreen(prefilledPickup: 'Doha City Centre', prefilledDropoff: 'Pearl Qatar'),
      filename: '06-buy-for-me.png',
    );
  });

  testWidgets('Export 07-hoptrack.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: DeliveryDetailsScreen(
        orderId: '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        repository: SimulatedDeliveryRepository(),
      ),
      filename: '07-hoptrack.png',
    );
  });

  testWidgets('Export 08-hopshield.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const HopShipScreen(),
      filename: '08-hopshield.png',
    );
  });

  testWidgets('Export 09-profile.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: const ProfileScreen(),
      filename: '09-profile.png',
    );
  });

  testWidgets('Export 10-closing.png', (tester) async {
    await captureStoreScreenshot(
      tester: tester,
      widget: DeliveryDetailsScreen(
        orderId: '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        repository: SimulatedDeliveryRepository(),
      ),
      filename: '10-closing.png',
    );
  });
}
