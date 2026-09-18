import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class WorkspaceAuditEntry {
  const WorkspaceAuditEntry({
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

  factory WorkspaceAuditEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuditEntry(
        id: json['id'] as String,
        actorEmail: json['actorEmail'] as String?,
        action: json['action'] as String,
        resource: json['resource'] as String,
        resourceId: json['resourceId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class WorkspaceAuditPage {
  const WorkspaceAuditPage(this.entries, this.nextCursor);

  final List<WorkspaceAuditEntry> entries;
  final String? nextCursor;

  factory WorkspaceAuditPage.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuditPage(
        ((json['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (entry) => WorkspaceAuditEntry.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            )
            .toList(growable: false),
        json['nextCursor'] as String?,
      );
}

final workspaceAuditLogProvider = Provider(
  (ref) => WorkspaceAuditLogRepository(ref),
);

class WorkspaceAuditLogRepository {
  WorkspaceAuditLogRepository(this.ref);
  final Ref ref;

  Future<WorkspaceAuditPage> load({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/workspaces/$workspaceId/audit-log',
      queryParameters: {
        'from': _date(from),
        'to': _date(to),
        'limit': '25',
        'cursor': ?cursor,
      },
    ).toString();
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException('Invalid workspace activity response');
    }
    return WorkspaceAuditPage.fromJson(Map<String, dynamic>.from(result));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
