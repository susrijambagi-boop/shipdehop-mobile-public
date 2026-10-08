class DeliveryErrorTranslator {
  static String translate(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('invalid otp')) {
      return "That verification code isn't correct. Please check with the sender.";
    }
    if (msg.contains('otp expired')) {
      return "This code has expired. Ask the sender to refresh their handoff code.";
    }
    if (msg.contains('temporarily locked') || msg.contains('locked')) {
      return "Too many failed attempts. Verification is locked for 15 minutes.";
    }
    if (msg.contains('invalid qr') || msg.contains('qr/order mismatch')) {
      return "This isn't a valid ShipdeHop handoff code for this order.";
    }
    if (msg.contains('not ready') || msg.contains('invalid fulfillment state')) {
      return "This delivery isn't ready for handoff yet.";
    }
    if (msg.contains('already completed') || msg.contains('order cannot be released')) {
      return "This delivery has already been completed.";
    }
    if (msg.contains('protected test order is read-only')) {
      return "Protected test order is read-only in development mode.";
    }
    if (msg.contains('provider only') || msg.contains('buyer confirmation required') || msg.contains('forbidden')) {
      return "You are not authorized to perform this action.";
    }

    return "We couldn't connect or complete the request. Please try again.";
  }
}
