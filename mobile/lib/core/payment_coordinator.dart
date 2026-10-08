import 'dart:async';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'app_config.dart';

class PaymentCoordinator {
  Future<void> completeReservation(Map<String, dynamic> reservation) async {
    final payment = (reservation['payment'] as Map).cast<String, dynamic>();
    final order = (reservation['order'] as Map).cast<String, dynamic>();
    switch (payment['provider']) {
      case 'STRIPE':
        final secret = payment['clientSecret']?.toString();
        if (secret == null || secret.isEmpty) throw StateError('Stripe client secret missing');
        await Stripe.instance.initPaymentSheet(paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secret,
          merchantDisplayName: 'ShipdeHop',
        ));
        await Stripe.instance.presentPaymentSheet();
        break;
      case 'RAZORPAY':
        if (AppConfig.razorpayKeyId.isEmpty) throw StateError('RAZORPAY_KEY_ID --dart-define is required');
        final checkoutOrderId = payment['checkoutOrderId']?.toString();
        if (checkoutOrderId == null) throw StateError('Razorpay order id missing');
        final amountMinor = payment['amountMinor'];
        if (amountMinor is! num) throw StateError('Razorpay minor-unit amount missing');
        await _openRazorpay(checkoutOrderId, amountMinor.toInt(), order);
        break;
      case 'MOCK':
        // Development-only provider. The backend locks escrow immediately.
        return;
      default:
        throw StateError('Unsupported payment provider ${payment['provider']}');
    }
  }

  Future<void> _openRazorpay(String checkoutOrderId, int amountMinor, Map<String, dynamic> order) async {
    final razorpay = Razorpay();
    final completer = Completer<void>();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      if (!completer.isCompleted) completer.complete();
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      if (!completer.isCompleted) completer.completeError(StateError(response.message ?? 'Razorpay payment failed'));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {});
    try {
      razorpay.open({
        'key': AppConfig.razorpayKeyId,
        'order_id': checkoutOrderId,
        'amount': amountMinor,
        'currency': order['currency'].toString().trim(),
        'name': 'ShipdeHop',
        'description': 'HopPay protected order',
      });
      await completer.future.timeout(const Duration(minutes: 10));
    } finally {
      razorpay.clear();
    }
  }
}
