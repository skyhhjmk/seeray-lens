import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: Container(
        width: 156,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: Colors.white,
        child: Image.asset(
          'assets/seeray-lens-logo.png',
          fit: BoxFit.contain,
        ),
      ),
      actions: [
        const LanguageMenu(),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: FilledButton.tonal(
            onPressed: () => context.go('/login'),
            child: Text(context.tr('Sign in', '登录管理台')),
          ),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 36),
            Text(
              context.tr(
                'Privacy-first analytics you can understand.',
                '看得懂、可掌控的隐私优先网站分析。',
              ),
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr(
                'SeeRay Lens gives your team accurate visitors, sessions, pages and traffic insights without turning your audience into an advertising profile.',
                'SeeRay Lens 为团队提供准确的访客、会话、页面和流量洞察，而不把你的受众变成广告画像。',
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.dashboard_outlined),
                  label: Text(context.tr('Open admin', '进入管理台')),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.login),
                  label: Text(context.tr('Sign in', '登录')),
                ),
              ],
            ),
            const SizedBox(height: 54),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                _Feature(
                  icon: Icons.visibility_outlined,
                  title: context.tr('Clear metrics', '清晰指标'),
                  body: context.tr(
                    'Exact visitors, sessions, bounce rate and page views in each site time zone.',
                    '按站点时区统计精确访客、会话、跳出率和页面浏览量。',
                  ),
                ),
                _Feature(
                  icon: Icons.lock_outline,
                  title: context.tr('Privacy by design', '隐私优先'),
                  body: context.tr(
                    'A lightweight tracker and self-hosted data path keep control with your team.',
                    '轻量追踪器与自托管数据链路，让数据控制权留在团队手中。',
                  ),
                ),
                _Feature(
                  icon: Icons.layers_outlined,
                  title: context.tr('Built for teams', '为团队而建'),
                  body: context.tr(
                    'Workspaces, sites, domains and API tokens are managed from one control plane.',
                    '在同一控制台管理工作区、站点、域名和 API 令牌。',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    ),
  );
}
