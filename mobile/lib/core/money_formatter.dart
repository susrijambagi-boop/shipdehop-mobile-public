class MoneyFormatter {
  /// Formats an amount with Indian number grouping for INR, or standard grouping for other currencies.
  /// Example: format(150000, 'INR') -> '₹1,50,000'
  /// Example: format(1234.5, 'INR') -> '₹1,234.50'
  static String formatINR(num amount) {
    return format(amount, 'INR');
  }

  @Deprecated('Use formatINR or format(amount, currency)')
  static String formatQAR(num amount) {
    return format(amount, 'QAR');
  }

  static String format(num amount, String currency, {bool showDecimalsIfNeeded = false}) {
    final cleanCurrency = currency.toUpperCase().trim();
    final symbolOrCode = currencySymbolOrCode(cleanCurrency);
    final isInt = amount % 1 == 0;
    final numStr = isInt ? amount.toInt().toString() : amount.toStringAsFixed(2);
    final formattedNum = cleanCurrency == 'INR' ? formatIndianNumber(amount) : numStr;

    if (symbolOrCode == '₹' || symbolOrCode == '\$' || symbolOrCode == '€' || symbolOrCode == '£') {
      return '$symbolOrCode$formattedNum';
    } else {
      return '$symbolOrCode $formattedNum';
    }
  }

  static String formatIndianNumber(num amount) {
    if (!amount.isFinite) throw ArgumentError.value(amount, 'amount');
    final sign = amount < 0 ? '-' : '';
    final absolute = amount.abs();
    final isInt = absolute % 1 == 0;
    final numStr = isInt ? absolute.toInt().toString() : absolute.toStringAsFixed(2);
    final parts = numStr.split('.');
    String integerPart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    if (integerPart.length <= 3) {
      return '$sign$integerPart$decimalPart';
    }

    final lastThree = integerPart.substring(integerPart.length - 3);
    final remaining = integerPart.substring(0, integerPart.length - 3);
    final formattedRemaining = remaining.replaceAllMapped(
      RegExp(r'(\d+?)(?=(\d\d)+$)'),
      (m) => '${m[1]},',
    );

    return '$sign$formattedRemaining,$lastThree$decimalPart';
  }

  static String currencySymbolOrCode(String currency) {
    switch (currency.toUpperCase()) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'QAR':
        return 'QAR';
      case 'AED':
        return 'AED';
      case 'SAR':
        return 'SAR';
      case 'OMR':
        return 'OMR';
      case 'BHD':
        return 'BHD';
      case 'KWD':
        return 'KWD';
      default:
        return currency.toUpperCase();
    }
  }
}

