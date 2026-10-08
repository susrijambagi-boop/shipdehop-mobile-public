import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';

final mockOrderData = {
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
  'title': 'Mumbai → Pune Parcel',
  'createdAt': '2026-08-25T10:00:00Z',
  'roleLabel': 'Shipster',
  'module': 'PARCELPOOL',
};

Future<void> setupFonts() async {
  Animate.defaultDuration = Duration.zero;

  final fontLoaderRoboto = FontLoader('Roboto');
  final robotoFile = File('/usr/local/share/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  if (robotoFile.existsSync()) {
    fontLoaderRoboto.addFont(Future.value(ByteData.sublistView(robotoFile.readAsBytesSync())));
    await fontLoaderRoboto.load();
  }

  final fontLoaderOutfit = FontLoader('Outfit');
  final robotoBoldFile = File('/usr/local/share/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf');
  if (robotoBoldFile.existsSync()) {
    fontLoaderOutfit.addFont(Future.value(ByteData.sublistView(robotoBoldFile.readAsBytesSync())));
    await fontLoaderOutfit.load();
  }

  final fontLoaderIcons = FontLoader('MaterialIcons');
  final iconFile = File('/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    fontLoaderIcons.addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
    await fontLoaderIcons.load();
  }
}

TextTheme applyRoboto(TextTheme base) {
  return base.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Roboto']);
}

Future<void> exportWidget({
  required WidgetTester tester,
  required Widget widget,
  required String filename,
  Size size = const Size(390, 844),
}) async {
  FlutterError.onError = (details) {};

  tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
  tester.view.devicePixelRatio = 2.0;

  final GlobalKey repaintKey = GlobalKey();
  final baseTheme = ThemeData(fontFamily: 'Roboto', useMaterial3: true);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        unifiedHistoryProvider.overrideWith((ref) => [mockOrderData]),
        userOrdersProvider.overrideWith((ref) => [mockOrderData]),
        marketplaceFeedProvider.overrideWith((ref) => []),
        shipmentFeedProvider.overrideWith((ref) => []),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: applyRoboto(baseTheme.textTheme),
          primaryTextTheme: applyRoboto(baseTheme.primaryTextTheme),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF4F2F8),
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

  try {
    final BuildContext context = repaintKey.currentContext!;
    final RenderRepaintBoundary boundary = context.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List pngBytes = byteData!.buffer.asUint8List();

    final dir = Directory('ux_review/final_fidelity');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final file = File('ux_review/final_fidelity/$filename');
    file.writeAsBytesSync(pngBytes);
    debugPrint('EXPORTED: $filename (${pngBytes.length} bytes)');
  } catch (e) {
    debugPrint('ERROR exporting $filename: $e');
  }
  exit(0);
}
