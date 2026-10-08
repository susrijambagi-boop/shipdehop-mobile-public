import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'mascot_pose.dart';
import 'mascot_motion.dart';

/// Central presentation component for the canonical ShipdeHop squirrel mascot.
/// Decouples visual state (MascotPose) from motion behavior (MascotMotion).
/// Prepares for future Rive/Lottie rendering engine swap without changing call-sites.
class ShipdeHopMascot extends StatefulWidget {
  final MascotPose pose;
  final MascotMotion motion;
  final double size;
  final Widget? badge;
  final VoidCallback? onTap;
  final String? customLabel;
  final BoxFit fit;

  const ShipdeHopMascot({
    super.key,
    this.pose = MascotPose.idle,
    this.motion = MascotMotion.idleFloat,
    this.size = 120.0,
    this.badge,
    this.onTap,
    this.customLabel,
    this.fit = BoxFit.contain,
  });

  @override
  State<ShipdeHopMascot> createState() => _ShipdeHopMascotState();
}

class _ShipdeHopMascotState extends State<ShipdeHopMascot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isTapped = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _getDurationForMotion(widget.motion),
    );
    final bool isTestMode = Animate.defaultDuration == Duration.zero;
    if (widget.motion != MascotMotion.none && !isTestMode) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ShipdeHopMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      _controller.duration = _getDurationForMotion(widget.motion);
      final bool isTestMode = Animate.defaultDuration == Duration.zero;
      if (widget.motion == MascotMotion.none || isTestMode) {
        _controller.stop();
        _controller.reset();
      } else {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _getDurationForMotion(MascotMotion motion) {
    switch (motion) {
      case MascotMotion.idleFloat:
        return const Duration(milliseconds: 2800);
      case MascotMotion.hop:
        return const Duration(milliseconds: 550);
      case MascotMotion.runMatching:
        return const Duration(milliseconds: 400);
      case MascotMotion.bellWiggle:
        return const Duration(milliseconds: 650);
      case MascotMotion.celebrateOnce:
        return const Duration(milliseconds: 850);
      case MascotMotion.typingPulse:
        return const Duration(milliseconds: 1200);
      case MascotMotion.routeGlide:
        return const Duration(milliseconds: 1500);
      case MascotMotion.none:
        return Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final disableAnimations = media?.disableAnimations ?? false;
    final semanticsLabel = widget.customLabel ?? widget.pose.semanticLabel;

    Widget mascotCore = Image.asset(
      widget.pose.assetPath,
      width: widget.size,
      height: widget.size,
      fit: widget.fit,
      semanticLabel: semanticsLabel,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to canonical idle image if missing pose file
        return Image.asset(
          'assets/mascot/shipdehop_squirrel_canonical.png',
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          semanticLabel: semanticsLabel,
          errorBuilder: (ctx, err, stack) => Icon(
            Icons.pets,
            size: widget.size * 0.6,
            color: const Color(0xFFF97316),
          ),
        );
      },
    );

    // Contextual Badge Overlay
    if (widget.badge != null || widget.pose.badgeIcon != null) {
      final badgeChild = widget.badge ??
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFFF97316),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.pose.badgeIcon,
              size: widget.size * 0.2,
              color: Colors.white,
            ),
          );

      mascotCore = Stack(
        alignment: Alignment.topRight,
        children: [
          mascotCore,
          Positioned(
            top: 0,
            right: 0,
            child: badgeChild,
          ),
        ],
      );
    }

    final isTestEnvironment = WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding') ||
        disableAnimations ||
        Animate.defaultDuration == Duration.zero;

    if (isTestEnvironment || widget.motion == MascotMotion.none) {
      return GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: mascotCore,
        ),
      );
    }

    // Flutter-native motion presets using flutter_animate / AnimatedBuilder
    Widget animatedMascot;
    switch (widget.motion) {
      case MascotMotion.idleFloat:
        animatedMascot = mascotCore
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: -2, end: 4, duration: 2800.ms, curve: Curves.easeInOut);
        break;

      case MascotMotion.hop:
        animatedMascot = mascotCore
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -8, duration: 500.ms, curve: Curves.easeOutCubic)
            .scale(begin: const Offset(1, 1), end: const Offset(0.96, 1.04), duration: 500.ms);
        break;

      case MascotMotion.runMatching:
        animatedMascot = mascotCore
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -6, duration: 350.ms, curve: Curves.easeOut)
            .rotate(begin: -0.02, end: 0.02, duration: 350.ms);
        break;

      case MascotMotion.bellWiggle:
        animatedMascot = mascotCore
            .animate()
            .rotate(begin: -0.07, end: 0.07, duration: 250.ms, curve: Curves.easeInOut)
            .then()
            .rotate(begin: 0.07, end: 0.0, duration: 250.ms);
        break;

      case MascotMotion.celebrateOnce:
        animatedMascot = mascotCore
            .animate()
            .scale(begin: const Offset(0.92, 0.92), end: const Offset(1.08, 1.08), duration: 400.ms, curve: Curves.easeOutBack)
            .then()
            .scale(begin: const Offset(1.08, 1.08), end: const Offset(1.0, 1.0), duration: 300.ms);
        break;

      case MascotMotion.typingPulse:
        animatedMascot = Stack(
          alignment: Alignment.topRight,
          children: [
            mascotCore,
            Positioned(
              top: 0,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDot(0),
                    const SizedBox(width: 2),
                    _buildDot(200),
                    const SizedBox(width: 2),
                    _buildDot(400),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case MascotMotion.routeGlide:
        animatedMascot = mascotCore
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveX(begin: -5, end: 5, duration: 1500.ms, curve: Curves.easeInOut)
            .moveY(begin: -2, end: 2, duration: 1500.ms);
        break;

      case MascotMotion.none:
        animatedMascot = mascotCore;
        break;
    }

    return GestureDetector(
      onTap: () {
        setState(() => _isTapped = true);
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _isTapped = false);
        });
        if (widget.onTap != null) widget.onTap!();
      },
      child: AnimatedScale(
        scale: _isTapped ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: animatedMascot,
        ),
      ),
    );
  }

  Widget _buildDot(int delayMs) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        color: Color(0xFFF97316),
        shape: BoxShape.circle,
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.3, 1.3), delay: delayMs.ms, duration: 500.ms);
  }
}
