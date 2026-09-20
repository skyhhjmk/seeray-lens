import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_i18n.dart';

class FlutterSdkSetup extends StatelessWidget {
  const FlutterSdkSetup({
    required this.trackingId,
    required this.apiOrigin,
    required this.requireConsent,
    super.key,
  });

  static const _repository = 'https://github.com/skyhhjmk/seeray-lens.git';
  static const _version = '0.1.0';
  final String trackingId;
  final String apiOrigin;
  final bool requireConsent;

  bool get _apiUsesHttps => Uri.tryParse(apiOrigin)?.scheme == 'https';

  String get _dependency => '''dependencies:
  seeray_analytics_flutter:
    git:
      url: $_repository
      path: sdk/flutter
      ref: master''';

  String get _initialization => '''import 'package:seeray_analytics_flutter/seeray_analytics_flutter.dart';

final analytics = await SeeRayAnalytics.create(
  const SeeRayAnalyticsOptions(
    siteId: '$trackingId',
    apiOrigin: '$apiOrigin',
    requireConsent: $requireConsent,
  ),
);''';

  String get _tracking => '''analytics.trackScreen(
  name: 'pricing',
  url: 'https://www.example.com/mobile/pricing',
);

analytics.trackEvent(
  type: 'signup',
  url: 'https://www.example.com/mobile/signup',
  category: 'account',
  action: 'completed',
  properties: {'plan': 'pro'},
);

analytics.trackGoal(
  name: 'signup_completed',
  url: 'https://www.example.com/mobile/complete',
);''';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(context.tr('Connect a Flutter app', '接入 Flutter 应用'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(context.tr(
        'The Flutter SDK supports Android, iOS, Web, Windows, macOS and Linux. It sends explicit screens, events and goals to the same reports as web analytics.',
        'Flutter SDK 支持 Android、iOS、Web、Windows、macOS 和 Linux，并将明确上报的页面、事件和目标写入与网页相同的报表。',
      )),
      const SizedBox(height: 16),
      _Notice(version: _version),
      const SizedBox(height: 12),
      _Step(
        number: 1,
        title: context.tr('Add the Git dependency', '添加 Git 依赖'),
        description: context.tr(
          'Add this site-independent dependency to your app pubspec. For reproducible production builds, replace master with a published Git tag.',
          '将此与站点无关的依赖加入应用 pubspec。正式环境需要可复现构建时，请将 master 替换为已发布的 Git tag。',
        ),
        code: _dependency,
        copyLabel: context.tr('Copy pubspec dependency', '复制 pubspec 依赖'),
      ),
      const SizedBox(height: 12),
      if (!_apiUsesHttps)
        _HttpsWarning(apiOrigin: apiOrigin)
      else
        _Step(
          number: 2,
          title: context.tr('Initialize this site', '初始化当前站点'),
          description: context.tr(
            'Create one client for the application process. The SDK rejects plaintext HTTP collectors.',
            '为应用进程创建一个客户端。SDK 会拒绝明文 HTTP Collector。',
          ),
          code: _initialization,
          copyLabel: context.tr('Copy initialization code', '复制初始化代码'),
        ),
      const SizedBox(height: 12),
      _Step(
        number: 3,
        title: context.tr('Apply the visitor choice', '遵守访客选择'),
        description: requireConsent
            ? context.tr(
                'This site requires consent. Invoke this only after your app presents and receives the visitor privacy choice.',
                '此站点要求先取得同意。仅在应用呈现并收到访客隐私选择后调用。',
              )
            : context.tr(
                'If the app presents an analytics choice, apply it here and honor withdrawal immediately.',
                '如果应用提供分析数据选项，请在这里应用访客选择并立即遵守撤回。',
              ),
        code: 'await analytics.setConsent(granted: visitorAcceptedAnalytics);',
        copyLabel: context.tr('Copy consent call', '复制同意调用'),
      ),
      const SizedBox(height: 12),
      _Step(
        number: 4,
        title: context.tr('Track explicit screens and conversions', '追踪明确页面与转化'),
        description: context.tr(
          'The SDK does not observe Navigator routes. Call these methods when a screen is visible or after a conversion succeeds, using canonical HTTPS URLs on an enabled site domain.',
          'SDK 不监听 Navigator 路由。请在页面实际展示或转化成功后调用，并使用已启用站点域名下的规范 HTTPS URL。',
        ),
        code: _tracking,
        copyLabel: context.tr('Copy tracking examples', '复制追踪示例'),
      ),
      const SizedBox(height: 12),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.tr(
          'The SDK uses bounded in-memory batches and retries only while the process is alive. Call flush() at an appropriate background boundary. It does not collect advertising IDs, device models, location, route names, UI content, heatmaps, recordings, or crash diagnostics.',
          'SDK 使用有界内存批次，仅在进程存活时重试。请在合适的后台切换点调用 flush()。它不采集广告 ID、设备型号、位置、路由名称、界面内容、热图、回放或崩溃诊断。',
        )),
      )),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(context.tr('Public source package · v$version', '公开源码包 · v$version')),
      subtitle: Text(context.tr(
        'The package currently resolves from this repository. Push source changes before consumers can use them; use a Git tag when one is available.',
        '当前包从此仓库解析。源码变更需要推送后使用方才能使用；有 Git tag 后请固定到对应版本。',
      )),
    ),
  );
}

class _HttpsWarning extends StatelessWidget {
  const _HttpsWarning({required this.apiOrigin});
  final String apiOrigin;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(context.tr('HTTPS required for Flutter', 'Flutter SDK 要求 HTTPS')),
      subtitle: Text(context.tr(
        'The configured analytics endpoint is $apiOrigin. Enable HTTPS before copying initialization code.',
        '当前分析服务地址为 $apiOrigin。启用 HTTPS 后再复制初始化代码。',
      )),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.description, required this.code, required this.copyLabel});
  final int number;
  final String title;
  final String description;
  final String code;
  final String copyLabel;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(radius: 14, child: Text('$number')), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium))]),
      const SizedBox(height: 8), Text(description), const SizedBox(height: 12),
      SelectableText(code, style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: code)), icon: const Icon(Icons.copy_outlined), label: Text(copyLabel)),
    ]),
  ));
}
