import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../providers/app_providers.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final email = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (!email.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email address.')));
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(supabaseProvider).auth.signInWithOtp(
        email: email.text.trim(),
        emailRedirectTo: kIsWeb ? Uri.base.origin : 'com.shipdehop://login-callback/',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check your email for the secure sign-in link.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> devLogin(String targetEmail) async {
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await ref.read(apiClientProvider).post('/dev/auth/login-as-test-user', {
        'email': targetEmail,
      });

      final sessionMap = (response['session'] as Map).cast<String, dynamic>();
      final refreshToken = sessionMap['refresh_token'].toString();

      await ref.read(supabaseProvider).auth.setSession(refreshToken);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Dev session established for $targetEmail'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Dev login failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Dev login error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mascotMaxHeight = media.size.height * 0.22;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      height: mascotMaxHeight.clamp(110, 160),
                      child: ShipdeHopMascot(
                        pose: MascotPose.wave,
                        motion: MascotMotion.idleFloat,
                        size: 130,
                        badge: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF312E81),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mark_email_unread_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to ShipdeHop',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E1B4B),
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your email to sign in or create your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'you@example.com',
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF64748B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: busy ? null : signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF312E81),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        busy ? 'Sending link…' : 'Email me a sign-in link',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_rounded, size: 14, color: Color(0xFF312E81)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Secure sign-in. Some transaction features require additional verification.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  if (AppConfig.enableDevTestAuth) ...[
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      color: Colors.amber.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.amber, width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.developer_mode, color: Colors.brown, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'DEV TEST ACCOUNTS',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.brown,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Local dev shortcut to switch test accounts without email rate limits.',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              key: const Key('dev_login_sender_button'),
                              onPressed: busy ? null : () => devLogin('shipsterheadquarter@gmail.com'),
                              icon: const Icon(Icons.person_outline, size: 18),
                              label: const Text(
                                'Login as Sender / Buyer\nshipsterheadquarter@gmail.com',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              key: const Key('dev_login_carrier_button'),
                              onPressed: busy ? null : () => devLogin('susrijambagi@gmail.com'),
                              icon: const Icon(Icons.directions_car_outlined, size: 18),
                              label: const Text(
                                'Login as Carrier / Traveller\nsusrijambagi@gmail.com',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
