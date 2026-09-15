import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../sites/application/site_controller.dart';

class IntegrationPage extends ConsumerWidget {
  const IntegrationPage({
    required this.siteId,
    this.embedded = false,
    super.key,
  });
  final String siteId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = (ref.watch(sitesProvider).value ?? const <Site>[])
        .where((item) => item.id == siteId)
        .firstOrNull;
    if (site == null) {
      return Scaffold(
        appBar: AppBar(leading: AppBackButton(fallback: '/sites/$siteId')),
        body: Center(child: Text(context.tr('Site not found', '未找到站点'))),
      );
    }
    final base = ref.read(apiProvider).baseUrl;
    final script = '$base/tracker.js';
    final gif = '$base/api/v1/pixel/${site.trackingId}.gif';
    final svg = '$base/api/v1/pixel/${site.trackingId}.svg';
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: embedded
            ? null
            : SiteTopBar(
                siteId: siteId,
                selected: SiteTopTab.integration,
                help: PageHelpButton(
                  englishTitle: 'Tracking integration',
                  chineseTitle: '追踪集成说明',
                  englishBody:
                      'Use one JavaScript snippet per page. Repeated snippets for the same site are de-duplicated by the tracker. The no-JavaScript image fallback belongs inside noscript, so it never runs alongside JavaScript tracking.',
                  chineseBody:
                      '每个页面只需放置一段 JavaScript 代码。同一站点的重复嵌入会由追踪器去重。无 JavaScript 的图片回退代码必须放在 noscript 中，因此不会与 JavaScript 追踪同时执行。',
                ),
              ),
        body: Column(
          children: [
            Material(
              child: TabBar(
                tabs: [
                  Tab(text: context.tr('JavaScript', 'JavaScript')),
                  Tab(text: context.tr('Image fallback', '图片回退')),
                  Tab(text: context.tr('SVG fallback', 'SVG 回退')),
                  Tab(text: context.tr('Goals', '目标事件')),
                  Tab(text: context.tr('Heatmaps', '行为热图')),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _Snippet(
                    title: context.tr(
                      'Recommended JavaScript snippet',
                      '推荐的 JavaScript 代码',
                    ),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}"></script>',
                    note: context.tr(
                      'The tracker URL and collector path stay fixed. Do not add generated query parameters; site identity is the stable data-site-id value.',
                      '追踪器 URL 和 Collector 路径保持固定。不要添加自动生成的查询参数；站点身份使用稳定的 data-site-id。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'No-JavaScript GIF fallback',
                      '无 JavaScript 的 GIF 回退',
                    ),
                    body:
                        '<noscript>\n  <img src="$gif" width="1" height="1" alt="" referrerpolicy="strict-origin-when-cross-origin">\n</noscript>',
                    note: context.tr(
                      'Use exactly one fallback format and keep it inside noscript. The pixel URL is stable and derives the page from Referer.',
                      '仅使用一种回退格式，并保持在 noscript 内。像素 URL 固定，页面地址从 Referer 获取。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'No-JavaScript SVG fallback',
                      '无 JavaScript 的 SVG 回退',
                    ),
                    body:
                        '<noscript>\n  <img src="$svg" width="1" height="1" alt="" referrerpolicy="strict-origin-when-cross-origin">\n</noscript>',
                    note: context.tr(
                      'SVG has the same collection behavior as GIF. Do not include both formats on one page.',
                      'SVG 与 GIF 的采集行为相同。请勿在同一页面同时包含两种格式。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr('Record a conversion goal', '记录转化目标'),
                    body:
                        "<script>\n  SeeRay.trackGoal('signup_completed', {\n    category: 'conversion',\n    action: 'submit'\n  });\n</script>",
                    note: context.tr(
                      'Call this only after the conversion succeeds. Goal name, category and action are event fields, not URL parameters, so changing your site configuration never creates mixed tracking URLs.',
                      '仅在转化成功后调用。目标名称、分类和动作属于事件字段，而非 URL 参数，因此修改站点配置不会产生混用的追踪 URL。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr('Enable behaviour heatmaps', '启用页面行为热图'),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}" data-heatmap></script>\n<script>\n  // Before replacing PJAX content:\n  SeeRay.beginNavigation();\n  // After content and scroll restoration complete:\n  SeeRay.pageReady({ layoutVersion: \'homepage-v2\' });\n</script>',
                    note: context.tr(
                      'First enable Heatmaps in the site settings, then add data-heatmap. Heatmaps are sampled per page instance and remain off if the public configuration cannot be read. Use a new layoutVersion whenever same-sized content moves; register independent scroll containers with a stable ID.',
                      '请先在站点设置中开启热图，再添加 data-heatmap。热图按页面实例采样；公开配置读取失败时保持关闭。相同尺寸的内容位置变化时请更新 layoutVersion；独立滚动容器需使用稳定 ID 注册。',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({required this.title, required this.body, required this.note});
  final String title;
  final String body;
  final String note;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(note),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            body,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: body));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('Code copied', '代码已复制'))),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(context.tr('Copy code', '复制代码')),
        ),
      ),
    ],
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
