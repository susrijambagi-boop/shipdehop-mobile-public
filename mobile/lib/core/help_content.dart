class HelpTopic {
  final String id;
  final String title;
  final String shortExplanation;
  final String fullExplanation;
  final String category;
  final List<String> keywords;
  final List<String> relatedTopics;

  const HelpTopic({
    required this.id,
    required this.title,
    required this.shortExplanation,
    required this.fullExplanation,
    required this.category,
    required this.keywords,
    this.relatedTopics = const [],
  });
}

class HelpContent {
  static const List<HelpTopic> allTopics = [
    HelpTopic(
      id: 'shipdehop',
      title: 'ShipdeHop',
      shortExplanation: 'The super-app connecting people sharing rides, parcels, and local shopping.',
      fullExplanation:
          'ShipdeHop helps people going the same way share rides, carry parcels, bring shopping requests, and buy or sell items safely.',
      category: 'Getting Started',
      keywords: ['shipdehop', 'app', 'superapp', 'about', 'how it works'],
      relatedTopics: ['explore', 'parcelpool', 'carpool', 'marketplace'],
    ),
    HelpTopic(
      id: 'journey',
      title: 'Unified Journey',
      shortExplanation: 'One travel route that powers passenger rides, parcel crowdshipping, and shopping requests.',
      fullExplanation:
          'One journey can include passengers, parcels, and shopping requests if they fit your route and capacity. You publish one travel route once, and ShipdeHop matches compatible opportunities along your corridor.',
      category: 'Journeys',
      keywords: ['journey', 'route', 'publish', 'traveller', 'carry', 'corridor'],
      relatedTopics: ['journey_opportunities', 'journey_capacity', 'parcelpool', 'carpool'],
    ),
    HelpTopic(
      id: 'journey_opportunities',
      title: 'Journey Opportunities',
      shortExplanation: 'Matching requests found along your travel route.',
      fullExplanation:
          'Opportunities include passengers looking for a ride, senders needing parcel delivery, and shoppers requesting store buy-for-me pickups along your travel route.',
      category: 'Journeys',
      keywords: ['opportunities', 'matches', 'passengers', 'parcels', 'shopping', 'requests'],
      relatedTopics: ['journey', 'journey_capacity'],
    ),
    HelpTopic(
      id: 'journey_capacity',
      title: 'Journey Capacity',
      shortExplanation: 'Managing available seats, parcel sizes, and shopping carry limits.',
      fullExplanation:
          'When publishing a journey, you specify how many seats you offer, your parcel trunk space (envelope, medium, or luggage), and whether you accept shopping requests. ShipdeHop ensures you never get overbooked.',
      category: 'Journeys',
      keywords: ['capacity', 'seats', 'trunk', 'parcel size', 'weight', 'limits'],
      relatedTopics: ['journey', 'journey_opportunities'],
    ),
    HelpTopic(
      id: 'explore',
      title: 'Explore',
      shortExplanation: 'Your main dashboard to discover opportunities, active journeys, and nearby activity.',
      fullExplanation:
          'Explore connects your intentions (sending, travelling, shopping) with live matches along your regular routes.',
      category: 'Getting Started',
      keywords: ['explore', 'home', 'search', 'intent', 'dashboard'],
      relatedTopics: ['journey', 'opportunity'],
    ),
    HelpTopic(
      id: 'parcelpool',
      title: 'ParcelPool',
      shortExplanation: 'Send parcels with verified travellers heading the same direction.',
      fullExplanation:
          'ParcelPool lets you send packages quickly with people already traveling along your corridor, saving cost and time.',
      category: 'ParcelPool',
      keywords: ['parcelpool', 'parcel', 'package', 'shipping', 'shipster', 'hopster'],
      relatedTopics: ['shipster', 'hopster', 'shopster'],
    ),
    HelpTopic(
      id: 'shipster',
      title: 'Shipster',
      shortExplanation: 'A sender using ParcelPool to ship a item or parcel.',
      fullExplanation:
          'As a Shipster, you list parcel details, set flexible pickup/delivery windows, and get matched with verified travellers.',
      category: 'ParcelPool',
      keywords: ['shipster', 'sender', 'ship', 'parcel'],
      relatedTopics: ['parcelpool', 'payment_secured'],
    ),
    HelpTopic(
      id: 'shopster',
      title: 'Shopster',
      shortExplanation: 'A buyer asking a traveller to purchase and bring an item from another location.',
      fullExplanation:
          'Shopsters request items from other cities or countries. Travellers buy or pick up the item and bring it along their journey.',
      category: 'Marketplace',
      keywords: ['shopster', 'buyer', 'buy for me', 'request', 'bring'],
      relatedTopics: ['marketplace', 'cross_border'],
    ),
    HelpTopic(
      id: 'hopster',
      title: 'Hopster',
      shortExplanation: 'A traveller carrying a parcel or item along their journey.',
      fullExplanation:
          'Hopsters earn rewards by utilizing extra space in their bag or vehicle to carry verified items during planned trips.',
      category: 'ParcelPool',
      keywords: ['hopster', 'carrier', 'traveller', 'carry', 'driver'],
      relatedTopics: ['parcelpool', 'journey'],
    ),
    HelpTopic(
      id: 'carpool',
      title: 'CarPool',
      shortExplanation: 'Shared mobility connecting drivers and passengers heading the same way.',
      fullExplanation:
          'CarPool connects commuters and travellers sharing vehicle seats to split travel costs safely.',
      category: 'CarPool',
      keywords: ['carpool', 'ride', 'commute', 'pooler', 'poolice'],
      relatedTopics: ['pooler', 'poolice'],
    ),
    HelpTopic(
      id: 'pooler',
      title: 'Pooler',
      shortExplanation: 'A passenger looking for a shared ride along a corridor.',
      fullExplanation:
          'Poolers book available seats on verified driver routes for convenient, cost-effective travel.',
      category: 'CarPool',
      keywords: ['pooler', 'passenger', 'rider', 'book ride'],
      relatedTopics: ['carpool', 'poolice'],
    ),
    HelpTopic(
      id: 'poolice',
      title: 'Poolice',
      shortExplanation: 'A driver offering spare seat capacity on their journey.',
      fullExplanation:
          'Poolice drivers publish their routes and schedules to share travel costs with verified passengers.',
      category: 'CarPool',
      keywords: ['poolice', 'driver', 'offer ride', 'carpool driver'],
      relatedTopics: ['carpool', 'pooler'],
    ),
    HelpTopic(
      id: 'marketplace',
      title: 'Marketplace',
      shortExplanation: 'Peer-to-peer shopping requests and local listings.',
      fullExplanation:
          'Marketplace connects buyers wanting items from other places with sellers and travellers who can fulfill them.',
      category: 'Marketplace',
      keywords: ['marketplace', 'shop', 'buy', 'sell', 'lister'],
      relatedTopics: ['shopster'],
    ),
    HelpTopic(
      id: 'lister',
      title: 'Lister',
      shortExplanation: 'A seller or traveller offering items in Marketplace.',
      fullExplanation:
          'Listers post available products or offer to bring items for buyers along their route.',
      category: 'Marketplace',
      keywords: ['lister', 'seller', 'list item'],
      relatedTopics: ['marketplace'],
    ),
    HelpTopic(
      id: 'journey',
      title: 'Journey',
      shortExplanation: 'A planned route (origin to destination) that unlocks parcel and ride opportunities.',
      fullExplanation:
          'Publishing a Journey allows ShipdeHop to match you with parcels to carry or passengers to ride along your corridor.',
      category: 'Journeys',
      keywords: ['journey', 'route', 'trip', 'corridor', 'travel'],
      relatedTopics: ['opportunity', 'hopster', 'poolice'],
    ),
    HelpTopic(
      id: 'opportunity',
      title: 'Opportunity',
      shortExplanation: 'A parcel delivery or ride matching your planned journey route.',
      fullExplanation:
          'Opportunities highlight packages or passengers needing travel along your confirmed route so you can earn rewards effortlessly.',
      category: 'Journeys',
      keywords: ['opportunity', 'match', 'reward', 'carry parcel'],
      relatedTopics: ['journey'],
    ),
    HelpTopic(
      id: 'trust_score',
      title: 'Trust Score',
      shortExplanation: 'Your verified trust rating based on identity, reviews, and safe completed handoffs.',
      fullExplanation:
          'Trust Score (out of 100) measures your safety and reliability. It improves as you verify your identity and complete successful transactions.',
      category: 'Safety & Trust',
      keywords: ['trust score', 'trust', 'safety', 'rating', 'verification'],
      relatedTopics: ['identity_verified', 'xp_level'],
    ),
    HelpTopic(
      id: 'identity_verified',
      title: 'ShipdeHop Verified',
      shortExplanation: 'Identity verification ensuring a trusted peer-to-peer community.',
      fullExplanation:
          'Identity verification confirms member phone ownership and trusted profile status to maintain safety across peer handoffs.',
      category: 'Safety & Trust',
      keywords: ['identity', 'verified', 'id', 'verification', 'shipdehop verified'],
      relatedTopics: ['trust_score'],
    ),
    HelpTopic(
      id: 'xp_level',
      title: 'Progress & Levels',
      shortExplanation: 'Your activity level and achievement badges earned through completed transactions.',
      fullExplanation:
          'Progress reflects your real journey activity. Earn Explorer level and badges as you send parcels, share rides, and help others.',
      category: 'Profile & Progress',
      keywords: ['progress', 'xp', 'level', 'badge', 'explorer', 'achievement'],
      relatedTopics: ['trust_score'],
    ),
    HelpTopic(
      id: 'payment_secured',
      title: 'Payment Protection',
      shortExplanation: 'Funds are securely held until delivery or ride completion.',
      fullExplanation:
          'Payments are held safely in protection until both parties confirm a successful handoff, ensuring zero risk for senders or travellers.',
      category: 'Payments',
      keywords: ['payment', 'secured', 'protected', 'escrow', 'money', 'safety'],
      relatedTopics: ['handoff'],
    ),
    HelpTopic(
      id: 'handoff',
      title: 'Handoff Confirmation',
      shortExplanation: 'Verifying delivery completion at pickup and drop-off.',
      fullExplanation:
          'When meeting a traveller or recipient, handoff is confirmed to release payment safely.',
      category: 'Payments',
      keywords: ['handoff', 'confirm', 'pickup', 'delivery', 'release'],
      relatedTopics: ['payment_secured'],
    ),
    HelpTopic(
      id: 'flexible_timing',
      title: 'Flexible Timing',
      shortExplanation: 'Setting date windows to increase match opportunities.',
      fullExplanation:
          'Selecting flexible dates allows ShipdeHop to match you with travellers leaving slightly earlier or later.',
      category: 'Getting Started',
      keywords: ['flexible', 'timing', 'schedule', 'window'],
      relatedTopics: ['journey'],
    ),
    HelpTopic(
      id: 'pickup',
      title: 'Parcel Pickup',
      shortExplanation: 'Meeting the traveller to hand over your package safely.',
      fullExplanation:
          'Once payment is secured, the traveller meets you at the agreed pickup location. Contact details and location maps are provided in delivery details.',
      category: 'Delivery Lifecycle',
      keywords: ['pickup', 'collection', 'meet', 'sender', 'location'],
      relatedTopics: ['in_transit', 'payment_secured'],
    ),
    HelpTopic(
      id: 'in_transit',
      title: 'In Transit',
      shortExplanation: 'The traveller is en route with your parcel or ride.',
      fullExplanation:
          'When the traveller collects the parcel and begins their journey, they mark the status as In Transit. You can monitor route progress and timing in delivery details.',
      category: 'Delivery Lifecycle',
      keywords: ['in transit', 'transit', 'en route', 'traveller', 'journey'],
      relatedTopics: ['pickup', 'handoff_verification'],
    ),
    HelpTopic(
      id: 'handoff_verification',
      title: 'Handoff Verification',
      shortExplanation: 'Security code check ensuring the item reaches the right recipient.',
      fullExplanation:
          'Handoff verification confirms that the parcel reached the authorized recipient. Payment is released to the traveller only after verification.',
      category: 'Delivery Lifecycle',
      keywords: ['handoff', 'verification', 'confirm', 'otp', 'qr', 'release'],
      relatedTopics: ['otp_handoff', 'qr_handoff', 'payment_release'],
    ),
    HelpTopic(
      id: 'otp_handoff',
      title: 'OTP Handoff Code',
      shortExplanation: 'A 6-digit one-time code generated for safe verification.',
      fullExplanation:
          'The sender reveals a secure 6-digit OTP code when the traveller arrives. The traveller enters the code to confirm successful delivery.',
      category: 'Delivery Lifecycle',
      keywords: ['otp', 'code', 'pin', 'handoff', 'six digit'],
      relatedTopics: ['handoff_verification', 'qr_handoff'],
    ),
    HelpTopic(
      id: 'qr_handoff',
      title: 'QR Code Handoff',
      shortExplanation: 'Scan a secure QR code for instant handoff confirmation.',
      fullExplanation:
          'The sender displays a secure ShipdeHop QR code. The traveller scans the code using their camera to confirm delivery without typing.',
      category: 'Delivery Lifecycle',
      keywords: ['qr', 'scan', 'barcode', 'handoff', 'camera'],
      relatedTopics: ['handoff_verification', 'otp_handoff'],
    ),
    HelpTopic(
      id: 'payment_release',
      title: 'Payment Release',
      shortExplanation: 'Escrow release transferring funds to the traveller upon completion.',
      fullExplanation:
          'After handoff verification succeeds, protected funds are automatically released to the traveller’s account balance.',
      category: 'Payments',
      keywords: ['release', 'payout', 'payment', 'transfer', 'funds'],
      relatedTopics: ['payment_secured', 'delivery_completion'],
    ),
    HelpTopic(
      id: 'delivery_completion',
      title: 'Delivery Completion',
      shortExplanation: 'Final state of a verified parcel delivery or carpool ride.',
      fullExplanation:
          'When handoff is verified and funds are released, the transaction marks completed and adds to your trusted user profile history.',
      category: 'Delivery Lifecycle',
      keywords: ['completion', 'completed', 'delivered', 'done', 'history'],
      relatedTopics: ['payment_release', 'trust_score'],
    ),
    HelpTopic(
      id: 'live_location',
      title: 'Live Location Sharing',
      shortExplanation: 'Real-time GPS tracking along driver and traveller corridors.',
      fullExplanation:
          'Active travellers share periodic GPS updates during planned trips. Location sharing turns on only when the traveller active delivery flow begins.',
      category: 'Journeys',
      keywords: ['live', 'location', 'gps', 'tracking', 'map', 'snapshot'],
      relatedTopics: ['in_transit', 'journey'],
    ),
  ];

  static HelpTopic? findById(String id) {
    try {
      return allTopics.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<HelpTopic> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return allTopics;
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    return allTopics.where((t) {
      final titleLower = t.title.toLowerCase();
      final shortLower = t.shortExplanation.toLowerCase();
      final fullLower = t.fullExplanation.toLowerCase();
      if (titleLower.contains(q) || shortLower.contains(q) || fullLower.contains(q)) return true;
      return t.keywords.any((k) {
        final kLower = k.toLowerCase();
        return kLower == q || words.contains(kLower);
      });
    }).toList();
  }
}
