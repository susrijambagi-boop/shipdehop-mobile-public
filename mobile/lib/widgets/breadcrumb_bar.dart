import 'package:flutter/material.dart';

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.crumbs,
  });

  final List<String> crumbs;

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, size: 14, color: Colors.indigo),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                      ),
                    Text(
                      crumbs[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == crumbs.length - 1 ? FontWeight.bold : FontWeight.normal,
                        color: i == crumbs.length - 1 ? Colors.indigo : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
