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
import 'features/analytics/presentation/recordings_page.dart';
import 'features/analytics/presentation/custom_dimensions_page.dart';
import 'features/analytics/presentation/segments_page.dart';
import 'features/analytics/presentation/technology_page.dart';
import 'features/analytics/presentation/visit_time_page.dart';
import 'features/analytics/presentation/visitor_interest_page.dart';
import 'features/analytics/presentation/locations_page.dart';
import 'features/analytics/presentation/cohorts_page.dart';
import 'features/analytics/presentation/realtime_page.dart';
import 'features/analytics/presentation/site_audit_log_page.dart';
import 'features/analytics/presentation/scheduled_reports_page.dart';
import 'features/analytics/presentation/analytics_alerts_page.dart';
import 'features/analytics/presentation/attribution_page.dart';
import 'features/analytics/presentation/analytics_annotations_page.dart';
import 'features/analytics/presentation/visitor_profile_page.dart';
import 'features/analytics/presentation/form_analytics_page.dart';
import 'features/analytics/presentation/media_analytics_page.dart';
import 'features/analytics/presentation/crash_analytics_page.dart';
import 'features/landing/presentation/landing_page.dart';
import 'features/integration/presentation/integration_page.dart';
import 'features/domains/presentation/domains_page.dart';
import 'features/sites/presentation/site_detail_page.dart';
import 'features/sites/presentation/sites_page.dart';
import 'features/tokens/presentation/token_settings_page.dart';
import 'features/workspaces/presentation/workspace_page.dart';
import 'features/workspaces/presentation/workspace_members_page.dart';
import 'features/workspaces/presentation/workspace_rollup_page.dart';

class SeeRayLensAdminApp extends ConsumerStatefulWidget {
  const SeeRayLensAdminApp({super.key});

  @override
  ConsumerState<SeeRayLensAdminApp> createState() => _SeeRayLensAdminAppState();

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
      GoRoute(
        path: '/workspaces/:workspaceId/rollup',
        builder: (context, state) => _Authenticated(
          child: WorkspaceRollupPage(
            workspaceId: state.pathParameters['workspaceId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/workspaces/:workspaceId/members',
        builder: (context, state) => _Authenticated(
          child: WorkspaceMembersPage(
            workspaceId: state.pathParameters['workspaceId']!,
          ),
        ),
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
            path: '/sites/:siteId/realtime',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: RealtimePage(
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
            path: '/sites/:siteId/visitors/engagement',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: VisitorInterestPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors/time',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: VisitTimePage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors/cohorts',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: CohortsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors/technology',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: TechnologyPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors/locations',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: LocationsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/visitors/:visitorId',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: VisitorProfilePage(
                  siteId: state.pathParameters['siteId']!,
                  visitorId: state.pathParameters['visitorId']!,
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
            path: '/sites/:siteId/acquisition/attribution',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AttributionPage(
                  siteId: state.pathParameters['siteId']!,
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
            path: '/sites/:siteId/behaviour/recordings',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: RecordingsPage(siteId: state.pathParameters['siteId']!),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/behaviour/forms',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: FormAnalyticsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/behaviour/media',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: MediaAnalyticsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/behaviour/crashes',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: CrashAnalyticsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/dimensions',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: CustomDimensionsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/segments',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: SegmentsPage(
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
          GoRoute(
            path: '/sites/:siteId/audit-log',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: SiteAuditLogPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/scheduled-reports',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: ScheduledReportsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/alerts',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsAlertsPage(
                  siteId: state.pathParameters['siteId']!,
                  embedded: true,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sites/:siteId/annotations',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: AnalyticsAnnotationsPage(
                  siteId: state.pathParameters['siteId']!,
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
}

class _SeeRayLensAdminAppState extends ConsumerState<SeeRayLensAdminApp> {
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'SeeRay Lens',
    theme: AppTheme.light,
    locale: ref.watch(localeProvider),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: SeeRayLensAdminApp._router,
  );
}

/*
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
            path: '/sites/:siteId/visitors/:visitorId',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: VisitorProfilePage(
                  siteId: state.pathParameters['siteId']!,
                  visitorId: state.pathParameters['visitorId']!,
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
            path: '/sites/:siteId/behaviour/recordings',
            pageBuilder: (context, state) => _siteTabPage(
              state,
              _Authenticated(
                child: RecordingsPage(siteId: state.pathParameters['siteId']!),
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

*/

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
