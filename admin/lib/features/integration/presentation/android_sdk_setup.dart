import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_i18n.dart';

class AndroidSdkSetup extends StatelessWidget {
  const AndroidSdkSetup({
    required this.trackingId,
    required this.apiOrigin,
    required this.requireConsent,
    super.key,
  });

  static const _version = '0.1.0';

  final String trackingId;
  final String apiOrigin;
  final bool requireConsent;

  String get _dependency =>
      'implementation("io.seeray.lens:seeray-analytics-android:$_version")';

  String get _initialization =>
      '''import io.seeray.lens.android.SeeRayAnalytics
import io.seeray.lens.android.SeeRayAnalyticsOptions

val analytics = SeeRayAnalytics(
    context = applicationContext,
    options = SeeRayAnalyticsOptions(
        siteId = "$trackingId",
        apiOrigin = "$apiOrigin",
        requireConsent = $requireConsent,
    ),
)''';

  String get _consent =>
      'analytics.setConsent(granted = visitorAcceptedAnalytics)';

  int get _choiceStep => _apiUsesHttps ? 4 : 3;
  int get _trackingStep => _apiUsesHttps ? 5 : 4;

  String get _tracking => '''analytics.trackScreen(
    screenName = "pricing",
    url = "https://www.example.com/mobile/pricing",
)

analytics.trackEvent(
    eventType = "signup",
    url = "https://www.example.com/mobile/signup",
    category = "account",
    action = "completed",
)

analytics.trackGoal(
    name = "signup_completed",
    url = "https://www.example.com/mobile/complete",
)''';

  bool get _apiUsesHttps => Uri.tryParse(apiOrigin)?.scheme == 'https';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        context.tr('Connect an Android app', '接入 Android 应用'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        context.tr(
          'This guide is prefilled for the selected site. Android app events use the same reports and goals as web events; the SDK never reads advertising IDs or device models.',
          '以下步骤已填入当前站点信息。Android 应用事件与网页事件进入相同报表和目标；SDK 不读取广告 ID 或设备型号。',
        ),
      ),
      const SizedBox(height: 16),
      _AvailabilityCard(version: _version),
      const SizedBox(height: 12),
      _SetupStep(
        number: 1,
        title: context.tr(
          'Build the SDK from this source checkout',
          '从当前源码构建 SDK',
        ),
        description: context.tr(
          'The Android artifact is currently available through a local Maven publish; it is not yet distributed from a public Maven repository.',
          '当前 Android 包通过本地 Maven 仓库发布；尚未托管到公共 Maven 仓库。',
        ),
        code:
            './gradlew -p sdk/android test assembleRelease\n'
            './gradlew -p sdk/android publishReleasePublicationToMavenLocal',
        copyLabel: context.tr('Copy build commands', '复制构建命令'),
      ),
      const SizedBox(height: 12),
      _SetupStep(
        number: 2,
        title: context.tr('Add the local dependency', '添加本地依赖'),
        description: context.tr(
          'In the consuming Android application, add mavenLocal() to its repository list and the SDK dependency to the app module.',
          '在接入 SDK 的 Android 应用中，将 mavenLocal() 加入仓库列表，并在 app 模块添加 SDK 依赖。',
        ),
        code:
            'repositories {\n    mavenLocal()\n}\n\n'
            'dependencies {\n    $_dependency\n}',
        copyLabel: context.tr('Copy Gradle setup', '复制 Gradle 配置'),
      ),
      const SizedBox(height: 12),
      if (!_apiUsesHttps) ...[
        _HttpsWarning(apiOrigin: apiOrigin),
        const SizedBox(height: 12),
      ] else
        _SetupStep(
          number: 3,
          title: context.tr('Initialize this site', '初始化当前站点'),
          description: context.tr(
            'Create one SDK instance with the application context and keep it for the app process.',
            '使用 Application Context 创建一个 SDK 实例，并在应用进程中复用。',
          ),
          code: _initialization,
          copyLabel: context.tr('Copy initialization code', '复制初始化代码'),
        ),
      const SizedBox(height: 12),
      if (requireConsent)
        _SetupStep(
          number: _choiceStep,
          title: context.tr('Apply the visitor choice', '遵守访客选择'),
          description: context.tr(
            'This site requires consent. Call this only after your app has presented and received its privacy choice; tracking stays disabled before acceptance.',
            '此站点要求先取得同意。应用呈现隐私选项并收到访客选择后再调用；接受前 SDK 不会追踪。',
          ),
          code: _consent,
          copyLabel: context.tr('Copy consent call', '复制同意调用'),
        )
      else
        _SetupStep(
          number: _choiceStep,
          title: context.tr('Honor in-app privacy choices', '遵守应用内隐私选择'),
          description: context.tr(
            'The site does not require consent before collection. If your app presents an analytics choice, apply it here and honor withdrawal immediately.',
            '此站点未要求采集前必须取得同意。如果应用提供分析数据选项，请在这里应用访客选择，并立即遵守撤回。',
          ),
          code: _consent,
          copyLabel: context.tr('Copy consent call', '复制同意调用'),
        ),
      const SizedBox(height: 12),
      _SetupStep(
        number: _trackingStep,
        title: context.tr('Track screens and conversions', '追踪屏幕与转化'),
        description: context.tr(
          'Supply canonical HTTPS URLs on this site’s allowed-domain list. Query strings and fragments are stripped before collection.',
          '请提供已加入站点域名白名单的规范 HTTPS 地址；查询参数和片段会在采集前移除。',
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
              'Never put personal data in screen names, URLs, event properties, or goal names. Close the SDK with analytics.close() when the app process is shutting down.',
              '屏幕名称、URL、事件属性和目标名称中不要放个人信息。应用进程结束时调用 analytics.close()。',
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => _showDocumentation(context),
        icon: const Icon(Icons.menu_book_outlined),
        label: Text(
          context.tr('SDK behavior and privacy details', '查看 SDK 行为与隐私说明'),
        ),
      ),
    ],
  );

  void _showDocumentation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Android SDK details', 'Android SDK 说明')),
        content: SingleChildScrollView(
          child: Text(
            context.tr(
              'The SDK uses bounded batches, rotates site-scoped sessions after inactivity, retries only while the app process remains alive, and stores no advertising identifiers. Review docs/analytics/android-sdk.md before release; local Maven publishing is not a public artifact release.',
              'SDK 使用有界批次，空闲后轮换站点范围的会话，并仅在应用进程存活期间重试；不会保存广告标识符。发布前请阅读 docs/analytics/android-sdk.md；发布到本地 Maven 不等于对外发布 SDK 包。',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Close', '关闭')),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(
        context.tr('Source build only · v$version', '仅源码构建 · v$version'),
      ),
      subtitle: Text(
        context.tr(
          'This is suitable for self-hosted/source deployments. Publish a signed artifact to a public or organization Maven repository before offering one-step installation to external customers.',
          '适用于自托管或源码部署。向外部客户提供一键安装前，需要将签名包发布到公共或组织 Maven 仓库。',
        ),
      ),
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
      title: Text(
        context.tr('HTTPS required for Android', 'Android SDK 要求 HTTPS'),
      ),
      subtitle: Text(
        context.tr(
          'The configured analytics endpoint is $apiOrigin. The Android SDK rejects plaintext HTTP. Enable HTTPS before copying the generated initialization code.',
          '当前分析服务地址为 $apiOrigin。Android SDK 会拒绝明文 HTTP；启用 HTTPS 后再复制生成的初始化代码。',
        ),
      ),
    ),
  );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
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
