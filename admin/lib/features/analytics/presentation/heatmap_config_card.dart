import 'package:flutter/material.dart';

import '../../../core/i18n/app_i18n.dart';

class ConfigCard extends StatelessWidget {
  const ConfigCard({
    required this.config,
    required this.onEnabled,
    required this.onRate,
    super.key,
  });
  final Map<String, dynamic> config;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<int> onRate;
  @override
  Widget build(BuildContext context) {
    final rate = (config['sampleRate'] as num?)?.toDouble() ?? 10;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: config['enabled'] == true,
              onChanged: onEnabled,
              title: Text(context.tr('Collect heatmaps', '采集行为热图')),
              subtitle: Text(
                context.tr(
                  'Disabled by default. Turning it off stops future collection without affecting ordinary analytics.',
                  '默认关闭。关闭后仅停止后续热图采集，不影响普通分析。',
                ),
              ),
            ),
            Text(
              context.tr(
                'Page-instance sampling: ${rate.round()}%',
                '页面实例采样率：${rate.round()}%',
              ),
            ),
            Slider(
              value: rate,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${rate.round()}%',
              onChanged: (value) => onRate(value.round()),
            ),
          ],
        ),
      ),
    );
  }
}
