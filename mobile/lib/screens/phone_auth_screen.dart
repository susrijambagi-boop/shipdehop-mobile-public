import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/pending_verification_storage.dart';
import '../providers/app_providers.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import 'identity_verification_screen.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final phoneController = TextEditingController();
  final emailController = TextEditingController();

  String selectedCountryCode = '+91';
  bool isEmailMode = false;
  bool isBusy = false;

  final List<Map<String, String>> countries = const [
    {'name': 'India', 'code': '+91', 'flag': '🇮🇳'},
    {'name': 'Qatar', 'code': '+974', 'flag': '🇶🇦'},
    {'name': 'UAE', 'code': '+971', 'flag': '🇦🇪'},
    {'name': 'United States', 'code': '+1', 'flag': '🇺🇸'},
    {'name': 'United Kingdom', 'code': '+44', 'flag': '🇬🇧'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRestorePendingSession();
    });
  }

  Future<void> _checkAndRestorePendingSession() async {
    final pendingSessionId = await PendingVerificationStorage.getPendingSessionId();
    if (pendingSessionId == null || pendingSessionId.isEmpty || !mounted) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final status = await apiClient.get('/auth/phone/status/$pendingSessionId', requireAuth: false);
      if (!mounted) return;

      final currentStatus = status['status']?.toString();
      if (currentStatus == 'WAITING_FOR_WHATSAPP') {
        _showWhatsAppChallengeModal(
          pendingSessionId,
          '',
          '',
          status['phoneE164']?.toString() ?? '',
        );
      } else if (currentStatus == 'PHONE_VERIFIED') {
        _directExchangeSession(pendingSessionId, status['phoneE164']?.toString() ?? '');
      } else {
        await PendingVerificationStorage.clearPendingSessionId();
      }
    } catch (_) {
      await PendingVerificationStorage.clearPendingSessionId();
    }
  }

  Future<void> _directExchangeSession(String sessionId, String phoneE164) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final exchange = await apiClient.post('/auth/phone/exchange', {
        'sessionId': sessionId,
      }, requireAuth: false);

      await PendingVerificationStorage.clearPendingSessionId();

      final resolvedPhone = exchange['phoneE164']?.toString() ?? phoneE164;
      if (exchange['accessToken'] != null && exchange['userId'] != null) {
        ref.read(sessionManagerProvider.notifier).setSession(
          userId: exchange['userId'] as String,
          accessToken: exchange['accessToken'] as String,
          phoneE164: resolvedPhone,
        );
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (c) => IdentityVerificationScreen(phoneE164: resolvedPhone),
          ),
        );
      }
    } catch (_) {
      await PendingVerificationStorage.clearPendingSessionId();
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  String _normalizeE164(String raw, String countryCode) {
    String clean = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (clean.startsWith('+')) return clean;
    if (clean.startsWith('00')) return '+${clean.substring(2)}';
    final ccDigits = countryCode.replaceAll('+', '');
    if (clean.startsWith(ccDigits) && clean.length == (ccDigits.length + 10)) {
      return '+$clean';
    }
    if (clean.startsWith('0')) return '$countryCode${clean.substring(1)}';
    return '$countryCode$clean';
  }

  Future<void> _startWhatsAppVerification() async {
    final rawNumber = phoneController.text.trim();
    final normalized = _normalizeE164(rawNumber, selectedCountryCode);
    final digitsOnly = rawNumber.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');

    if (selectedCountryCode == '+91') {
      if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(normalized)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 10-digit Indian mobile number starting with 6-9.')),
        );
        return;
      }
    } else {
      if (digitsOnly.length < 7 || RegExp(r'[a-zA-Z]').hasMatch(rawNumber)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid mobile phone number.')),
        );
        return;
      }
    }

    setState(() => isBusy = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/auth/phone/start',
        {
          'phoneNumber': normalized,
          'countryCode': selectedCountryCode,
        },
        requireAuth: false,
      );

      final sessionId = response['sessionId']?.toString() ?? '';
      final challenge = response['challenge']?.toString() ?? '';
      final whatsappUrl = response['whatsappUrl']?.toString() ?? '';

      if (sessionId.isNotEmpty) {
        await PendingVerificationStorage.savePendingSessionId(sessionId);
      }

      if (mounted) {
        _showWhatsAppChallengeModal(sessionId, challenge, whatsappUrl, normalized);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  void _showWhatsAppChallengeModal(
    String sessionId,
    String challenge,
    String whatsappUrl,
    String phoneE164,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _WhatsAppWaitingSheet(
        sessionId: sessionId,
        challenge: challenge,
        whatsappUrl: whatsappUrl,
        phoneE164: phoneE164,
        onVerified: () {
          Navigator.of(ctx).maybePop();
        },
      ),
    );
  }

  Future<void> _sendEmailMagicLink() async {
    final email = emailController.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() => isBusy = true);
    try {
      await ref.read(supabaseProvider).auth.signInWithOtp(
        email: email,
        emailRedirectTo: kIsWeb ? Uri.base.origin : 'com.shipdehop://login-callback/',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your inbox for the secure sign-in link.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                  Text(
                    'Welcome to ShipdeHop',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isEmailMode
                        ? 'Enter your email to sign in or recover your account.'
                        : 'Enter your mobile number to get started with zero-cost verification.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (!isEmailMode) ...[
                    // Phone number entry
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCountryCode,
                              items: countries.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c['code'],
                                  child: Text('${c['flag']} ${c['code']}'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => selectedCountryCode = val);
                                }
                              },
                            ),
                          ),
                          const VerticalDivider(width: 16, thickness: 1),
                          Expanded(
                            child: TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                hintText: 'Mobile Number',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isBusy ? null : _startWhatsAppVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: isBusy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Verify with WhatsApp',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ] else ...[
                    // Email mode
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: isBusy ? null : _sendEmailMagicLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: isBusy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Email me a sign-in link',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  // Toggle between Phone and Email
                  TextButton(
                    onPressed: () => setState(() => isEmailMode = !isEmailMode),
                    child: Text(
                      isEmailMode ? '← Back to Phone verification' : 'Or continue with Email',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Secure phone & trust verification',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          textAlign: TextAlign.center,
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

class _WhatsAppWaitingSheet extends ConsumerStatefulWidget {
  final String sessionId;
  final String challenge;
  final String whatsappUrl;
  final String phoneE164;
  final VoidCallback onVerified;

  const _WhatsAppWaitingSheet({
    required this.sessionId,
    required this.challenge,
    required this.whatsappUrl,
    required this.phoneE164,
    required this.onVerified,
  });

  @override
  ConsumerState<_WhatsAppWaitingSheet> createState() => _WhatsAppWaitingSheetState();
}

class _WhatsAppWaitingSheetState extends ConsumerState<_WhatsAppWaitingSheet> with WidgetsBindingObserver {
  Timer? pollTimer;
  int remainingSeconds = 300; // 5 min TTL
  Timer? countdownTimer;
  bool isExchanging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && remainingSeconds > 0) {
        setState(() => remainingSeconds--);
      } else {
        t.cancel();
        PendingVerificationStorage.clearPendingSessionId();
      }
    });
    _startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollOnceAndExchange();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    countdownTimer?.cancel();
    pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      await _pollOnceAndExchange();
    });
  }

  Future<void> _pollOnceAndExchange() async {
    if (!mounted || isExchanging) return;
    try {
      final apiClient = ref.read(apiClientProvider);
      final status = await apiClient.get('/auth/phone/status/${widget.sessionId}', requireAuth: false);
      if (!mounted || isExchanging) return;

      final currentStatus = status['status']?.toString();
      if (currentStatus == 'PHONE_VERIFIED') {
        isExchanging = true;
        pollTimer?.cancel();
        countdownTimer?.cancel();

        final exchange = await apiClient.post('/auth/phone/exchange', {
          'sessionId': widget.sessionId,
        }, requireAuth: false);

        await PendingVerificationStorage.clearPendingSessionId();

        final resolvedPhone = exchange['phoneE164']?.toString() ?? widget.phoneE164;
        final identityStatus = exchange['identityStatus']?.toString() ?? 'NOT_STARTED';
        final isVerified = exchange['isIdentityVerified'] == true;
        if (exchange['accessToken'] != null && exchange['userId'] != null) {
          ref.read(sessionManagerProvider.notifier).setSession(
            userId: exchange['userId'] as String,
            accessToken: exchange['accessToken'] as String,
            phoneE164: resolvedPhone,
            identityStatus: isVerified ? 'VERIFIED' : identityStatus,
            isIdentityVerified: isVerified,
          );
        }
        widget.onVerified();
      } else if (currentStatus == 'EXPIRED' || currentStatus == 'BLOCKED' || currentStatus == 'CONSUMED') {
        await PendingVerificationStorage.clearPendingSessionId();
      }
    } catch (_) {
      // Retry
    }
  }

  Future<void> _openWhatsApp() async {
    if (widget.whatsappUrl.isEmpty) return;
    final uri = Uri.parse(widget.whatsappUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366), size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Send Verification Challenge',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '$minutes:$seconds',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE11D48)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.phoneE164.isNotEmpty
                  ? 'To prove ownership of ${widget.phoneE164}, send your one-time code to ShipdeHop on WhatsApp.'
                  : 'Send your one-time verification code to ShipdeHop on WhatsApp.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            if (widget.challenge.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text(
                  widget.challenge,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
            if (widget.whatsappUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _openWhatsApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.send_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Open WhatsApp & Send', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await PendingVerificationStorage.clearPendingSessionId();
                nav.pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }
}

