import 'package:flutter/material.dart';
import 'app_config.dart';

enum DeliveryLifecycleState {
  matched,
  reserved,
  paymentSecured,
  inTransit,
  readyForHandoff,
  completed,
  cancelled,
}

enum ConsumerUserRole {
  sender,
  carrier,
  participant,
}

class DeliveryLifecycleContext {
  final String? orderId;
  final String? shipmentStatus;
  final String? escrowStatus;
  final String? fulfillmentStatus;
  final String? reservationExpiresAt;
  final List<String> eventTypes;
  final ConsumerUserRole role;

  const DeliveryLifecycleContext({
    this.orderId,
    this.shipmentStatus,
    this.escrowStatus,
    this.fulfillmentStatus,
    this.reservationExpiresAt,
    this.eventTypes = const [],
    this.role = ConsumerUserRole.participant,
  });

  bool get isExpired {
    if (reservationExpiresAt == null) return false;
    final expiry = DateTime.tryParse(reservationExpiresAt!);
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now());
  }

  bool get hasEventInTransit => eventTypes.contains('IN_TRANSIT');
  bool get hasEventHandoffVerified => eventTypes.contains('HANDOFF_VERIFIED') || eventTypes.contains('HANDOFF_QR_VERIFIED');
}

class DeliveryLifecycleActionHelper {
  static bool canPayEscrow(DeliveryLifecycleContext context) {
    final state = DeliveryLifecycleMapper.resolveState(context);
    final isSender = context.role == ConsumerUserRole.sender || context.role == ConsumerUserRole.participant;
    return isSender && (state == DeliveryLifecycleState.reserved || state == DeliveryLifecycleState.matched);
  }

  static bool canViewPickupCode(DeliveryLifecycleContext context) {
    final state = DeliveryLifecycleMapper.resolveState(context);
    final isSender = context.role == ConsumerUserRole.sender || context.role == ConsumerUserRole.participant;
    return isSender && (state == DeliveryLifecycleState.paymentSecured);
  }

  static bool canConfirmPickup(DeliveryLifecycleContext context) {
    final state = DeliveryLifecycleMapper.resolveState(context);
    final isCarrier = context.role == ConsumerUserRole.carrier;
    return isCarrier && (state == DeliveryLifecycleState.paymentSecured);
  }

  static bool canStartDelivery(DeliveryLifecycleContext context) {
    return canConfirmPickup(context);
  }

  static bool canViewHandoffCode(DeliveryLifecycleContext context) {
    final state = DeliveryLifecycleMapper.resolveState(context);
    final isSender = context.role == ConsumerUserRole.sender || context.role == ConsumerUserRole.participant;
    return isSender && (state == DeliveryLifecycleState.inTransit || state == DeliveryLifecycleState.readyForHandoff);
  }

  static bool canVerifyHandoff(DeliveryLifecycleContext context) {
    final state = DeliveryLifecycleMapper.resolveState(context);
    final isCarrier = context.role == ConsumerUserRole.carrier;
    return isCarrier && (state == DeliveryLifecycleState.inTransit || state == DeliveryLifecycleState.readyForHandoff);
  }
}

class DeliveryLifecycleMapper {
  static DeliveryLifecycleState resolveState(DeliveryLifecycleContext context) {
    final fulfillment = (context.fulfillmentStatus ?? 'CREATED').toUpperCase();
    final escrow = (context.escrowStatus ?? 'PENDING').toUpperCase();

    if (fulfillment == 'CANCELLED' || escrow == 'REFUNDED' || escrow == 'DISPUTED' || escrow == 'CANCELLED') {
      return DeliveryLifecycleState.cancelled;
    }

    if (fulfillment == 'COMPLETED' || fulfillment == 'VERIFIED' || escrow == 'RELEASED') {
      return DeliveryLifecycleState.completed;
    }

    if (fulfillment == 'AWAITING_HANDOFF') {
      return DeliveryLifecycleState.readyForHandoff;
    }

    if (fulfillment == 'IN_TRANSIT') {
      return DeliveryLifecycleState.inTransit;
    }

    if (fulfillment == 'READY') {
      return DeliveryLifecycleState.paymentSecured; // i.e. Match Confirmed · Ready for Pickup
    }

    if (escrow == 'LOCKED') {
      return DeliveryLifecycleState.paymentSecured;
    }

    if (context.isExpired) {
      return DeliveryLifecycleState.cancelled;
    }

    final shipment = (context.shipmentStatus ?? '').toUpperCase();
    if (shipment == 'MATCHED' || shipment == 'APPROVED') {
      return DeliveryLifecycleState.matched;
    }

    return DeliveryLifecycleState.reserved;
  }

  static String getTitle(DeliveryLifecycleState state) {
    switch (state) {
      case DeliveryLifecycleState.matched:
        return 'Request Matched';
      case DeliveryLifecycleState.reserved:
        return 'Match Awaiting Acceptance';
      case DeliveryLifecycleState.paymentSecured:
        return 'Payment Secured';
      case DeliveryLifecycleState.inTransit:
        return 'In Transit';
      case DeliveryLifecycleState.readyForHandoff:
        return 'Ready for Handoff';
      case DeliveryLifecycleState.completed:
        return 'Completed';
      case DeliveryLifecycleState.cancelled:
        return 'Cancelled';
    }
  }

  static String getSubtitle(DeliveryLifecycleState state) {
    switch (state) {
      case DeliveryLifecycleState.matched:
        return 'Matched with a verified traveller';
      case DeliveryLifecycleState.reserved:
        return '30-minute reservation window active';
      case DeliveryLifecycleState.paymentSecured:
        return 'Awaiting pickup';
      case DeliveryLifecycleState.inTransit:
        return 'Traveller is en route with parcel';
      case DeliveryLifecycleState.readyForHandoff:
        return 'Handoff code ready for recipient';
      case DeliveryLifecycleState.completed:
        return 'Handoff confirmed • Delivery complete';
      case DeliveryLifecycleState.cancelled:
        return 'Reservation expired or transaction cancelled';
    }
  }

  static String getStatusLabel(DeliveryLifecycleContext context) {
    final state = resolveState(context);
    final isBetaNoPayment = AppConfig.paymentProvider == 'DISABLED';
    if (state == DeliveryLifecycleState.paymentSecured && isBetaNoPayment) {
      return 'Match Confirmed • Ready for Pickup';
    }
    final title = getTitle(state);
    final subtitle = getSubtitle(state);
    if (state == DeliveryLifecycleState.paymentSecured) {
      return '$title • $subtitle';
    }
    return title;
  }

  static Color getColor(DeliveryLifecycleState state) {
    switch (state) {
      case DeliveryLifecycleState.matched:
        return Colors.blue.shade700;
      case DeliveryLifecycleState.reserved:
        return Colors.amber.shade800;
      case DeliveryLifecycleState.paymentSecured:
        return Colors.green.shade700;
      case DeliveryLifecycleState.inTransit:
        return Colors.indigo.shade700;
      case DeliveryLifecycleState.readyForHandoff:
        return Colors.purple.shade700;
      case DeliveryLifecycleState.completed:
        return Colors.teal.shade800;
      case DeliveryLifecycleState.cancelled:
        return Colors.red.shade700;
    }
  }
}
