import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_state.dart';
import 'core/i18n/app_i18n.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/analytics/presentation/analytics_dashboard_page.dart';
import 'features/analytics/presentation/analytics_detail_page.dart';
import 'features/analytics/presentation/heatmap_page.dart';
import 'features/analytics/presentation/site_tab_shell.dart';
import 'features/landing/presentation/landing_page.dart';
import 'features/integration/presentation/integration_page.dart';
import 'features/domains/presentation/domains_page.dart';
import 'features/sites/presentation/site_detail_page.dart';
import 'features/sites/presentation/sites_page.dart';
import 'features/tokens/presentation/token_settings_page.dart';
import 'features/workspaces/presentation/workspace_page.dart';

class SeeRayLensAdminApp extends ConsumerWidget {
  const SeeRayLensAdminApp({super.key});

  static final GoRouter _router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const LandingPage()),
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
      ShellRoute(
        builder: (context, state, child) =>
            SiteTabShell(state: state, child: child),
        routes: [
          GoRoute(
            path: '/sites/:siteId',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: SiteDetailPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/dashboard',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsDashboardPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/integration',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: IntegrationPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsDetailPage(
                  siteId: state.pathParameters['siteId']!,
                  view: AnalyticsView.visitors,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/acquisition',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsDetailPage(
                  siteId: state.pathParameters['siteId']!,
                  view: AnalyticsView.acquisition,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/behaviour',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsDetailPage(
                  siteId: state.pathParameters['siteId']!,
                  view: AnalyticsView.behaviour,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/behaviour/heatmaps',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: HeatmapPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/goals',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsDetailPage(
                  siteId: state.pathParameters['siteId']!,
                  view: AnalyticsView.goals,
                  embedded: true,
                ),
              ),
            ),
          ),
        ],
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
    locale: ref.watch(localeProvider),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: _router,
  );
}

Page<void> _siteTabPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (context, animation, secondaryAnimation, page) {
        final direction = state.extra is int && (state.extra! as int) < 0
            ? -1.0
            : 1.0;
        return SlideTransition(
          position: Tween<Offset>(begin: Offset(direction, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: page,
        );
      },
    );

class _Authenticated extends ConsumerWidget {
  const _Authenticated({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(authProvider).phase;
    if (phase == AuthPhase.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (phase == AuthPhase.authenticated || phase == AuthPhase.refreshing) {
      return child;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
