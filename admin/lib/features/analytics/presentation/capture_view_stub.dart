import 'package:flutter/material.dart';

class CaptureView extends StatelessWidget {
  const CaptureView({
    required this.apiBase,
    required this.siteId,
    required this.resourceId,
    required this.accessToken,
    required this.mode,
    super.key,
  });
  final String apiBase, siteId, resourceId, accessToken, mode;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('DOM snapshots and recordings are available in Flutter Web.'),
  );
}
