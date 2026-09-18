import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class AnalyticsSegmentOption {
  const AnalyticsSegmentOption({required this.id, required this.name});

  final String id;
  final String name;
}

final analyticsSegmentOptionsProvider =
    FutureProvider.family<List<AnalyticsSegmentOption>, String>((
      ref,
      siteId,
    ) async {
      final response = await ref
          .read(apiProvider)
          .request('GET', '/api/v1/sites/$siteId/segments');
      return (response as List)
          .whereType<Map>()
          .where((item) => item['enabled'] == true)
          .map(
            (item) => AnalyticsSegmentOption(
              id: item['id'] as String,
              name: item['name'] as String,
            ),
          )
          .toList(growable: false);
    });

final analyticsSegmentSelectionProvider =
    NotifierProvider.family<AnalyticsSegmentSelectionNotifier, String?, String>(
      AnalyticsSegmentSelectionNotifier.new,
    );

class AnalyticsSegmentSelectionNotifier extends Notifier<String?> {
  AnalyticsSegmentSelectionNotifier(this.siteId);

  final String siteId;

  @override
  String? build() => null;

  void select(String? segmentId) => state = segmentId;
}
