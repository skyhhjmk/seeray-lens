import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class SiteAuditEntry {
  const SiteAuditEntry({
    required this.id,
    required this.actorEmail,
    required this.action,
    required this.resource,
    required this.resourceId,
    required this.createdAt,
  });

  final String id;
  final String? actorEmail;
  final String action;
  final String resource;
  final String? resourceId;
  final DateTime createdAt;

  factory SiteAuditEntry.fromJson(Map<String, dynamic> json) => SiteAuditEntry(
    id: json['id'] as String,
    actorEmail: json['actorEmail'] as String?,
    action: json['action'] as String? ?? 'UPDATE',
    resource: json['resource'] as String? ?? 'site',
    resourceId: json['resourceId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );
}

class SiteAuditPage {
  const SiteAuditPage(this.entries, this.nextCursor);
  final List<SiteAuditEntry> entries;
  final String? nextCursor;

  factory SiteAuditPage.fromJson(Map<String, dynamic> json) => SiteAuditPage(
    ((json['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (entry) => SiteAuditEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false),
    json['nextCursor'] as String?,
  );
}

final siteAuditLogProvider = Provider((ref) => SiteAuditLogRepository(ref));

class SiteAuditLogRepository {
  SiteAuditLogRepository(this.ref);
  final Ref ref;

  Future<SiteAuditPage> load({
    required String siteId,
    required DateTime from,
    required DateTime to,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/sites/$siteId/audit-log',
      queryParameters: {
        'from': _date(from),
        'to': _date(to),
        'limit': '25',
        'cursor': ?cursor,
      },
    ).toString();
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException('Invalid audit-log response');
    }
    return SiteAuditPage.fromJson(Map<String, dynamic>.from(result));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
