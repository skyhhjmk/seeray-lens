import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../sites/application/site_controller.dart';

final workspaceRollupSitesProvider = FutureProvider.family<List<Site>, String>((
  ref,
  workspaceId,
) async {
  final data =
      await ref
              .read(apiProvider)
              .request('GET', '/api/v1/workspaces/$workspaceId/sites')
          as List;
  return data
      .map((item) => Site.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
});

class WorkspaceRollupQuery {
  WorkspaceRollupQuery({
    required this.workspaceId,
    required Iterable<String> siteIds,
    required this.from,
    required this.to,
  }) : siteIds = List.unmodifiable(siteIds.toSet().toList()..sort());

  final String workspaceId;
  final List<String> siteIds;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRollupQuery &&
      other.workspaceId == workspaceId &&
      other.from == from &&
      other.to == to &&
      listEquals(other.siteIds, siteIds);

  @override
  int get hashCode =>
      Object.hash(workspaceId, from, to, Object.hashAll(siteIds));
}

class WorkspaceRollupDaily {
  const WorkspaceRollupDaily({
    required this.date,
    required this.pageViews,
    required this.sessions,
    required this.siteVisitors,
  });

  final String date;
  final int pageViews;
  final int sessions;
  final int siteVisitors;

  factory WorkspaceRollupDaily.fromJson(Map<String, dynamic> json) =>
      WorkspaceRollupDaily(
        date: json['date'] as String,
        pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        siteVisitors: (json['siteVisitors'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceRollupSite {
  const WorkspaceRollupSite({
    required this.siteId,
    required this.name,
    required this.timezone,
    required this.trackingEnabled,
    required this.pageViews,
    required this.siteVisitors,
    required this.sessions,
    required this.bounceRate,
  });

  final String siteId;
  final String name;
  final String timezone;
  final bool trackingEnabled;
  final int pageViews;
  final int siteVisitors;
  final int sessions;
  final double bounceRate;

  factory WorkspaceRollupSite.fromJson(Map<String, dynamic> json) =>
      WorkspaceRollupSite(
        siteId: json['siteId'] as String,
        name: json['name'] as String,
        timezone: json['timezone'] as String? ?? 'UTC',
        trackingEnabled: json['trackingEnabled'] as bool? ?? false,
        pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
        siteVisitors: (json['siteVisitors'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as num?)?.toInt() ?? 0,
        bounceRate: (json['bounceRate'] as num?)?.toDouble() ?? 0,
      );
}

class WorkspaceRollupChannel {
  const WorkspaceRollupChannel(this.channel, this.sessions);

  final String channel;
  final int sessions;

  factory WorkspaceRollupChannel.fromJson(Map<String, dynamic> json) =>
      WorkspaceRollupChannel(
        json['channel'] as String? ?? 'direct',
        (json['sessions'] as num?)?.toInt() ?? 0,
      );
}

class WorkspaceRollupReport {
  const WorkspaceRollupReport({
    required this.from,
    required this.to,
    required this.siteCount,
    required this.pageViews,
    required this.siteVisitors,
    required this.sessions,
    required this.bounceRate,
    required this.daily,
    required this.sites,
    required this.channels,
  });

  final String from;
  final String to;
  final int siteCount;
  final int pageViews;
  final int siteVisitors;
  final int sessions;
  final double bounceRate;
  final List<WorkspaceRollupDaily> daily;
  final List<WorkspaceRollupSite> sites;
  final List<WorkspaceRollupChannel> channels;

  factory WorkspaceRollupReport.fromJson(
    Map<String, dynamic> json,
  ) => WorkspaceRollupReport(
    from: json['from'] as String,
    to: json['to'] as String,
    siteCount: (json['siteCount'] as num?)?.toInt() ?? 0,
    pageViews: (json['pageViews'] as num?)?.toInt() ?? 0,
    siteVisitors: (json['siteVisitors'] as num?)?.toInt() ?? 0,
    sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    bounceRate: (json['bounceRate'] as num?)?.toDouble() ?? 0,
    daily: (json['daily'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              WorkspaceRollupDaily.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
    sites: (json['sites'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              WorkspaceRollupSite.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
    channels: (json['channels'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              WorkspaceRollupChannel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );
}

final workspaceRollupProvider =
    FutureProvider.family<WorkspaceRollupReport, WorkspaceRollupQuery>((
      ref,
      query,
    ) async {
      final result = await ref
          .read(apiProvider)
          .request(
            'POST',
            '/api/v1/workspaces/${query.workspaceId}/analytics/rollup',
            body: {
              'siteIds': query.siteIds,
              'from': query.from,
              'to': query.to,
            },
          );
      return WorkspaceRollupReport.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    });
