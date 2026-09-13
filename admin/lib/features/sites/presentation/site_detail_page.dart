import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/site_controller.dart';
import '../../../shared/presentation/timezone_picker.dart';

class SiteDetailPage extends ConsumerStatefulWidget {
  const SiteDetailPage({required this.siteId, super.key});

  final String siteId;

  @override
  ConsumerState<SiteDetailPage> createState() => _SiteDetailPageState();
}

class _SiteDetailPageState extends ConsumerState<SiteDetailPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _timezone = TextEditingController();
  final _language = TextEditingController();
  final _raw = TextEditingController();
  final _aggregate = TextEditingController();
  bool _enabled = true;
  String? _loadedId;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    _language.dispose();
    _raw.dispose();
    _aggregate.dispose();
    super.dispose();
  }

  void _load(Site site) {
    if (_loadedId == site.id) return;
    _loadedId = site.id;
    _name.text = site.name;
    _timezone.text = site.timezone;
    _language.text = site.defaultLanguage ?? '';
    _raw.text = '${site.rawRetentionDays}';
    _aggregate.text = '${site.aggregateRetentionDays}';
    _enabled = site.trackingEnabled;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(sitesProvider.notifier).updateSite(widget.siteId, {
        'name': _name.text.trim(),
        'timezone': _timezone.text.trim(),
        'defaultLanguage': _language.text.trim().isEmpty
            ? null
            : _language.text.trim(),
        'trackingEnabled': _enabled,
        'rawRetentionDays': int.parse(_raw.text),
        'aggregateRetentionDays': int.parse(_aggregate.text),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Site saved')));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(sitesProvider).value ?? const <Site>[];
    final site = sites.where((item) => item.id == widget.siteId).firstOrNull;
    if (site == null) {
      return const Scaffold(body: Center(child: Text('Site not found')));
    }
    _load(site);
    return Scaffold(
      appBar: AppBar(title: Text(site.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Site name'),
                      validator: _required,
                    ),
                    TimezonePicker(controller: _timezone),
                    TextField(
                      controller: _language,
                      decoration: const InputDecoration(
                        labelText: 'Default language',
                      ),
                    ),
                    SwitchListTile(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      title: const Text('Tracking enabled'),
                    ),
                    TextFormField(
                      controller: _raw,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Raw retention days',
                      ),
                      validator: _positive,
                    ),
                    TextFormField(
                      controller: _aggregate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Aggregate retention days',
                      ),
                      validator: _positive,
                    ),
                    const SizedBox(height: 12),
                    const Text('Tracking ID'),
                    SelectableText(site.trackingId),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/sites/${site.id}/domains'),
                icon: const Icon(Icons.language),
                label: const Text('Allowed domains'),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(sitesProvider.notifier).delete(site.id);
                  if (context.mounted) context.go('/sites');
                },
                child: const Text('Delete site'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _positive(String? value) =>
    int.tryParse(value ?? '') == null || int.parse(value!) < 1
    ? 'Enter a positive number'
    : null;

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
