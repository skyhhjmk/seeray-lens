import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_i18n.dart';

class IosSdkSetup extends StatelessWidget {
  const IosSdkSetup({
    required this.trackingId,
    required this.apiOrigin,
    required this.requireConsent,
    super.key,
  });

  static const _repository = 'https://github.com/skyhhjmk/seeray-lens.git';

  final String trackingId;
  final String apiOrigin;
  final bool requireConsent;

  bool get _apiUsesHttps => Uri.tryParse(apiOrigin)?.scheme == 'https';
  int get _consentStep => 4;
  int get _trackingStep => 5;

  String get _packageSetup =>
      '''dependencies: [
    .package(url: "$_repository", branch: "master"),
],

targets: [
    .target(dependencies: [
        .product(name: "SeeRayAnalytics", package: "seeray-lens"),
    ]),
]''';

  String get _initialization =>
      '''import SeeRayAnalytics

let analytics = try SeeRayAnalytics(
    options: .init(
        siteId: "$trackingId",
        apiOrigin: "$apiOrigin",
        requireConsent: $requireConsent
    )
)''';

  String get _consent =>
      'await analytics.setConsent(granted: visitorAcceptedAnalytics)';

  String get _tracking => '''await analytics.trackScreen(
    name: "pricing",
    url: "https://www.example.com/mobile/pricing"
)

await analytics.trackEvent(
    type: "signup",
    url: "https://www.example.com/mobile/signup",
    category: "account",
    action: "completed",
    properties: ["plan": .string("pro")]
)

await analytics.trackGoal(
    name: "signup_completed",
    url: "https://www.example.com/mobile/complete"
)''';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        context.tr('Connect an iOS app', '接入 iOS 应用'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'This guide is prefilled for the selected site. The native SDK sends explicit screen, event, and goal actions into the same reports as web analytics; it does not infer navigation or read device models or advertising IDs.',
          '以下步骤已填入当前站点信息。原生 SDK 将明确上报的屏幕、事件和目标写入与网页相同的报表；它不会推断导航，也不读取设备型号或广告 ID。',
        ),
      ),
      const SizedBox(height: 16),
      const _PackageNotice(),
      const SizedBox(height: 12),
      _IosSetupStep(
        number: 1,
        title: context.tr(
          'Add the SeeRay Swift package',
          '添加 SeeRay Swift Package',
        ),
        description: context.tr(
          'In Xcode choose File → Add Package Dependencies, paste the repository URL below, and select the master branch. The repository must be reachable by the app developer.',
          '在 Xcode 中选择“File → Add Package Dependencies”，粘贴下面的仓库地址并选择 master 分支。应用开发者需要有权访问该仓库。',
        ),
        code: _repository,
        copyLabel: context.tr('Copy package URL', '复制 Package 地址'),
      ),
      const SizedBox(height: 12),
      _IosSetupStep(
        number: 2,
        title: context.tr('Declare the package in SwiftPM', '在 SwiftPM 中声明依赖'),
        description: context.tr(
          'For projects that manage dependencies in Package.swift, add this dependency and product to the app target.',
          '使用 Package.swift 管理依赖的项目，可将以下依赖和 product 添加到应用 target。',
        ),
        code: _packageSetup,
        copyLabel: context.tr('Copy SwiftPM setup', '复制 SwiftPM 配置'),
      ),
      const SizedBox(height: 12),
      if (!_apiUsesHttps) ...[
        _IosHttpsWarning(apiOrigin: apiOrigin),
        const SizedBox(height: 12),
      ] else
        _IosSetupStep(
          number: 3,
          title: context.tr('Initialize this site', '初始化当前站点'),
          description: context.tr(
            'Create one client and retain it for the app process. This code is generated only when the collector endpoint uses HTTPS.',
            '创建一个客户端并在应用进程中复用。仅当 Collector 使用 HTTPS 时才生成此初始化代码。',
          ),
          code: _initialization,
          copyLabel: context.tr('Copy initialization code', '复制初始化代码'),
        ),
      const SizedBox(height: 12),
      _IosSetupStep(
        number: _consentStep,
        title: context.tr('Apply the visitor choice', '遵守访客选择'),
        description: requireConsent
            ? context.tr(
                'This site requires consent. Call this from your app’s privacy-choice handler; collection and persistent IDs remain off until acceptance.',
                '此站点要求先取得同意。请从应用的隐私选择处理程序调用；接受前不会采集或保存持久 ID。',
              )
            : context.tr(
                'Collection is permitted by the current site policy. If your app offers a privacy choice, pass its result here and honor withdrawal immediately.',
                '当前站点策略允许采集。如果应用提供隐私选项，请将访客选择传入并立即遵守撤回。',
              ),
        code: _consent,
        copyLabel: context.tr('Copy consent call', '复制同意调用'),
      ),
      const SizedBox(height: 12),
      _IosSetupStep(
        number: _trackingStep,
        title: context.tr('Track screens and conversions', '追踪屏幕与转化'),
        description: context.tr(
          'Call these methods when the screen is visible and after the application confirms a conversion. Use canonical HTTPS URLs on this site’s allowed-domain list.',
          '在屏幕实际展示时调用屏幕追踪方法；应用确认转化成功后再记录目标。请使用加入站点域名白名单的规范 HTTPS URL。',
        ),
        code: _tracking,
        copyLabel: context.tr('Copy tracking examples', '复制追踪示例'),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.tr(
              'URLs have query strings and fragments removed. Do not put personal data in screen names, event properties, or goal names. Native crash collection and automatic navigation remain off.',
              'URL 查询参数和片段会被移除。屏幕名称、事件属性和目标名称中不要放个人信息。原生崩溃采集和自动导航追踪默认未启用。',
            ),
          ),
        ),
      ),
    ],
  );
}

class _PackageNotice extends StatelessWidget {
  const _PackageNotice();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(
        context.tr(
          'Public source package · master branch',
          '公开源码包 · master 分支',
        ),
      ),
      subtitle: Text(
        context.tr(
          'The repository is public and SwiftPM can consume it directly. This branch is not a versioned SDK release; use a tagged release for reproducible production builds when one is available. Changes must be pushed before consumers can resolve them.',
          '仓库公开，可由 SwiftPM 直接依赖；当前分支尚不是带版本号的 SDK 发布。正式环境应在有版本标签后固定到对应版本。代码提交到远端后，使用方才能解析到更新。',
        ),
      ),
    ),
  );
}

class _IosHttpsWarning extends StatelessWidget {
  const _IosHttpsWarning({required this.apiOrigin});
  final String apiOrigin;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(context.tr('HTTPS required for iOS', 'iOS SDK 要求 HTTPS')),
      subtitle: Text(
        context.tr(
          'The configured analytics endpoint is $apiOrigin. The native SDK rejects plaintext HTTP. Enable HTTPS before copying initialization code.',
          '当前分析服务地址为 $apiOrigin。原生 SDK 会拒绝明文 HTTP；启用 HTTPS 后再复制初始化代码。',
        ),
      ),
    ),
  );
}

class _IosSetupStep extends StatelessWidget {
  const _IosSetupStep({
    required this.number,
    required this.title,
    required this.description,
    required this.code,
    required this.copyLabel,
  });

  final int number;
  final String title;
  final String description;
  final String code;
  final String copyLabel;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 14, child: Text('$number')),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('Code copied', '已复制'))),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: Text(copyLabel),
            ),
          ),
        ],
      ),
    ),
  );
}
