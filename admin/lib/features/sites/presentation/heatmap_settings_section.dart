import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_i18n.dart';
import '../../analytics/presentation/heatmap_config_card.dart';
import '../../auth/application/auth_controller.dart';

class HeatmapSettingsSection extends ConsumerStatefulWidget {
  const HeatmapSettingsSection({required this.siteId, super.key});
  final String siteId;

  @override
  ConsumerState<HeatmapSettingsSection> createState() =>
      _HeatmapSettingsSectionState();
}

class _HeatmapSettingsSectionState
    extends ConsumerState<HeatmapSettingsSection> {
  Map<String, dynamic>? _config;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'GET',
                    '/api/v1/sites/${widget.siteId}/heatmaps/config',
                  )
              as Map;
      if (mounted) {
        setState(() {
          _config = result.cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final current = _config;
    if (current == null) return;
    final body = {...current, ...patch};
    try {
      final result =
          await ref
                  .read(apiProvider)
                  .request(
                    'PUT',
                    '/api/v1/sites/${widget.siteId}/heatmaps/config',
                    body: body,
                  )
              as Map;
      if (mounted) setState(() => _config = result.cast<String, dynamic>());
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        Text(
          context.tr('Behaviour capture', '行为采集设置'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (_error != null) Text('$_error'),
        if (config == null && _error == null)
          const Center(child: CircularProgressIndicator())
        else if (config != null)
          ConfigCard(
            config: config,
            onEnabled: (value) => _save({'enabled': value}),
            onRate: (value) => _save({'sampleRate': value}),
            onAutoSnapshot: (value) => _save({'autoSnapshotEnabled': value}),
            onRecording: (value) => _save({'recordingEnabled': value}),
            onRecordingRate: (value) => _save({'recordingSampleRate': value}),
            onRecordingRetention: (value) =>
                _save({'recordingRetentionDays': value}),
          ),
      ],
    );
  }
}
