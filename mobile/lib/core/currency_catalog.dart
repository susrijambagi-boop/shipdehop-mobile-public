class CurrencyCatalog {
  CurrencyCatalog._();

  /// ShipdeHop's first production market is India. Keep selectable commerce
  /// currency aligned with the launch market instead of exposing currencies
  /// for countries where the app is not available yet.
  static const List<String> all = <String>['INR'];

  static String? defaultForCountryCode(String? rawCountryCode) {
    final code = (rawCountryCode ?? '').trim().toUpperCase();
    return switch (code) {
      'IN' || 'IND' || 'INDIA' => 'INR',
      _ => null,
    };
  }
}
