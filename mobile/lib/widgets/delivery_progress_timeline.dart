import 'package:flutter/material.dart';
import '../core/delivery_lifecycle.dart';

class MilestoneStep {
  final String title;
  final String description;
  final bool isCompleted;
  final bool isCurrent;

  const MilestoneStep({
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.isCurrent,
  });
}

class DeliveryProgressTimeline extends StatelessWidget {
  const DeliveryProgressTimeline({
    super.key,
    required this.contextModel,
  });

  final DeliveryLifecycleContext contextModel;

  @override
  Widget build(BuildContext context) {
    final state = DeliveryLifecycleMapper.resolveState(contextModel);
    final events = contextModel.eventTypes;

    final isMatchedDone = state != DeliveryLifecycleState.cancelled;
    final isPaymentDone = state == DeliveryLifecycleState.paymentSecured ||
        state == DeliveryLifecycleState.inTransit ||
        state == DeliveryLifecycleState.readyForHandoff ||
        state == DeliveryLifecycleState.completed ||
        events.contains('PAYMENT_LOCKED');

    final isPickupDone = state == DeliveryLifecycleState.inTransit ||
        state == DeliveryLifecycleState.readyForHandoff ||
        state == DeliveryLifecycleState.completed ||
        events.contains('IN_TRANSIT');

    final isInTransitDone = state == DeliveryLifecycleState.readyForHandoff ||
        state == DeliveryLifecycleState.completed ||
        events.contains('IN_TRANSIT');

    final isHandoffDone = state == DeliveryLifecycleState.completed ||
        events.contains('HANDOFF_VERIFIED') ||
        events.contains('HANDOFF_QR_VERIFIED');

    final isCompletedDone = state == DeliveryLifecycleState.completed;

    final steps = [
      MilestoneStep(
        title: 'Request matched',
        description: 'Matched with verified traveller',
        isCompleted: isMatchedDone,
        isCurrent: state == DeliveryLifecycleState.matched,
      ),
      MilestoneStep(
        title: 'Payment secured',
        description: 'Payment is protected until handoff',
        isCompleted: isPaymentDone,
        isCurrent: state == DeliveryLifecycleState.paymentSecured && !isPickupDone,
      ),
      MilestoneStep(
        title: isPickupDone ? 'Pickup completed' : 'Awaiting pickup',
        description: isPickupDone ? 'Package collected by traveller' : 'Waiting for traveller to collect package',
        isCompleted: isPickupDone,
        isCurrent: state == DeliveryLifecycleState.paymentSecured && !isPickupDone,
      ),
      MilestoneStep(
        title: 'In transit',
        description: 'Traveller is en route along journey route',
        isCompleted: isInTransitDone,
        isCurrent: state == DeliveryLifecycleState.inTransit,
      ),
      MilestoneStep(
        title: 'Handoff',
        description: 'OTP or QR code verified at drop-off',
        isCompleted: isHandoffDone,
        isCurrent: state == DeliveryLifecycleState.readyForHandoff,
      ),
      MilestoneStep(
        title: 'Completed',
        description: 'Payment released to traveller',
        isCompleted: isCompletedDone,
        isCurrent: state == DeliveryLifecycleState.completed,
      ),
    ];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Progress',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: steps.length,
              separatorBuilder: (context, index) => Container(
                margin: const EdgeInsets.only(left: 15),
                height: 16,
                width: 2,
                color: steps[index].isCompleted ? Colors.green : Colors.grey.shade300,
              ),
              itemBuilder: (context, index) {
                final step = steps[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: step.isCompleted
                          ? Colors.green
                          : step.isCurrent
                              ? Colors.indigo
                              : Colors.grey.shade200,
                      child: Icon(
                        step.isCompleted
                            ? Icons.check
                            : step.isCurrent
                                ? Icons.navigation
                                : Icons.circle_outlined,
                        size: 16,
                        color: (step.isCompleted || step.isCurrent) ? Colors.white : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: TextStyle(
                              fontWeight: (step.isCompleted || step.isCurrent) ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                              color: step.isCompleted
                                  ? Colors.black87
                                  : step.isCurrent
                                      ? Colors.indigo.shade900
                                      : Colors.grey,
                            ),
                          ),
                          Text(
                            step.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: (step.isCompleted || step.isCurrent) ? Colors.black54 : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
