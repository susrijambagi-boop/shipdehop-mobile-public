import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'shd_skeleton.dart';
import '../../theme/shipdehop_colors.dart';

class ShdImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData fallbackIcon;

  const ShdImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12.0,
    this.fallbackIcon = Icons.image_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final hasValidUrl = imageUrl != null && imageUrl!.trim().isNotEmpty && imageUrl!.startsWith('http');

    Widget buildFallback() {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ShipdeHopColors.brandPrimaryLight,
              ShipdeHopColors.brandPrimary.withValues(alpha: 0.08),
              ShipdeHopColors.carpoolBg,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Icon(fallbackIcon, size: 24, color: ShipdeHopColors.brandPrimary),
              ),
            ],
          ),
        ),
      );
    }

    Widget child;
    if (!hasValidUrl) {
      child = buildFallback();
    } else {
      child = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => ShdSkeleton(
          enabled: true,
          child: Container(
            width: width,
            height: height,
            color: ShipdeHopColors.surfaceSubtle,
          ),
        ),
        errorWidget: (context, url, error) => buildFallback(),
      );
    }

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: child,
      );
    }
    return child;
  }
}
