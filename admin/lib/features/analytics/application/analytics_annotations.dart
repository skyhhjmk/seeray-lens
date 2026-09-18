import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class AnalyticsAnnotation {
  const AnalyticsAnnotation({
    required this.id,
    required this.date,
    required this.note,
  });

  final String id;
  final DateTime date;
  final String note;

  factory AnalyticsAnnotation.fromJson(Map<String, dynamic> json) =>
      AnalyticsAnnotation(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String? ?? '',
      );
}

class AnalyticsAnnotationsQuery {
  const AnalyticsAnnotationsQuery({
    required this.siteId,
    required this.from,
    required this.to,
  });

  final String siteId;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsAnnotationsQuery &&
      other.siteId == siteId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(siteId, from, to);
}

class AnalyticsAnnotationsState {
  const AnalyticsAnnotationsState({
    required this.from,
    required this.to,
    required this.annotations,
    required this.canManage,
  });

  final String from;
  final String to;
  final List<AnalyticsAnnotation> annotations;
  final bool canManage;

  factory AnalyticsAnnotationsState.fromJson(Map<String, dynamic> json) =>
      AnalyticsAnnotationsState(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        annotations: (json['annotations'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  AnalyticsAnnotation.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(growable: false),
        canManage: json['canManage'] as bool? ?? false,
      );
}

final analyticsAnnotationsRepositoryProvider = Provider(
  (ref) => AnalyticsAnnotationsRepository(ref),
);

final analyticsAnnotationsProvider =
    FutureProvider.family<AnalyticsAnnotationsState, AnalyticsAnnotationsQuery>(
      (ref, query) =>
          ref.read(analyticsAnnotationsRepositoryProvider).load(query),
    );

class AnalyticsAnnotationsRepository {
  AnalyticsAnnotationsRepository(this.ref);
  final Ref ref;

  Future<AnalyticsAnnotationsState> load(
    AnalyticsAnnotationsQuery query,
  ) async {
    final path =
        '/api/v1/sites/${query.siteId}/annotations'
        '?from=${query.from}&to=${query.to}';
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException('Invalid analytics annotations response');
    }
    return AnalyticsAnnotationsState.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  Future<AnalyticsAnnotation> save({
    required String siteId,
    String? annotationId,
    required String date,
    required String note,
  }) async {
    final result = await ref
        .read(apiProvider)
        .request(
          annotationId == null ? 'POST' : 'PUT',
          annotationId == null
              ? '/api/v1/sites/$siteId/annotations'
              : '/api/v1/sites/$siteId/annotations/$annotationId',
          body: {'date': date, 'note': note},
        );
    if (result is! Map) {
      throw const FormatException('Invalid analytics annotation response');
    }
    return AnalyticsAnnotation.fromJson(Map<String, dynamic>.from(result));
  }

  Future<void> delete(String siteId, String annotationId) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/sites/$siteId/annotations/$annotationId');
  }
}
