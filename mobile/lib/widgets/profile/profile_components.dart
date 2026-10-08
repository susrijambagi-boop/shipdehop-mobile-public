import 'package:flutter/material.dart';

import '../../theme/shipdehop_colors.dart';
import '../../theme/shipdehop_typography.dart';

class ProfileDetailScaffold extends StatelessWidget {
  const ProfileDetailScaffold({super.key, required this.title, required this.children, this.floatingActionButton});

  final String title;
  final List<Widget> children;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title, style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: floatingActionButton,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    );
  }
}

class ProfileSectionTitle extends StatelessWidget {
  const ProfileSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: ShipdeHopTypography.labelSmall.copyWith(letterSpacing: 1.05));
}

class ProfileControlCard extends StatelessWidget {
  const ProfileControlCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: ShipdeHopColors.brandPrimary, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 15)),
                const SizedBox(height: 5),
                Text(body, style: ShipdeHopTypography.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileLoadingCard extends StatelessWidget {
  const ProfileLoadingCard({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12), Text(label)]),
      );
}

class ProfileRetryCard extends StatelessWidget {
  const ProfileRetryCard({super.key, required this.title, required this.onRetry});
  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [Expanded(child: Text(title)), TextButton(onPressed: onRetry, child: const Text('Retry'))]),
      );
}

class ProfileMetricCard extends StatelessWidget {
  const ProfileMetricCard({super.key, required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: ShipdeHopColors.brandPrimary),
          const SizedBox(height: 8),
          Text(value, style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 19)),
          const SizedBox(height: 2),
          Text(label, style: ShipdeHopTypography.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

String profileHumanize(String value) {
  if (value.isEmpty) return '';
  return value
      .toLowerCase()
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String profileFormatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
