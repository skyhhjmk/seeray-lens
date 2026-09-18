import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class WorkspaceAuditEntry {
  const WorkspaceAuditEntry({
    required this.id,
    required this.actorEmail,
    required this.actorApiTokenName,
    required this.action,
    required this.resource,
    required this.resourceId,
    required this.createdAt,
  });

  final String id;
  final String? actorEmail;
  final String? actorApiTokenName;
  final String action;
  final String resource;
  final String? resourceId;
  final DateTime createdAt;

  factory WorkspaceAuditEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuditEntry(
        id: json['id'] as String,
        actorEmail: json['actorEmail'] as String?,
        actorApiTokenName: json['actorApiTokenName'] as String?,
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

class WorkspaceApiReadEntry {
  const WorkspaceApiReadEntry({
    required this.id,
    required this.actorEmail,
    required this.siteId,
    required this.siteName,
    required this.method,
    required this.routeTemplate,
    required this.statusCode,
    required this.createdAt,
  });

  final String id;
  final String? actorEmail;
  final String? siteId;
  final String? siteName;
  final String method;
  final String routeTemplate;
  final int statusCode;
  final DateTime createdAt;

  factory WorkspaceApiReadEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceApiReadEntry(
        id: json['id'] as String,
        actorEmail: json['actorEmail'] as String?,
        siteId: json['siteId'] as String?,
        siteName: json['siteName'] as String?,
        method: json['method'] as String,
        routeTemplate: json['routeTemplate'] as String,
        statusCode: (json['statusCode'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class WorkspaceApiReadPage {
  const WorkspaceApiReadPage(this.entries, this.nextCursor, this.retentionDays);

  final List<WorkspaceApiReadEntry> entries;
  final String? nextCursor;
  final int retentionDays;

  factory WorkspaceApiReadPage.fromJson(
    Map<String, dynamic> json,
  ) => WorkspaceApiReadPage(
    ((json['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (entry) =>
              WorkspaceApiReadEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false),
    json['nextCursor'] as String?,
    (json['retentionDays'] as num?)?.toInt() ?? 30,
  );
}

final workspaceApiReadLogProvider = Provider(
  (ref) => WorkspaceApiReadLogRepository(ref),
);

class WorkspaceAuthActivityEntry {
  const WorkspaceAuthActivityEntry({
    required this.id,
    required this.actorEmail,
    required this.eventType,
    required this.createdAt,
  });

  final String id;
  final String? actorEmail;
  final String eventType;
  final DateTime createdAt;

  factory WorkspaceAuthActivityEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuthActivityEntry(
        id: json['id'] as String,
        actorEmail: json['actorEmail'] as String?,
        eventType: json['eventType'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class WorkspaceAuthActivityPage {
  const WorkspaceAuthActivityPage(
    this.entries,
    this.nextCursor,
    this.retentionDays,
  );

  final List<WorkspaceAuthActivityEntry> entries;
  final String? nextCursor;
  final int retentionDays;

  factory WorkspaceAuthActivityPage.fromJson(Map<String, dynamic> json) =>
      WorkspaceAuthActivityPage(
        ((json['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (entry) => WorkspaceAuthActivityEntry.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            )
            .toList(growable: false),
        json['nextCursor'] as String?,
        (json['retentionDays'] as num?)?.toInt() ?? 30,
      );
}

final workspaceAuthActivityProvider = Provider(
  (ref) => WorkspaceAuthActivityRepository(ref),
);

class WorkspaceAuthActivityRepository {
  WorkspaceAuthActivityRepository(this.ref);
  final Ref ref;

  Future<WorkspaceAuthActivityPage> load({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/workspaces/$workspaceId/auth-activity',
      queryParameters: {
        'from': _date(from),
        'to': _date(to),
        'limit': '25',
        'cursor': ?cursor,
      },
    ).toString();
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException('Invalid authentication activity response');
    }
    return WorkspaceAuthActivityPage.fromJson(
      Map<String, dynamic>.from(result),
    );
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class WorkspaceApiReadLogRepository {
  WorkspaceApiReadLogRepository(this.ref);
  final Ref ref;

  Future<WorkspaceApiReadPage> load({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/workspaces/$workspaceId/api-read-log',
      queryParameters: {
        'from': _date(from),
        'to': _date(to),
        'limit': '25',
        'cursor': ?cursor,
      },
    ).toString();
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException(
        'Invalid workspace API read history response',
      );
    }
    return WorkspaceApiReadPage.fromJson(Map<String, dynamic>.from(result));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class WorkspaceApiWriteEntry {
  const WorkspaceApiWriteEntry({
    required this.id,
    required this.actorEmail,
    required this.siteId,
    required this.siteName,
    required this.method,
    required this.routeTemplate,
    required this.statusCode,
    required this.createdAt,
  });

  final String id;
  final String? actorEmail;
  final String? siteId;
  final String? siteName;
  final String method;
  final String routeTemplate;
  final int statusCode;
  final DateTime createdAt;

  factory WorkspaceApiWriteEntry.fromJson(Map<String, dynamic> json) =>
      WorkspaceApiWriteEntry(
        id: json['id'] as String,
        actorEmail: json['actorEmail'] as String?,
        siteId: json['siteId'] as String?,
        siteName: json['siteName'] as String?,
        method: json['method'] as String,
        routeTemplate: json['routeTemplate'] as String,
        statusCode: (json['statusCode'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class WorkspaceApiWritePage {
  const WorkspaceApiWritePage(
    this.entries,
    this.nextCursor,
    this.retentionDays,
  );

  final List<WorkspaceApiWriteEntry> entries;
  final String? nextCursor;
  final int retentionDays;

  factory WorkspaceApiWritePage.fromJson(
    Map<String, dynamic> json,
  ) => WorkspaceApiWritePage(
    ((json['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (entry) =>
              WorkspaceApiWriteEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false),
    json['nextCursor'] as String?,
    (json['retentionDays'] as num?)?.toInt() ?? 30,
  );
}

final workspaceApiWriteLogProvider = Provider(
  (ref) => WorkspaceApiWriteLogRepository(ref),
);

class WorkspaceApiWriteLogRepository {
  WorkspaceApiWriteLogRepository(this.ref);
  final Ref ref;

  Future<WorkspaceApiWritePage> load({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/workspaces/$workspaceId/api-write-log',
      queryParameters: {
        'from': _date(from),
        'to': _date(to),
        'limit': '25',
        'cursor': ?cursor,
      },
    ).toString();
    final result = await ref.read(apiProvider).request('GET', path);
    if (result is! Map) {
      throw const FormatException(
        'Invalid workspace API write history response',
      );
    }
    return WorkspaceApiWritePage.fromJson(Map<String, dynamic>.from(result));
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
