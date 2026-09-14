import 'package:flutter/material.dart';

import '../../core/i18n/app_i18n.dart';

class PageHelpButton extends StatelessWidget {
  const PageHelpButton({
    required this.englishTitle,
    required this.chineseTitle,
    required this.englishBody,
    required this.chineseBody,
    super.key,
  });

  final String englishTitle;
  final String chineseTitle;
  final String englishBody;
  final String chineseBody;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.tr('Help', '帮助'),
    icon: const Icon(Icons.help_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(englishTitle, chineseTitle)),
        content: Text(context.tr(englishBody, chineseBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('Got it', '知道了')),
          ),
        ],
      ),
    ),
  );
}
