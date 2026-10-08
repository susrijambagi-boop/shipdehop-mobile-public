import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/pending_verification_storage.dart';
import '../providers/app_providers.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/shipdehop_mascot.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String selectedCountryCode = '+91';
  String? sessionId;
  String? phoneE164;
  bool isBusy = false;
  int resendSeconds = 0;
  Timer? resendTimer;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_restorePendingSession);
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> _restorePendingSession() async {
    final pending = await PendingVerificationStorage.getPendingSessionId();
    if (pending == null || pending.isEmpty || !mounted) return;

    try {
      final status = await ref
          .read(apiClientProvider)
          .get('/auth/phone/status/' + pending, requireAuth: false);

      final currentStatus = status['status']?.toString();
      if (currentStatus == 'PHONE_VERIFIED') {
        await _exchangeSession(pending);
        return;
      }

      if (currentStatus == 'WAITING_FOR_WHATSAPP') {
        setState(() {
          sessionId = pending;
          phoneE164 = status['phoneE164']?.toString();
        });
        _startResendCountdown();
        return;
      }
    } catch (_) {}

    await PendingVerificationStorage.clearPendingSessionId();
  }

  String _normalizeE164(String raw) {
    var clean = raw.trim().replaceAll(RegExp(r'[\\s\\-\\(\\)\\.]'), '');
    if (clean.startsWith('+')) return clean;
    if (clean.startsWith('0091')) return '+91' + clean.substring(4);
    if (clean.startsWith('91') && clean.length == 12) return '+' + clean;
    if (clean.startsWith('0')) clean = clean.substring(1);
    return selectedCountryCode + clean;
  }

  bool _isValidIndiaPhone(String value) {
    return RegExp(r'^\\+91[6-9]\\d{9}$').hasMatch(value);
  }

  Future<void> _sendOtp() async {
    final normalized = _normalizeE164(phoneController.text);
    if (!_isValidIndiaPhone(normalized)) {
      _message('Enter a valid 10-digit Indian mobile number starting with 6-9.');
      return;
    }

    setState(() => isBusy = true);
    try {
      final response = await ref.read(apiClientProvider).post(
        '/auth/phone/start',
        {
          'phoneNumber': normalized,
          'countryCode': selectedCountryCode,
        },
        requireAuth: false,
      );

      final newSessionId = response['sessionId']?.toString() ?? '';
      if (newSessionId.isEmpty) {
        throw ApiException(500, 'OTP session was not created.');
      }

      await PendingVerificationStorage.savePendingSessionId(newSessionId);
      if (!mounted) return;

      setState(() {
        sessionId = newSessionId;
        phoneE164 = response['phoneE164']?.toString() ?? normalized;
        otpController.clear();
      });
      _startResendCountdown();
      _message('OTP sent to WhatsApp on ' + _maskedPhone(phoneE164 ?? normalized) + '.');
    } on ApiException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('Could not send the WhatsApp OTP. Please retry.');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  void _startResendCountdown() {
    resendTimer?.cancel();
    if (!mounted) return;

    setState(() => resendSeconds = 30);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (resendSeconds <= 1) {
        timer.cancel();
        setState(() => resendSeconds = 0);
      } else {
        setState(() => resendSeconds -= 1);
      }
    });
  }

  Future<void> _verifyOtp() async {
    final currentSession = sessionId;
    final otp = otpController.text.trim();

    if (currentSession == null || currentSession.isEmpty) {
      _message('Request a new WhatsApp OTP.');
      return;
    }
    if (!RegExp(r'^\\d{6}$').hasMatch(otp)) {
      _message('Enter the 6-digit OTP from WhatsApp.');
      return;
    }

    setState(() => isBusy = true);
    try {
      await ref.read(apiClientProvider).post(
        '/auth/phone/verify',
        {
          'sessionId': currentSession,
          'otp': otp,
        },
        requireAuth: false,
      );

      await _exchangeSession(currentSession);
    } on ApiException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('OTP verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> _exchangeSession(String currentSession) async {
    final exchange = await ref.read(apiClientProvider).post(
      '/auth/phone/exchange',
      {'sessionId': currentSession},
      requireAuth: false,
    );

    final userId = exchange['userId']?.toString();
    final accessToken = exchange['accessToken']?.toString();
    if (userId == null || accessToken == null) {
      throw ApiException(500, 'Could not create your ShipdeHop session.');
    }

    final identityStatus = exchange['identityStatus']?.toString() ?? 'NOT_STARTED';
    final isVerified = exchange['isIdentityVerified'] == true;

    ref.read(sessionManagerProvider.notifier).setSession(
      userId: userId,
      accessToken: accessToken,
      phoneE164: exchange['phoneE164']?.toString() ?? phoneE164,
      identityStatus: isVerified ? 'VERIFIED' : identityStatus,
      isIdentityVerified: isVerified,
      refreshToken: exchange['refreshToken']?.toString(),
    );

    await PendingVerificationStorage.clearPendingSessionId();
  }

  Future<void> _changeNumber() async {
    resendTimer?.cancel();
    await PendingVerificationStorage.clearPendingSessionId();
    if (!mounted) return;
    setState(() {
      sessionId = null;
      phoneE164 = null;
      otpController.clear();
      resendSeconds = 0;
    });
  }

  String _maskedPhone(String value) {
    if (value.length <= 6) return value;
    return value.substring(0, 3) + '******' + value.substring(value.length - 3);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final waitingForOtp = sessionId != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: ShipdeHopMascot(
                      pose: MascotPose.wave,
                      motion: MascotMotion.idleFloat,
                      size: 96,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome to ShipdeHop',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    waitingForOtp
                        ? 'Enter the 6-digit code we sent to your WhatsApp.'
                        : 'Enter your mobile number. We will send your sign-in code on WhatsApp.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!waitingForOtp) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          const Text('🇮🇳', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCountryCode,
                              items: const [
                                DropdownMenuItem(value: '+91', child: Text('+91')),
                              ],
                              onChanged: null,
                            ),
                          ),
                          const VerticalDivider(width: 20),
                          Expanded(
                            child: TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                                LengthLimitingTextInputFormatter(14),
                              ],
                              decoration: const InputDecoration(
                                hintText: 'Mobile number',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: isBusy ? null : _sendOtp,
                      icon: const Icon(Icons.chat_rounded),
                      label: Text(isBusy ? 'Sending…' : 'Send OTP on WhatsApp'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ] else ...[
                    if (phoneE164 != null)
                      Text(
                        _maskedPhone(phoneE164!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: otpController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 10,
                      ),
                      decoration: InputDecoration(
                        hintText: '000000',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!isBusy) _verifyOtp();
                      },
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: isBusy ? null : _verifyOtp,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: const Color(0xFF312E81),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(isBusy ? 'Verifying…' : 'Verify & continue'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: isBusy || resendSeconds > 0 ? null : _sendOtp,
                      child: Text(
                        resendSeconds > 0
                            ? 'Resend OTP in ' + resendSeconds.toString() + 's'
                            : 'Resend WhatsApp OTP',
                      ),
                    ),
                    TextButton(
                      onPressed: isBusy ? null : _changeNumber,
                      child: const Text('Use a different number'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'WhatsApp OTP is the only ShipdeHop sign-in method.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
