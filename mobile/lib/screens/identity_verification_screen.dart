import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../widgets/identity_badge.dart';

class IdentityVerificationScreen extends ConsumerStatefulWidget {
  final String? phoneE164;

  const IdentityVerificationScreen({super.key, this.phoneE164});

  @override
  ConsumerState<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends ConsumerState<IdentityVerificationScreen> {
  // Step 0: Enter Aadhaar & Consent
  // Step 1: Enter 6-digit Aadhaar OTP
  // Step 2: Verification Progress
  // Step 3: Verification Success
  int currentStep = 0;
  bool isBusy = false;
  bool consentAgreed = false;

  final TextEditingController _aadhaarController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String? verificationSessionId;
  String? maskedAadhaar;
  String? errorMessage;
  int resendCooldown = 60;
  Timer? _cooldownTimer;

  VerificationBadgeStatus finalStatus = VerificationBadgeStatus.notStarted;
  String? verifiedName;
  String? documentLast4;

  @override
  void dispose() {
    _aadhaarController.dispose();
    _otpController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _cooldownTimer?.cancel();
    setState(() => resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (resendCooldown > 0) {
          setState(() => resendCooldown--);
        } else {
          timer.cancel();
        }
      }
    });
  }

  Future<void> _requestAadhaarOtp() async {
    if (!consentAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the verification consent to proceed.')),
      );
      return;
    }

    final rawAadhaar = _aadhaarController.text.replaceAll(RegExp(r'[\s\-]'), '');
    if (rawAadhaar.length != 12 || !RegExp(r'^\d{12}$').hasMatch(rawAadhaar)) {
      setState(() => errorMessage = 'Please enter a valid 12-digit Aadhaar number.');
      return;
    }

    setState(() {
      isBusy = true;
      errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.post('/identity/aadhaar/otp/request', {
        'aadhaarNumber': rawAadhaar,
        'consent': true,
      });

      if (res['success'] == true) {
        // Redact raw Aadhaar from controller immediately
        _aadhaarController.clear();
        setState(() {
          verificationSessionId = res['sessionId']?.toString();
          maskedAadhaar = res['maskedAadhaar']?.toString() ?? 'XXXX XXXX ${rawAadhaar.substring(8)}';
          currentStep = 1; // Move to OTP entry step
        });
        _startResendTimer();
      } else {
        setState(() {
          errorMessage = res['error']?.toString() ?? 'Identity verification is temporarily unavailable. Please try again later.';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Identity verification is temporarily unavailable. Please try again later.';
      });
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> _verifyAadhaarOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => errorMessage = 'Please enter the 6-digit OTP sent to your Aadhaar-linked mobile.');
      return;
    }

    if (verificationSessionId == null) {
      setState(() => errorMessage = 'Session expired. Please request a new OTP.');
      return;
    }

    setState(() {
      isBusy = true;
      errorMessage = null;
      currentStep = 2; // Show verification progress
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.post('/identity/aadhaar/otp/verify', {
        'verificationSessionId': verificationSessionId,
        'otp': otp,
      });

      _otpController.clear();

      if (res['success'] == true) {
        final statusStr = res['status']?.toString() ?? 'VERIFIED';
        ref.read(sessionManagerProvider.notifier).setIdentityStatus(statusStr);

        if (mounted) {
          setState(() {
            finalStatus = statusStr == 'VERIFIED'
                ? VerificationBadgeStatus.verified
                : VerificationBadgeStatus.verifiedTest;
            verifiedName = res['verifiedName']?.toString() ?? 'Aadhaar Verified Member';
            documentLast4 = res['documentLast4']?.toString() ?? (maskedAadhaar?.isNotEmpty == true ? maskedAadhaar!.substring(maskedAadhaar!.length - 4) : '1234');
            currentStep = 3; // Move to Result step
          });
        }
      } else {
        if (mounted) {
          setState(() {
            currentStep = 1;
            errorMessage = res['error']?.toString() ?? 'Identity verification is temporarily unavailable. Please try again later.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          currentStep = 1;
          errorMessage = 'Identity verification is temporarily unavailable. Please try again later.';
        });
      }
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your identity'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProgressIndicator(),
                  const SizedBox(height: 28),
                  if (errorMessage != null) _buildErrorMessage(),
                  if (currentStep == 0) _buildAadhaarInputStep(),
                  if (currentStep == 1) _buildOtpEntryStep(),
                  if (currentStep == 2) _buildVerificationProgressStep(),
                  if (currentStep == 3) _buildVerificationResultStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF87171)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(4, (index) {
        final isDone = index < currentStep;
        final isCurrent = index == currentStep;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 4,
            decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFF137333)
                  : isCurrent
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  // Step 0: Enter Aadhaar Number & Consent
  Widget _buildAadhaarInputStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Verify your identity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        const Text(
          'ShipdeHop verifies your identity via official Aadhaar OTP authentication to ensure community safety.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _aadhaarController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: '12-digit Aadhaar Number',
            hintText: 'Enter 12-digit number',
            prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF1E3A8A)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '🔒 Privacy & Security Guarantees',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
              ),
              SizedBox(height: 10),
              Text(
                '• Raw 12-digit Aadhaar numbers are never stored in databases or server logs.',
                style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.3),
              ),
              SizedBox(height: 6),
              Text(
                '• Verification is processed securely through official UIDAI e-KYC OTP authentication.',
                style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.3),
              ),
              SizedBox(height: 6),
              Text(
                '• OTP delivered to your Aadhaar-registered mobile number.',
                style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          value: consentAgreed,
          onChanged: (val) => setState(() => consentAgreed = val ?? false),
          title: const Text(
            'I consent to Aadhaar e-KYC verification for ShipdeHop identity verification and safety.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isBusy ? null : _requestAadhaarOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: isBusy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Send Aadhaar OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  // Step 1: Enter 6-digit Aadhaar OTP
  Widget _buildOtpEntryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter Aadhaar OTP',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit OTP sent to your Aadhaar-registered mobile (${maskedAadhaar ?? 'Aadhaar'}).',
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: '6-digit OTP',
            hintText: '123456',
            prefixIcon: const Icon(Icons.lock_clock_outlined, color: Color(0xFF1E3A8A)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              resendCooldown > 0 ? 'Resend OTP in ${resendCooldown}s' : 'OTP expired',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            TextButton(
              onPressed: (resendCooldown == 0 && !isBusy) ? _requestAadhaarOtp : null,
              child: const Text(
                'Resend OTP',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isBusy ? null : _verifyAadhaarOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: isBusy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Verify Aadhaar OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  // Step 2: Verification Progress
  Widget _buildVerificationProgressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Center(
          child: SizedBox(
            height: 48,
            width: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF1E3A8A)),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Verifying Aadhaar OTP...',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Authenticating directly with UIDAI e-KYC service.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  // Step 3: Verification Result Screen
  Widget _buildVerificationResultStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 48,
              color: Color(0xFF15803D),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Aadhaar Identity Verified',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your identity has been verified via official UIDAI Aadhaar e-KYC.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.4),
        ),
        const SizedBox(height: 24),
        Center(
          child: IdentityBadge(
            status: finalStatus,
            phoneVerified: true,
            governmentIdVerified: true,
            isAadhaarVerified: true,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verified Identity Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                '• Verified Name: ${verifiedName ?? 'Aadhaar Verified Member'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
              ),
              const SizedBox(height: 4),
              Text(
                '• Masked Aadhaar: ${maskedAadhaar ?? 'XXXX XXXX $documentLast4'}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Identity Provider: UIDAI e-KYC',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
