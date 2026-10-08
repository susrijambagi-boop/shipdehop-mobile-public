import 'package:flutter/material.dart';
import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ShdBottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? bottomAction;

  const ShdBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.bottomAction,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    Widget? bottomAction,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: true,
      backgroundColor: ShipdeHopColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ShdBottomSheet(
          title: title,
          bottomAction: bottomAction,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: ShipdeHopColors.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ShipdeHopColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: ShipdeHopTypography.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: ShipdeHopColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(color: ShipdeHopColors.borderSubtle, height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
          if (bottomAction != null) ...[
            const Divider(color: ShipdeHopColors.borderSubtle, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: bottomAction!,
            ),
          ],
        ],
      ),
    );
  }
}
