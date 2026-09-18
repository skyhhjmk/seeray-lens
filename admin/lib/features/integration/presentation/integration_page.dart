import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../../shared/presentation/app_back_button.dart';
import '../../../shared/presentation/page_help_button.dart';
import '../../../shared/presentation/site_top_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../sites/application/site_controller.dart';
import 'product_features_page.dart';

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
    final consentAttribute = site.requireConsent
        ? ' data-require-consent="true"'
        : '';
    final gif = '$base/api/v1/pixel/${site.trackingId}.gif';
    final svg = '$base/api/v1/pixel/${site.trackingId}.svg';
    final initialTab =
        GoRouter.maybeOf(context)?.state.uri.queryParameters['tab'] ==
            'web-vitals'
        ? 6
        : GoRouter.maybeOf(context)?.state.uri.queryParameters['tab'] == 'forms'
        ? 12
        : GoRouter.maybeOf(context)?.state.uri.queryParameters['tab'] == 'media'
        ? 13
        : 0;
    return DefaultTabController(
      length: 14,
      initialIndex: initialTab,
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
                isScrollable: true,
                tabs: [
                  Tab(text: context.tr('JavaScript', 'JavaScript')),
                  Tab(text: context.tr('Image fallback', '图片回退')),
                  Tab(text: context.tr('SVG fallback', 'SVG 回退')),
                  Tab(text: context.tr('Goals', '目标事件')),
                  Tab(text: context.tr('Site search', '站内搜索')),
                  Tab(text: context.tr('Content analytics', '内容分析')),
                  Tab(text: context.tr('Web Vitals', 'Web Vitals')),
                  Tab(text: context.tr('Heatmaps', '行为热图')),
                  Tab(text: context.tr('Funnels', '漏斗')),
                  Tab(text: context.tr('A/B tests', 'A/B 测试')),
                  Tab(text: context.tr('Tag Manager', 'Tag Manager')),
                  Tab(text: context.tr('Consent & privacy', '同意与隐私')),
                  Tab(text: context.tr('Form analytics', '表单分析')),
                  Tab(text: context.tr('Media analytics', '媒体分析')),
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
                        '<script src="$script" data-site-id="${site.trackingId}"$consentAttribute></script>',
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
                    body: site.requireConsent
                        ? '<!-- Pixel fallback is disabled: required consent needs the JavaScript choice UI. -->'
                        : '<noscript>\n  <img src="$gif" width="1" height="1" alt="" referrerpolicy="strict-origin-when-cross-origin">\n</noscript>',
                    note: context.tr(
                      site.requireConsent
                          ? 'A no-JavaScript pixel cannot collect an informed visitor choice, so it is disabled for this site.'
                          : 'Use exactly one fallback format and keep it inside noscript. The pixel URL is stable and derives the page from Referer.',
                      site.requireConsent
                          ? '无 JavaScript 图片无法呈现并取得访客选择，因此此站点禁用该回退。'
                          : '仅使用一种回退格式，并保持在 noscript 内。像素 URL 固定，页面地址从 Referer 获取。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'No-JavaScript SVG fallback',
                      '无 JavaScript 的 SVG 回退',
                    ),
                    body: site.requireConsent
                        ? '<!-- Pixel fallback is disabled: required consent needs the JavaScript choice UI. -->'
                        : '<noscript>\n  <img src="$svg" width="1" height="1" alt="" referrerpolicy="strict-origin-when-cross-origin">\n</noscript>',
                    note: context.tr(
                      site.requireConsent
                          ? 'A no-JavaScript pixel cannot collect an informed visitor choice, so it is disabled for this site.'
                          : 'SVG has the same collection behavior as GIF. Do not include both formats on one page.',
                      site.requireConsent
                          ? '无 JavaScript 图片无法呈现并取得访客选择，因此此站点禁用该回退。'
                          : 'SVG 与 GIF 的采集行为相同。请勿在同一页面同时包含两种格式。',
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
                    title: context.tr(
                      'Record a completed site search',
                      '记录完成的站内搜索',
                    ),
                    body:
                        "SeeRay.trackSiteSearch(searchInput.value, {\n  category: 'catalog',\n  resultsCount: results.total\n});",
                    note: context.tr(
                      'Call after the search result count is known. For a standard HTML form, the simpler alternative is to add data-seeray-search and optionally data-seeray-search-category="catalog" to the form; the tracker captures only its submitted search field. Do not use both methods for the same search. Search terms are explicit data and can contain personal information, so exclude sensitive fields and values.',
                      '在搜索结果数已知后调用。普通 HTML 表单也可使用更简单的方式：在表单上添加 data-seeray-search，并可选添加 data-seeray-search-category="catalog"；追踪器只会在表单提交时读取其中的搜索字段。同一次搜索不要同时使用两种方式。搜索词是显式采集的数据，可能包含个人信息，请避免追踪敏感字段和值。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'Measure content impressions and interactions',
                      '追踪内容曝光与互动',
                    ),
                    body:
                        '<section data-seeray-content-name="home hero" data-seeray-content-piece="summer-campaign" data-seeray-content-target="/summer">\n  <a href="/summer" data-seeray-content-action="primary_cta">Shop the summer collection</a>\n</section>\n\n<!-- For dynamically inserted content, call after rendering: -->\nSeeRay.refreshContentTracking();',
                    note: context.tr(
                      'Mark only the content you want measured. A visible impression is recorded once when at least 10% of the marked element enters the viewport. Clicks are recorded only on controls marked data-seeray-content-action. The tracker reads these labels, never visible text or HTML; target query strings and fragments are stripped. Use trackContentImpression/trackContentInteraction when your app owns the rendering, but do not combine API calls with markup for the same event.',
                      '只标记希望统计的内容项。标记元素至少 10% 进入可视区域时记录一次曝光；只有带 data-seeray-content-action 的控件会记录点击。追踪器仅读取这些标签，不读取可见文本或 HTML；目标地址的查询参数和片段会被剥离。应用自行管理渲染时可调用 trackContentImpression/trackContentInteraction，但同一事件不要同时用 API 和 HTML 标记重复采集。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'Measure Core Web Vitals',
                      '测量 Core Web Vitals',
                    ),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}"$consentAttribute data-web-vitals></script>',
                    note: context.tr(
                      'This opt-in collects only LCP, INP and CLS values for the current page; it does not read page text, DOM elements or form input. Final values are sent when available, including when the page is hidden. Measurements follow the tracker’s DNT and consent settings. Browsers without a supported measurement API may not report every metric.',
                      '此功能需显式启用，只采集当前页面的 LCP、INP 和 CLS 数值，不读取页面文本、DOM 元素或表单输入。数值在可用时发送，包括页面隐藏时；并遵循追踪器的 DNT 与同意设置。不支持相关测量 API 的浏览器可能无法报告所有指标。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr('Enable behaviour heatmaps', '启用页面行为热图'),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}"$consentAttribute data-heatmap></script>\n<script>\n  // Before replacing PJAX content:\n  SeeRay.beginNavigation();\n  // After content and scroll restoration complete:\n  SeeRay.pageReady({ layoutVersion: \'homepage-v2\' });\n</script>',
                    note: context.tr(
                      'First enable Heatmaps in the site settings, then add data-heatmap. Heatmaps are sampled per page instance and remain off if the public configuration cannot be read. Use a new layoutVersion whenever same-sized content moves; register independent scroll containers with a stable ID.',
                      '请先在站点设置中开启热图，再添加 data-heatmap。热图按页面实例采样；公开配置读取失败时保持关闭。相同尺寸的内容位置变化时请更新 layoutVersion；独立滚动容器需使用稳定 ID 注册。',
                    ),
                  ),
                  ProductFeaturesPage(
                    siteId: siteId,
                    trackingId: site.trackingId,
                    trackerUrl: script,
                    requireConsent: site.requireConsent,
                    mode: ProductFeatureMode.funnels,
                  ),
                  ProductFeaturesPage(
                    siteId: siteId,
                    trackingId: site.trackingId,
                    trackerUrl: script,
                    requireConsent: site.requireConsent,
                    mode: ProductFeatureMode.experiments,
                  ),
                  ProductFeaturesPage(
                    siteId: siteId,
                    trackingId: site.trackingId,
                    trackerUrl: script,
                    requireConsent: site.requireConsent,
                    mode: ProductFeatureMode.tagManager,
                  ),
                  _ConsentSetup(
                    siteId: site.id,
                    trackingId: site.trackingId,
                    trackerUrl: script,
                    requiredBySite: site.requireConsent,
                  ),
                  _Snippet(
                    title: context.tr(
                      'Measure explicit form interactions',
                      '追踪明确标记的表单互动',
                    ),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}"$consentAttribute data-track-forms></script>\n\n<form data-seeray-form="signup">\n  <input type="email" autocomplete="email">\n  <button type="submit">Continue</button>\n</form>\n\n<script>\n  // Call inside your async submit handler after the server responds:\n  SeeRay.trackFormResult(\'signup\', success);\n</script>',
                    note: context.tr(
                      'This is opt-in twice: enable data-track-forms on the tracker and add a stable, non-personal data-seeray-form ID to each form. The tracker records visible form views, starts, generic field categories, time, native validation errors and submit attempts. It never reads field names, values, labels, error text or DOM content; password, hidden and file inputs are excluded. Native submit is not backend success: call trackFormResult only after your application knows the result. Mark sensitive forms with data-seeray-no-track, and call SeeRay.refreshFormTracking() after dynamically adding forms.',
                      '此功能需要两处显式启用：追踪代码添加 data-track-forms，每个表单添加稳定且不含个人信息的 data-seeray-form ID。追踪器记录可见表单、开始填写、通用字段类别、耗时、浏览器原生校验错误和提交尝试；不会读取字段名、值、标签、错误文本或 DOM 内容，并排除密码、隐藏和文件字段。原生提交不代表服务端成功：应用确认处理结果后再调用 trackFormResult。敏感表单请加 data-seeray-no-track；动态添加表单后调用 SeeRay.refreshFormTracking()。',
                    ),
                  ),
                  _Snippet(
                    title: context.tr(
                      'Measure explicit audio/video playback',
                      '追踪明确标记的音视频播放',
                    ),
                    body:
                        '<script src="$script" data-site-id="${site.trackingId}"$consentAttribute data-track-media></script>\n\n<video data-seeray-media="product-demo" controls>\n  <source src="/media/product-demo.mp4" type="video/mp4">\n</video>',
                    note: context.tr(
                      'This is opt-in twice: enable data-track-media and add a stable, non-personal data-seeray-media ID to each audio/video element. The tracker records one start, 25/50/75/90% playback milestones and natural ended completion per page visit. It does not read or send media source URLs, titles, captions, poster URLs or media content. Seeking directly to a milestone counts as reached playback progress, but seeking to the end is not reported as a completion. Mark sensitive embeds with data-seeray-no-track. For cross-origin media, the owning page must receive the standard HTML media events.',
                      '此功能需要两处显式启用：追踪代码添加 data-track-media，每个 audio/video 元素添加稳定且不含个人信息的 data-seeray-media ID。每次页面访问记录一次开始播放、25/50/75/90% 进度节点和自然 ended 完成事件；不会读取或发送媒体源地址、标题、字幕、封面地址或媒体内容。拖动到进度节点会计为到达该节点，但直接拖到结尾不会计为完成。敏感嵌入请加 data-seeray-no-track。跨域媒体需由所属页面正常接收到 HTML 媒体事件。',
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

class _ConsentSetup extends StatelessWidget {
  const _ConsentSetup({
    required this.siteId,
    required this.trackingId,
    required this.trackerUrl,
    required this.requiredBySite,
  });

  final String siteId;
  final String trackingId;
  final String trackerUrl;
  final bool requiredBySite;

  String get _snippet =>
      '''<script src="$trackerUrl" data-site-id="$trackingId" data-require-consent="true"></script>
<aside id="seeray-consent-banner-$trackingId" role="dialog" aria-label="Privacy choices" hidden>
  <p>Allow anonymous analytics and the site's enabled behaviour tools?</p>
  <button type="button" data-seeray-consent-accept>Accept</button>
  <button type="button" data-seeray-consent-reject>Reject</button>
</aside>
<button id="seeray-consent-manage-$trackingId" type="button">Privacy settings</button>
<script>
(() => {
  const banner = document.getElementById('seeray-consent-banner-$trackingId');
  const manage = document.getElementById('seeray-consent-manage-$trackingId');
  if (!banner || !manage || !window.SeeRay) return;
  if (SeeRay.getConsentState('$trackingId') === 'unknown') banner.hidden = false;
  manage.addEventListener('click', () => { banner.hidden = false; });
  banner.querySelector('[data-seeray-consent-accept]')?.addEventListener('click', () => {
    SeeRay.setConsent(true, '$trackingId');
    banner.hidden = true;
  });
  banner.querySelector('[data-seeray-consent-reject]')?.addEventListener('click', () => {
    SeeRay.optOut('$trackingId');
    banner.hidden = true;
  });
})();
</script>''';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        context.tr('Visitor consent setup', '访客同意设置'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: Icon(
            requiredBySite ? Icons.verified_user_outlined : Icons.info_outline,
          ),
          title: Text(
            requiredBySite
                ? context.tr('Consent required for this site', '此站点需要访客同意')
                : context.tr('Consent is currently optional', '当前未强制要求访客同意'),
          ),
          subtitle: Text(
            requiredBySite
                ? context.tr(
                    'Newly generated tracker snippets wait for a visitor choice; replace snippets already installed on the site. Reject and later withdrawal stop collection and clear this site’s stored tracker identifiers.',
                    '新生成的追踪代码会等待访客选择；请替换网站上已安装的旧代码。拒绝或之后撤回会停止采集并清除此站点保存的追踪标识。',
                  )
                : context.tr(
                    'This starter snippet enables consent for its installation. Turn on the site policy to include the requirement in every generated feature snippet.',
                    '此示例代码会为该安装启用同意控制。开启站点策略后，所有生成的功能代码都会带上同意要求。',
                  ),
          ),
          trailing: IconButton(
            tooltip: context.tr('Open site settings', '打开站点设置'),
            onPressed: () => context.go('/sites/$siteId'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'Copy this complete starter snippet into your page. It includes an accessible accept/reject prompt and a persistent privacy-settings control. Adapt its copy and styling to your privacy notice and legal requirements.',
          '将这段完整示例放入页面即可获得可访问的接受/拒绝提示和常驻隐私设置入口。请根据自己的隐私声明及法律要求调整文案与样式。',
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _snippet,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _snippet));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('Code copied', '代码已复制'))),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(context.tr('Copy consent setup', '复制同意设置代码')),
        ),
      ),
    ],
  );
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
