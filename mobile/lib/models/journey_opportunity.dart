import 'confirmed_location.dart';
import 'date_flexibility.dart';

enum JourneyOpportunityType {
  passenger,
  parcel,
  shoppingRequest,
}

enum JourneyOpportunitySource {
  liveParcel,
  livePassenger,
  liveShopping,
  simulation,
}

enum CompatibilityMatchScore {
  greatMatch,
  goodMatch,
  possibleMatch,
}

enum ParcelFitStatus {
  fitsEasily,
  fits,
  tooLarge,
}

class JourneyOpportunity {
  final String id;
  final JourneyOpportunityType type;
  final JourneyOpportunitySource source;
  final ConfirmedLocation origin;
  final ConfirmedLocation destination;
  final DateFlexibility timing;
  final double rewardAmount;
  final String currency;
  final double? weightKg;
  final int? seatsNeeded;
  final int requiredParcelUnits;
  final String? productUrl;
  final String requesterName;
  final double pickupDistanceMeters;
  final double dropDistanceMeters;
  final CompatibilityMatchScore matchScore;

  const JourneyOpportunity({
    required this.id,
    required this.type,
    this.source = JourneyOpportunitySource.liveParcel,
    required this.origin,
    required this.destination,
    required this.timing,
    required this.rewardAmount,
    required this.currency,
    this.weightKg,
    this.seatsNeeded,
    int? requiredParcelUnits,
    this.productUrl,
    required this.requesterName,
    this.pickupDistanceMeters = 0,
    this.dropDistanceMeters = 0,
    this.matchScore = CompatibilityMatchScore.greatMatch,
  }) : requiredParcelUnits = requiredParcelUnits ??
            ((type == JourneyOpportunityType.parcel || type == JourneyOpportunityType.shoppingRequest)
                ? ((weightKg ?? 2.0) <= 1.0 ? 1 : (weightKg ?? 2.0) <= 5.0 ? 3 : 6)
                : 0);

  bool get isSimulation => source == JourneyOpportunitySource.simulation;

  String get typeLabel {
    switch (type) {
      case JourneyOpportunityType.passenger:
        return 'Passenger Ride';
      case JourneyOpportunityType.parcel:
        return 'Parcel Delivery';
      case JourneyOpportunityType.shoppingRequest:
        return 'Buy-for-Me Shopping';
    }
  }

  String get scoreLabel {
    switch (matchScore) {
      case CompatibilityMatchScore.greatMatch:
        return 'Great match';
      case CompatibilityMatchScore.goodMatch:
        return 'Good match';
      case CompatibilityMatchScore.possibleMatch:
        return 'Possible match';
    }
  }

  ParcelFitStatus calculateFitStatus(int availableUnits) {
    if (requiredParcelUnits > availableUnits) {
      return ParcelFitStatus.tooLarge;
    }
    if (availableUnits - requiredParcelUnits >= 2 || requiredParcelUnits <= 1) {
      return ParcelFitStatus.fitsEasily;
    }
    return ParcelFitStatus.fits;
  }

  String getFitLabel(int availableUnits) {
    final status = calculateFitStatus(availableUnits);
    switch (status) {
      case ParcelFitStatus.fitsEasily:
        return 'Fits easily';
      case ParcelFitStatus.fits:
        return 'Fits';
      case ParcelFitStatus.tooLarge:
        return 'Too large';
    }
  }

  static CompatibilityMatchScore calculateScore(double pickupM, double dropM) {
    final maxDist = pickupM > dropM ? pickupM : dropM;
    if (maxDist <= 1500) {
      return CompatibilityMatchScore.greatMatch;
    } else if (maxDist <= 5000) {
      return CompatibilityMatchScore.goodMatch;
    } else {
      return CompatibilityMatchScore.possibleMatch;
    }
  }
}
