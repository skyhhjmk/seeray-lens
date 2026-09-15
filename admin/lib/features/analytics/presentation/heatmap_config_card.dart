import 'package:flutter/material.dart';

import '../../../core/i18n/app_i18n.dart';

class ConfigCard extends StatelessWidget {
  const ConfigCard({
    required this.config,
    required this.onEnabled,
    required this.onRate,
    required this.onAutoSnapshot,
    required this.onRecording,
    required this.onRecordingRate,
    required this.onRecordingRetention,
    super.key,
  });
  final Map<String, dynamic> config;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<int> onRate;
  final ValueChanged<bool> onAutoSnapshot;
  final ValueChanged<bool> onRecording;
  final ValueChanged<int> onRecordingRate;
  final ValueChanged<int> onRecordingRetention;
  @override
  Widget build(BuildContext context) {
    final rate = (config['sampleRate'] as num?)?.toDouble() ?? 10;
    final recordingRate =
        (config['recordingSampleRate'] as num?)?.toDouble() ?? 1;
    final retention = (config['recordingRetentionDays'] as num?)?.toInt() ?? 14;
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
            SwitchListTile(
              value: config['autoSnapshotEnabled'] != false,
              onChanged: config['enabled'] == true ? onAutoSnapshot : null,
              title: Text(context.tr('Automatic DOM snapshots', '自动采集 DOM 快照')),
              subtitle: Text(
                context.tr(
                  'Capture a masked snapshot from a real visitor browser for matching heatmaps.',
                  '从真实访客浏览器采集脱敏页面快照，用作热图底图。',
                ),
              ),
            ),
            const Divider(),
            SwitchListTile(
              value: config['recordingEnabled'] == true,
              onChanged: onRecording,
              title: Text(context.tr('Session recordings', '会话回放')),
              subtitle: Text(
                context.tr(
                  'Disabled independently. Inputs are masked before events leave the browser.',
                  '独立开关。表单内容会在事件离开浏览器前完成遮罩。',
                ),
              ),
            ),
            Text(
              context.tr(
                'Recording sampling: ${recordingRate.round()}%',
                '回放采样率：${recordingRate.round()}%',
              ),
            ),
            Slider(
              value: recordingRate,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${recordingRate.round()}%',
              onChanged: config['recordingEnabled'] == true
                  ? (value) => onRecordingRate(value.round())
                  : null,
            ),
            Row(
              children: [
                Text(context.tr('Recording retention', '回放保留时间')),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: [7, 14, 30, 60, 90].contains(retention)
                      ? retention
                      : 14,
                  items: [7, 14, 30, 60, 90]
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text(context.tr('$days days', '$days 天')),
                        ),
                      )
                      .toList(),
                  onChanged: config['recordingEnabled'] == true
                      ? (value) {
                          if (value != null) onRecordingRetention(value);
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
