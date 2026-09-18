import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/seeray_api.dart';
import '../../auth/application/auth_controller.dart';
import '../../workspaces/application/workspace_controller.dart';

class Site {
  const Site({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.trackingId,
    required this.timezone,
    required this.defaultLanguage,
    required this.trackingEnabled,
    this.requireConsent = false,
    required this.rawRetentionDays,
    required this.aggregateRetentionDays,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String trackingId;
  final String timezone;
  final String? defaultLanguage;
  final bool trackingEnabled;
  final bool requireConsent;
  final int rawRetentionDays;
  final int aggregateRetentionDays;

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    name: json['name'] as String,
    trackingId: json['trackingId'] as String,
    timezone: json['timezone'] as String,
    defaultLanguage: json['defaultLanguage'] as String?,
    trackingEnabled: json['trackingEnabled'] as bool,
    requireConsent: json['requireConsent'] as bool? ?? false,
    rawRetentionDays: json['rawRetentionDays'] as int,
    aggregateRetentionDays: json['aggregateRetentionDays'] as int,
  );
}

final sitesProvider = AsyncNotifierProvider<SitesController, List<Site>>(
  SitesController.new,
);

class SitesController extends AsyncNotifier<List<Site>> {
  @override
  Future<List<Site>> build() async {
    final workspace = ref.watch(currentWorkspaceProvider);
    if (workspace == null) return const [];
    return load(workspace.id);
  }

  Future<List<Site>> load([String? workspaceId]) async {
    final id = workspaceId ?? ref.read(currentWorkspaceProvider)?.id;
    if (id == null) return const [];
    final data =
        await ref
                .read(apiProvider)
                .request('GET', '/api/v1/workspaces/$id/sites')
            as List;
    return data
        .map((item) => Site.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Site> create(Map<String, dynamic> input) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) {
      throw const ApiFailure(0, 'Select a workspace first');
    }
    final data = await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/workspaces/${workspace.id}/sites',
          body: input,
        );
    final site = Site.fromJson(data as Map<String, dynamic>);
    state = AsyncData([...(state.value ?? const <Site>[]), site]);
    return site;
  }

  Future<Site> updateSite(String siteId, Map<String, dynamic> input) async {
    final data = await ref
        .read(apiProvider)
        .request('PATCH', '/api/v1/sites/$siteId', body: input);
    final updated = Site.fromJson(data as Map<String, dynamic>);
    state = AsyncData([
      for (final site in state.value ?? const <Site>[])
        if (site.id == siteId) updated else site,
    ]);
    return updated;
  }

  Future<void> delete(String siteId) async {
    await ref.read(apiProvider).request('DELETE', '/api/v1/sites/$siteId');
    state = AsyncData(
      (state.value ?? const <Site>[])
          .where((site) => site.id != siteId)
          .toList(),
    );
  }
}
