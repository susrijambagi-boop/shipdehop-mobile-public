import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';

class ShdSkeleton extends StatefulWidget {
  const ShdSkeleton({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<ShdSkeleton> createState() => _ShdSkeletonState();
}

class _ShdSkeletonState extends State<ShdSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: widget.child,
        );
      },
    );
  }
}

class ShdSkeletonBox extends StatelessWidget {
  const ShdSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShipdeHopColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
