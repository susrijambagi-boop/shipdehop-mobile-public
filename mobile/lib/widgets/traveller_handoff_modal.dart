import 'package:flutter/material.dart';
import '../repositories/delivery_repository.dart';
import 'contextual_help_button.dart';

class TravellerHandoffModal extends StatefulWidget {
  const TravellerHandoffModal({
    super.key,
    required this.orderId,
    required this.repository,
    required this.onVerifiedSuccess,
  });

  final String orderId;
  final DeliveryRepository repository;
  final VoidCallback onVerifiedSuccess;

  static void show(
    BuildContext context,
    String orderId,
    DeliveryRepository repository,
    VoidCallback onVerifiedSuccess,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TravellerHandoffModal(
        orderId: orderId,
        repository: repository,
        onVerifiedSuccess: onVerifiedSuccess,
      ),
    );
  }

  @override
  State<TravellerHandoffModal> createState() => _TravellerHandoffModalState();
}

class _TravellerHandoffModalState extends State<TravellerHandoffModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _qrInputController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _otpController.dispose();
    _qrInputController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || int.tryParse(otp) == null) {
      setState(() => _errorMessage = 'Please enter a 6-digit verification code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.verifyHandoffOtp(widget.orderId, otp);
      if (mounted) {
        Navigator.pop(context);
        widget.onVerifiedSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _submitQrPayload(String payload) async {
    final qrPayload = payload.trim();
    if (qrPayload.isEmpty) {
      setState(() => _errorMessage = 'Please enter or scan a valid QR code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.repository.verifyHandoffQr(widget.orderId, qrPayload);
      if (mounted) {
        Navigator.pop(context);
        widget.onVerifiedSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      'Verify Delivery Handoff',
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
              'Enter the OTP code or scan the recipient\'s QR code to confirm delivery and release payment.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),

            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Option A: Enter OTP', icon: Icon(Icons.pin, size: 18)),
                Tab(text: 'Option B: Scan / QR', icon: Icon(Icons.qr_code_scanner, size: 18)),
              ],
            ),

            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 13, color: Colors.brown, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              height: 200,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // OPTION A: OTP FORM
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                        decoration: InputDecoration(
                          hintText: '000000',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submitOtp,
                          icon: _isSubmitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_isSubmitting ? 'Verifying...' : 'Verify OTP & Release Payment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // OPTION B: QR MANUAL / SCANNER FORM
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextField(
                        controller: _qrInputController,
                        decoration: InputDecoration(
                          hintText: 'shipdehop://handoff/...',
                          prefixIcon: const Icon(Icons.qr_code),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : () => _submitQrPayload(_qrInputController.text),
                          icon: _isSubmitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.qr_code_scanner),
                          label: Text(_isSubmitting ? 'Verifying QR...' : 'Verify QR & Release Payment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('What is handoff verification?', style: TextStyle(fontSize: 11, color: Colors.black54)),
                const SizedBox(width: 4),
                ContextualHelpButton.showHelpModalIcon(context, 'handoff_verification'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
