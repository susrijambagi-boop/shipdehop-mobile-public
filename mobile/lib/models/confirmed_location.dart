class ConfirmedLocation {
  const ConfirmedLocation({
    required this.displayLabel,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.countryCode,
    this.countryName,
    this.administrativeArea,
    this.locality,
    this.postalCode,
    this.provider = 'development',
  });

  final String displayLabel;
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String? countryCode;
  final String? countryName;
  final String? administrativeArea;
  final String? locality;
  final String? postalCode;
  final String provider;

  Map<String, dynamic> toJson() => {
        'displayLabel': displayLabel,
        'formattedAddress': formattedAddress,
        'latitude': latitude,
        'longitude': longitude,
        'countryCode': countryCode,
        'countryName': countryName,
        'administrativeArea': administrativeArea,
        'locality': locality,
        'postalCode': postalCode,
        'provider': provider,
      };

  factory ConfirmedLocation.fromJson(Map<String, dynamic> json) => ConfirmedLocation(
        displayLabel: json['displayLabel']?.toString() ?? json['name']?.toString() ?? 'Location',
        formattedAddress: json['formattedAddress']?.toString() ?? json['address']?.toString() ?? '',
        latitude: ((json['latitude'] ?? json['lat']) as num?)?.toDouble() ?? 0.0,
        longitude: ((json['longitude'] ?? json['lon']) as num?)?.toDouble() ?? 0.0,
        countryCode: json['countryCode']?.toString(),
        countryName: json['countryName']?.toString(),
        administrativeArea: json['administrativeArea']?.toString(),
        locality: json['locality']?.toString(),
        postalCode: json['postalCode']?.toString(),
        provider: json['provider']?.toString() ?? 'development',
      );

  @override
  String toString() => '$displayLabel ($formattedAddress)';
}
