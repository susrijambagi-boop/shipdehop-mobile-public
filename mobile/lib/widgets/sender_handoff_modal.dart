import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../repositories/delivery_repository.dart';
import 'contextual_help_button.dart';

class SenderHandoffModal extends StatefulWidget {
  const SenderHandoffModal({
    super.key,
    required this.orderId,
    required this.repository,
  });

  final String orderId;
  final DeliveryRepository repository;

  static void show(BuildContext context, String orderId, DeliveryRepository repository) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SenderHandoffModal(orderId: orderId, repository: repository),
    );
  }

  @override
  State<SenderHandoffModal> createState() => _SenderHandoffModalState();
}

class _SenderHandoffModalState extends State<SenderHandoffModal> {
  late Future<HandoffSecretData> _secretFuture;
  Timer? _countdownTimer;
  int _remainingSeconds = 1800;

  @override
  void initState() {
    super.initState();
    _secretFuture = widget.repository.fetchHandoffSecret(widget.orderId);
    _secretFuture.then((data) {
      if (mounted) {
        setState(() => _remainingSeconds = data.expiresInSeconds);
        _startTimer();
      }
    }).catchError((_) {});
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _remainingSeconds = 0);
      } else {
        if (mounted) setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatTimer(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<HandoffSecretData>(
          future: _secretFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 40),
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating secure handoff codes...'),
                  SizedBox(height: 40),
                ],
              );
            }

            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.brown),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final data = snapshot.data!;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.qr_code_2, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'Handoff Verification',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Show OTP or QR code to the traveller at drop-off to release payment.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 20),

                // OTP DISPLAY CARD
                Card(
                  elevation: 0,
                  color: Colors.indigo.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.indigo.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          '6-Digit OTP Code',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.otp,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer_outlined, size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Text(
                              _remainingSeconds > 0
                                  ? 'Expires in ${_formatTimer(_remainingSeconds)}'
                                  : 'Code expired. Tap refresh to generate new code.',
                              style: TextStyle(
                                fontSize: 11,
                                color: _remainingSeconds > 0 ? Colors.black54 : Colors.red,
                                fontWeight: _remainingSeconds > 0 ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // LOCAL QR CODE CANVAS
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: data.qrPayload,
                      version: QrVersions.auto,
                      size: 180.0,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('How handoff works', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(width: 4),
                    ContextualHelpButton.showHelpModalIcon(context, 'handoff_verification'),
                  ],
                ),

                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}
