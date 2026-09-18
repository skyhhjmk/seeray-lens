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
    required this.lastUsedAt,
    required this.expiresAt,
    required this.revokedAt,
  });

  final String id;
  final String name;
  final String prefix;
  final String scopes;
  final String createdAt;
  final String? lastUsedAt;
  final String? expiresAt;
  final String? revokedAt;

  bool get isExpired =>
      expiresAt != null &&
      (DateTime.tryParse(expiresAt!)?.isBefore(DateTime.now()) ?? false);

  factory ApiTokenSummary.fromJson(Map<String, dynamic> json) =>
      ApiTokenSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        prefix: json['tokenPrefix'] as String,
        scopes: json['scopes'] as String,
        createdAt: json['createdAt'] as String,
        lastUsedAt: json['lastUsedAt'] as String?,
        expiresAt: json['expiresAt'] as String?,
        revokedAt: json['revokedAt'] as String?,
      );
}

class CreatedApiToken {
  const CreatedApiToken(this.summary, this.plainToken);
  final ApiTokenSummary summary;
  final String plainToken;
}

class ApiTokenUsageEntry {
  const ApiTokenUsageEntry({
    required this.id,
    required this.method,
    required this.routeTemplate,
    required this.statusCode,
    required this.createdAt,
  });

  final String id;
  final String method;
  final String routeTemplate;
  final int statusCode;
  final DateTime createdAt;

  factory ApiTokenUsageEntry.fromJson(Map<String, dynamic> json) =>
      ApiTokenUsageEntry(
        id: json['id'] as String,
        method: json['method'] as String,
        routeTemplate: json['routeTemplate'] as String,
        statusCode: (json['statusCode'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}

class ApiTokenUsagePage {
  const ApiTokenUsagePage({
    required this.entries,
    required this.nextCursor,
    required this.retentionDays,
  });

  final List<ApiTokenUsageEntry> entries;
  final String? nextCursor;
  final int retentionDays;

  factory ApiTokenUsagePage.fromJson(Map<String, dynamic> json) =>
      ApiTokenUsagePage(
        entries: ((json['entries'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (entry) =>
                  ApiTokenUsageEntry.fromJson(Map<String, dynamic>.from(entry)),
            )
            .toList(growable: false),
        nextCursor: json['nextCursor'] as String?,
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 30,
      );
}

final apiTokenUsageRepositoryProvider = Provider(
  (ref) => ApiTokenUsageRepository(ref),
);

class ApiTokenUsageRepository {
  ApiTokenUsageRepository(this.ref);
  final Ref ref;

  Future<ApiTokenUsagePage> load({
    required String workspaceId,
    required String tokenId,
    String? cursor,
  }) async {
    final path = Uri(
      path: '/api/v1/workspaces/$workspaceId/api-tokens/$tokenId/usage',
      queryParameters: {'limit': '25', 'cursor': ?cursor},
    ).toString();
    final response = await ref.read(apiProvider).request('GET', path);
    if (response is! Map) {
      throw const FormatException('Invalid API token activity response');
    }
    return ApiTokenUsagePage.fromJson(Map<String, dynamic>.from(response));
  }
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

  Future<CreatedApiToken> create(
    String name,
    List<String> scopes, {
    DateTime? expiresAt,
  }) async {
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
                  body: {
                    'name': name,
                    'scopes': scopes,
                    if (expiresAt != null)
                      'expiresAt': expiresAt.toUtc().toIso8601String(),
                  },
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
