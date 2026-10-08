import 'package:flutter/material.dart';
import '../theme/shipdehop_colors.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/mascot_motion.dart';
import 'phone_auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final int initialPage;

  const OnboardingScreen({super.key, this.onComplete, this.initialPage = 0});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      headline: 'Go together',
      sub: 'Find rides or share your journey.',
      pose: MascotPose.ride,
      motion: MascotMotion.idleFloat,
    ),
    _OnboardingPageData(
      headline: 'Things can hop too',
      sub: 'Send parcels or get something brought by people already travelling.',
      pose: MascotPose.carryParcel,
      motion: MascotMotion.hop,
    ),
    _OnboardingPageData(
      headline: 'Every hop, protected',
      sub: 'Pickup and handoff checks help people coordinate each hop more safely.',
      pose: MascotPose.celebrate,
      motion: MascotMotion.celebrateOnce,
    ),
  ];

  void _finishOnboarding() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const PhoneAuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.brandDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Wordmark + Skip button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: 'Outfit', fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      children: [
                        const TextSpan(text: 'Shipde', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Hop', style: TextStyle(color: ShipdeHopColors.squirrelOrange)),
                      ],
                    ),
                  ),
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: _finishOnboarding,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            // Continuous Route Graphic Indicator Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Row(
                children: List.generate(_pages.length, (idx) {
                  final isActive = idx <= _currentPage;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isActive ? ShipdeHopColors.squirrelOrange : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Page View Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _pages.length,
                itemBuilder: (context, idx) {
                  final item = _pages[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                          ),
                          child: Center(
                            child: ShipdeHopMascot(
                              pose: item.pose,
                              motion: item.motion,
                              size: 160,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          item.headline,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.sub,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Primary Bottom CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < _pages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _finishOnboarding();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShipdeHopColors.squirrelOrange,
                    foregroundColor: ShipdeHopColors.brandDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1 ? 'Start Hopping' : 'Continue Journey',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final String headline;
  final String sub;
  final MascotPose pose;
  final MascotMotion motion;

  const _OnboardingPageData({
    required this.headline,
    required this.sub,
    required this.pose,
    required this.motion,
  });
}
