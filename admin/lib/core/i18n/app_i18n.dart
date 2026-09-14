import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeProvider = NotifierProvider<AppLocaleNotifier, Locale>(
  AppLocaleNotifier.new,
);

class AppLocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('zh');

  void select(Locale locale) => state = locale;
}

extension AppI18n on BuildContext {
  bool get isChinese => Localizations.localeOf(this).languageCode == 'zh';

  String tr(String english, String chinese) => isChinese ? chinese : english;
}

class LanguageMenu extends ConsumerWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      tooltip: context.tr('Language', '语言'),
      initialValue: locale,
      onSelected: (value) => ref.read(localeProvider.notifier).select(value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: Locale('zh'), child: Text('中文')),
        PopupMenuItem(value: Locale('en'), child: Text('English')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(child: Text(locale.languageCode == 'zh' ? '中' : 'EN')),
      ),
    );
  }
}
