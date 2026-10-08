import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shipdehop_mobile/models/domain.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';

void main() {
  test('MarketplaceCardModel parses real listing fields', () {
    final item = MarketplaceCardModel.fromJson({
      'id': 'item-1',
      'seller_id': 'seller-1',
      'title': 'Headphones',
      'description': 'Very good condition',
      'price': 250,
      'currency': 'QAR',
      'category': 'Electronics',
      'condition': 'Like new',
      'location_name': 'West Bay, Doha',
      'jurisdiction_code': 'QA',
      'available_quantity': 2,
      'ship_eligible': true,
      'images': ['https://example.com/a.jpg'],
    });

    expect(item.sellerId, 'seller-1');
    expect(item.category, 'Electronics');
    expect(item.locationName, 'West Bay, Doha');
    expect(item.availableQuantity, 2);
    expect(item.shipEligible, isTrue);
  });

  testWidgets('Marketplace browse search filters visible listings', (tester) async {
    final items = [
      MarketplaceCardModel.fromJson({
        'id': '1',
        'seller_id': 'seller-a',
        'title': 'Sony Headphones',
        'description': 'Noise cancelling',
        'price': 250,
        'currency': 'QAR',
        'category': 'Electronics',
        'condition': 'Like new',
        'location_name': 'Doha',
        'jurisdiction_code': 'QA',
        'available_quantity': 1,
        'ship_eligible': true,
        'images': <String>[],
      }),
      MarketplaceCardModel.fromJson({
        'id': '2',
        'seller_id': 'seller-b',
        'title': 'Office Chair',
        'description': 'Ergonomic chair',
        'price': 180,
        'currency': 'QAR',
        'category': 'Home & Garden',
        'condition': 'Good',
        'location_name': 'Lusail',
        'jurisdiction_code': 'QA',
        'available_quantity': 1,
        'ship_eligible': false,
        'images': <String>[],
      }),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketplaceFeedProvider.overrideWith((ref) async => items),
          authUserProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
        child: const MaterialApp(home: MarketplaceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sony Headphones'), findsOneWidget);
    expect(find.text('Office Chair'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'chair');
    await tester.pump();

    expect(find.text('Office Chair'), findsOneWidget);
    expect(find.text('Sony Headphones'), findsNothing);
  });
}
