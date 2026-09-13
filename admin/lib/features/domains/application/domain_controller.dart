import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class AllowedDomain {
  const AllowedDomain({
    required this.id,
    required this.host,
    required this.allowSubdomains,
    required this.enabled,
  });

  final String id;
  final String host;
  final bool allowSubdomains;
  final bool enabled;

  factory AllowedDomain.fromJson(Map<String, dynamic> json) => AllowedDomain(
    id: json['id'] as String,
    host: json['host'] as String,
    allowSubdomains: json['allowSubdomains'] as bool,
    enabled: json['enabled'] as bool,
  );
}

final domainsProvider =
    AsyncNotifierProvider.family<
      DomainsController,
      List<AllowedDomain>,
      String
    >(DomainsController.new);

class DomainsController extends AsyncNotifier<List<AllowedDomain>> {
  DomainsController(this.siteId);

  final String siteId;

  @override
  Future<List<AllowedDomain>> build() => load();

  Future<List<AllowedDomain>> load() async {
    final data =
        await ref
                .read(apiProvider)
                .request('GET', '/api/v1/sites/$siteId/domains')
            as List;
    return data
        .map((item) => AllowedDomain.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> create(String host, bool allowSubdomains, bool enabled) async {
    final data = await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/sites/$siteId/domains',
          body: {
            'host': host,
            'allowSubdomains': allowSubdomains,
            'enabled': enabled,
          },
        );
    final domain = AllowedDomain.fromJson(data as Map<String, dynamic>);
    state = AsyncData([...(state.value ?? const <AllowedDomain>[]), domain]);
  }

  Future<void> updateDomain(
    AllowedDomain domain, {
    required bool allowSubdomains,
    required bool enabled,
  }) async {
    final data = await ref
        .read(apiProvider)
        .request(
          'PATCH',
          '/api/v1/sites/$siteId/domains/${domain.id}',
          body: {'allowSubdomains': allowSubdomains, 'enabled': enabled},
        );
    final updated = AllowedDomain.fromJson(data as Map<String, dynamic>);
    state = AsyncData([
      for (final item in state.value ?? const <AllowedDomain>[])
        if (item.id == domain.id) updated else item,
    ]);
  }

  Future<void> deleteDomain(String domainId) async {
    await ref
        .read(apiProvider)
        .request('DELETE', '/api/v1/sites/$siteId/domains/$domainId');
    state = AsyncData(
      (state.value ?? const <AllowedDomain>[])
          .where((item) => item.id != domainId)
          .toList(),
    );
  }
}
