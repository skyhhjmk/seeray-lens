import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/domains/presentation/domains_page.dart';
import 'features/sites/presentation/site_detail_page.dart';
import 'features/sites/presentation/sites_page.dart';
import 'features/tokens/presentation/token_settings_page.dart';
import 'features/workspaces/presentation/workspace_page.dart';

class SeeRayLensAdminApp extends ConsumerWidget {
  const SeeRayLensAdminApp({super.key});

  static final GoRouter _router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (context, state) => '/workspaces'),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/workspaces',
        builder: (context, state) =>
            const _Authenticated(child: WorkspacePage()),
      ),
      GoRoute(
        path: '/sites',
        builder: (context, state) => const _Authenticated(child: SitesPage()),
      ),
      GoRoute(
        path: '/sites/:siteId',
        builder: (context, state) => _Authenticated(
          child: SiteDetailPage(siteId: state.pathParameters['siteId']!),
        ),
      ),
      GoRoute(
        path: '/sites/:siteId/domains',
        builder: (context, state) => _Authenticated(
          child: DomainsPage(siteId: state.pathParameters['siteId']!),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const _Authenticated(child: TokenSettingsPage()),
      ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'SeeRay Lens',
    theme: AppTheme.light,
    routerConfig: _router,
  );
}

class _Authenticated extends ConsumerWidget {
  const _Authenticated({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(authProvider).phase;
    if (phase == AuthPhase.authenticated || phase == AuthPhase.refreshing) {
      return child;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
