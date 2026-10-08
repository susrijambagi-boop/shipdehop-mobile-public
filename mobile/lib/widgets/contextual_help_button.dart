import 'package:flutter/material.dart';
import '../core/help_content.dart';

enum ContextualHelpStyle {
  icon,
  textLink,
  chip,
}

class ContextualHelpButton extends StatelessWidget {
  const ContextualHelpButton({
    super.key,
    required this.topicId,
    this.style = ContextualHelpStyle.textLink,
    this.customLabel,
  });

  final String topicId;
  final ContextualHelpStyle style;
  final String? customLabel;

  static Widget showHelpModalIcon(BuildContext context, String topicId) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 18, color: Colors.teal),
      onPressed: () => showHelpModal(context, topicId),
    );
  }

  static void showHelpModal(BuildContext context, String topicId) {
    final topic = HelpContent.findById(topicId);
    if (topic == null) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topic.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Chip(
                    label: Text(
                      topic.category,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: Colors.teal.shade50,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                topic.shortExplanation,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                topic.fullExplanation,
                style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
              ),
              if (topic.relatedTopics.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Related Topics:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: topic.relatedTopics.map((relId) {
                    final relTopic = HelpContent.findById(relId);
                    if (relTopic == null) return const SizedBox.shrink();
                    return ActionChip(
                      label: Text(relTopic.title, style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        showHelpModal(context, relId);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topic = HelpContent.findById(topicId);
    final labelText = customLabel ?? (style == ContextualHelpStyle.textLink ? 'What does this mean?' : (topic?.title ?? 'Help'));

    if (style == ContextualHelpStyle.icon) {
      return IconButton(
        icon: const Icon(Icons.info_outline, size: 18, color: Colors.teal),
        tooltip: topic?.title ?? 'Help',
        onPressed: () => showHelpModal(context, topicId),
      );
    }

    if (style == ContextualHelpStyle.chip) {
      return ActionChip(
        avatar: const Icon(Icons.help_outline, size: 14, color: Colors.teal),
        label: Text(labelText, style: const TextStyle(fontSize: 11)),
        onPressed: () => showHelpModal(context, topicId),
      );
    }

    return InkWell(
      onTap: () => showHelpModal(context, topicId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 14, color: Colors.teal),
            const SizedBox(width: 4),
            Text(
              labelText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.teal.shade800,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
