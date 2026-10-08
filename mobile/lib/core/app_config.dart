class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const _backendBaseUrlEnv = String.fromEnvironment('BACKEND_BASE_URL');
  static const _apiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8080');

  static String get apiBaseUrl {
    final raw = _backendBaseUrlEnv.isNotEmpty ? _backendBaseUrlEnv : _apiBaseUrlEnv;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String get backendBaseUrl => apiBaseUrl;

  static const stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static const razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
  static const paymentProvider = String.fromEnvironment('PAYMENT_PROVIDER', defaultValue: 'DISABLED');
  static const _envEnableDevTestAuth = bool.fromEnvironment('ENABLE_DEV_TEST_AUTH', defaultValue: false);

  static bool devTestAuthOverride = false;
  static bool get enableDevTestAuth => _envEnableDevTestAuth || devTestAuthOverride;

  static bool showQaFixtures = false;

  static bool isQaFixtureText(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final lower = text.toLowerCase();
    return lower.contains('concurrent test') ||
        lower.contains('e2e') ||
        lower.contains('traceability proof') ||
        lower.contains('live e2e test') ||
        lower.contains('qa fixture') ||
        lower.contains('qa record') ||
        lower.contains('hopster carrier');
  }

  static bool isConfiguredOverride = false;
  static bool get isConfigured => (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) || isConfiguredOverride;

  static void validate() {
    if (!isConfigured) {
      throw StateError('Pass SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY using --dart-define.');
    }
  }
}
