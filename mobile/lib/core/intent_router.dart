enum IntentType {
  parcelSend,
  parcelShop,
  parcelCarry,
  carpoolRide,
  carpoolOffer,
  marketplaceSell,
  marketplaceBuy,
  unknown,
}

class IntentResult {
  const IntentResult({
    required this.type,
    required this.targetTab,
    this.targetModeIndex = 0,
    this.rawQuery = '',
    this.origin,
    this.destination,
    this.itemDescription,
    this.clarificationPrompt,
  });

  final IntentType type;
  final int targetTab; // 0: Explore, 1: ParcelPool, 2: CarPool, 3: Marketplace, 4: History
  final int targetModeIndex;
  final String rawQuery;
  final String? origin;
  final String? destination;
  final String? itemDescription;
  final String? clarificationPrompt;
}

abstract class IntentRouter {
  IntentResult parseQuery(String query);
}

class DeterministicIntentRouter implements IntentRouter {
  const DeterministicIntentRouter();

  @override
  IntentResult parseQuery(String query) {
    final q = query.trim().toLowerCase();

    // 1. Parcel Send (Shipster)
    if (q.contains('send') || q.contains('ship') || q.contains('parcel') || q.contains('package')) {
      final route = _extractRoute(query);
      return IntentResult(
        type: IntentType.parcelSend,
        targetTab: 1, // ParcelPool
        targetModeIndex: 0, // Shipster
        rawQuery: query,
        origin: route.origin,
        destination: route.destination,
      );
    }

    // 2. Buy for me (Shopster)
    if (q.contains('buy') || q.contains('shop') || q.contains('bring me') || q.contains('perfume')) {
      final item = _extractItem(query);
      return IntentResult(
        type: IntentType.parcelShop,
        targetTab: 1, // ParcelPool
        targetModeIndex: 1, // Shopster
        rawQuery: query,
        itemDescription: item,
      );
    }

    // 3. Drive / Carry (Hopster / Poolice)
    if (q.contains('drive') || q.contains('driving') || q.contains('travel') || q.contains('carry') || q.contains('earn')) {
      final route = _extractRoute(query);
      return IntentResult(
        type: IntentType.carpoolOffer,
        targetTab: 2, // CarPool
        targetModeIndex: 1, // Poolice
        rawQuery: query,
        origin: route.origin,
        destination: route.destination,
      );
    }

    // 4. Carpool Ride (Pooler)
    if (q.contains('ride') || q.contains('seat') || q.contains('passenger') || q.contains('carpool')) {
      final route = _extractRoute(query);
      return IntentResult(
        type: IntentType.carpoolRide,
        targetTab: 2, // CarPool
        targetModeIndex: 0, // Pooler
        rawQuery: query,
        origin: route.origin,
        destination: route.destination,
      );
    }

    // 5. Sell Item (Lister)
    if (q.contains('sell') || q.contains('list') || q.contains('iphone')) {
      final item = _extractItem(query);
      return IntentResult(
        type: IntentType.marketplaceSell,
        targetTab: 3, // Marketplace
        targetModeIndex: 1, // Lister
        rawQuery: query,
        itemDescription: item,
      );
    }

    // Default fallback with helpful clarification choice prompt
    return IntentResult(
      type: IntentType.unknown,
      targetTab: 0,
      rawQuery: query,
      clarificationPrompt: 'Are you looking to send a parcel, travel as a carrier, request a ride, shop globally, or list an item?',
    );
  }

  ({String? origin, String? destination}) _extractRoute(String text) {
    final fromRegex = RegExp(r'from\s+([a-zA-Z]+)', caseSensitive: false);
    final toRegex = RegExp(r'to\s+([a-zA-Z]+)', caseSensitive: false);

    final fromMatch = fromRegex.firstMatch(text);
    final toMatch = toRegex.firstMatch(text);

    return (
      origin: fromMatch?.group(1)?.trim(),
      destination: toMatch?.group(1)?.trim(),
    );
  }

  String? _extractItem(String text) {
    final buyRegex = RegExp(r'(?:buy|sell|bring me)\s+(?:this\s+)?([a-zA-Z0-9\s]+?)(?=\s+for|\s+from|\s+to|\s+$)', caseSensitive: false);
    final match = buyRegex.firstMatch(text);
    return match?.group(1)?.trim();
  }
}
