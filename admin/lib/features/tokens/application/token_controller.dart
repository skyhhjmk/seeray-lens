import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/seeray_api.dart';
import '../../auth/application/auth_controller.dart';
import '../../workspaces/application/workspace_controller.dart';

class ApiTokenSummary {
  const ApiTokenSummary({
    required this.id,
    required this.name,
    required this.prefix,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
  });

  final String id;
  final String name;
  final String prefix;
  final String scopes;
  final String createdAt;
  final String? expiresAt;
  final String? revokedAt;

  factory ApiTokenSummary.fromJson(Map<String, dynamic> json) =>
      ApiTokenSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        prefix: json['tokenPrefix'] as String,
        scopes: json['scopes'] as String,
        createdAt: json['createdAt'] as String,
        expiresAt: json['expiresAt'] as String?,
        revokedAt: json['revokedAt'] as String?,
      );
}

class CreatedApiToken {
  const CreatedApiToken(this.summary, this.plainToken);
  final ApiTokenSummary summary;
  final String plainToken;
}

final apiTokensProvider =
    AsyncNotifierProvider<ApiTokensController, List<ApiTokenSummary>>(
      ApiTokensController.new,
    );

class ApiTokensController extends AsyncNotifier<List<ApiTokenSummary>> {
  @override
  Future<List<ApiTokenSummary>> build() async {
    final workspace = ref.watch(currentWorkspaceProvider);
    if (workspace == null) return const [];
    return load(workspace.id);
  }

  Future<List<ApiTokenSummary>> load([String? workspaceId]) async {
    final id = workspaceId ?? ref.read(currentWorkspaceProvider)?.id;
    if (id == null) return const [];
    final data =
        await ref
                .read(apiProvider)
                .request('GET', '/api/v1/workspaces/$id/api-tokens')
            as List;
    return data
        .map((item) => ApiTokenSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<CreatedApiToken> create(String name, List<String> scopes) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) {
      throw const ApiFailure(0, 'Select a workspace first');
    }
    final data =
        await ref
                .read(apiProvider)
                .request(
                  'POST',
                  '/api/v1/workspaces/${workspace.id}/api-tokens',
                  body: {'name': name, 'scopes': scopes},
                )
            as Map<String, dynamic>;
    final created = CreatedApiToken(
      ApiTokenSummary.fromJson(data['token'] as Map<String, dynamic>),
      data['plainToken'] as String,
    );
    state = AsyncData([
      ...(state.value ?? const <ApiTokenSummary>[]),
      created.summary,
    ]);
    return created;
  }

  Future<void> revoke(String tokenId) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) {
      throw const ApiFailure(0, 'Select a workspace first');
    }
    await ref
        .read(apiProvider)
        .request(
          'POST',
          '/api/v1/workspaces/${workspace.id}/api-tokens/$tokenId/revoke',
        );
    state = AsyncData(await load(workspace.id));
  }
}
