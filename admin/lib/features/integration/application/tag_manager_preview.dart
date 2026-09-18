import 'dart:convert';

enum TagPreviewStatus { fires, notFired, needsBrowserCheck }

class TagPreviewResult {
  const TagPreviewResult({
    required this.name,
    required this.type,
    required this.status,
    this.eventType,
    this.properties = const {},
  });

  final String name;
  final String type;
  final TagPreviewStatus status;
  final String? eventType;
  final Map<String, Object?> properties;
}

class TagManagerPreview {
  static List<TagPreviewResult> evaluate(
    List<Map<String, dynamic>> tags, {
    required String event,
    String? url,
    String? title,
    String? referrer,
    String? eventName,
    String? eventCategory,
    String? eventAction,
    Map<String, Object?> eventProperties = const {},
    Map<String, Object?> context = const {},
  }) {
    return [
      for (var index = 0; index < tags.length; index++)
        _evaluateTag(
          tags[index],
          index,
          event: event,
          url: url,
          title: title,
          referrer: referrer,
          eventName: eventName,
          eventCategory: eventCategory,
          eventAction: eventAction,
          eventProperties: eventProperties,
          context: context,
        ),
    ];
  }

  static TagPreviewResult _evaluateTag(
    Map<String, dynamic> tag,
    int index, {
    required String event,
    required String? url,
    required String? title,
    required String? referrer,
    required String? eventName,
    required String? eventCategory,
    required String? eventAction,
    required Map<String, Object?> eventProperties,
    required Map<String, Object?> context,
  }) {
    final type = tag['type'] as String? ?? 'event';
    final triggers = _triggers(tag, type);
    var matched = false;
    var hasCustomJavaScript = false;
    for (final trigger in triggers) {
      if (trigger is String) {
        matched |= trigger.trim() == event;
      } else if (trigger is Map) {
        final triggerType = trigger['type'] as String?;
        if (triggerType == 'custom_js') {
          hasCustomJavaScript = true;
        } else {
          matched |=
              trigger['event'] == event &&
              _conditionsMatch(trigger['conditions'], eventProperties);
        }
      }
    }

    final status = matched
        ? TagPreviewStatus.fires
        : hasCustomJavaScript
        ? TagPreviewStatus.needsBrowserCheck
        : TagPreviewStatus.notFired;
    final name =
        _text(tag['name']) ?? _text(tag['eventType']) ?? 'Tag ${index + 1}';
    final eventType = _text(tag['eventType']) ?? _text(tag['name']);
    final properties = <String, Object?>{};
    if (status == TagPreviewStatus.fires && type != 'custom_html') {
      properties.addAll(eventProperties);
      final configured = tag['properties'];
      if (configured is Map) {
        for (final entry in configured.entries) {
          final key = '${entry.key}'.trim();
          if (key.isEmpty) continue;
          properties[key] = _resolveValue(
            entry.value,
            event: event,
            url: url,
            title: title,
            referrer: referrer,
            eventName: eventName,
            eventCategory: eventCategory,
            eventAction: eventAction,
            eventProperties: eventProperties,
            context: context,
          );
        }
      }
    }

    return TagPreviewResult(
      name: name,
      type: type,
      status: status,
      eventType: eventType,
      properties: properties,
    );
  }

  static List<dynamic> _triggers(Map<String, dynamic> tag, String type) {
    final configured = tag['triggers'];
    if (configured is List && configured.isNotEmpty) return configured;
    final legacy = tag['trigger'];
    if (legacy != null) return [legacy];
    if (type == 'page_view') return const ['page_view'];
    return const [];
  }

  static bool _conditionsMatch(
    Object? configured,
    Map<String, Object?> eventProperties,
  ) {
    if (configured == null) return true;
    if (configured is! List || configured.length > 20) return false;
    for (final condition in configured) {
      if (condition is! Map) return false;
      final property = condition['property'];
      final operator = condition['operator'];
      if (property is! String ||
          property.trim().isEmpty ||
          operator is! String) {
        return false;
      }
      final exists =
          eventProperties.containsKey(property) &&
          eventProperties[property] != null;
      if (operator == 'exists') {
        if (!exists) return false;
        continue;
      }
      if (!exists || condition['value'] is! String) return false;
      final actual = eventProperties[property];
      final actualText = switch (actual) {
        String value => value,
        num value => '$value',
        bool value => '$value',
        _ => null,
      };
      if (actualText == null) return false;
      final expected = condition['value'] as String;
      final matches = switch (operator) {
        'equals' => actualText == expected,
        'not_equals' => actualText != expected,
        'contains' => actualText.contains(expected),
        'starts_with' => actualText.startsWith(expected),
        'ends_with' => actualText.endsWith(expected),
        _ => false,
      };
      if (!matches) return false;
    }
    return true;
  }

  static Object? _resolveValue(
    Object? value, {
    required String event,
    required String? url,
    required String? title,
    required String? referrer,
    required String? eventName,
    required String? eventCategory,
    required String? eventAction,
    required Map<String, Object?> eventProperties,
    required Map<String, Object?> context,
  }) {
    if (value is! String) return value;
    return value.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (match) {
      final name = match.group(1)!.trim();
      final resolved = _resolveVariable(
        name,
        event: event,
        url: url,
        title: title,
        referrer: referrer,
        eventName: eventName,
        eventCategory: eventCategory,
        eventAction: eventAction,
        eventProperties: eventProperties,
        context: context,
      );
      return resolved == null ? match.group(0)! : _stringValue(resolved);
    });
  }

  static Object? _resolveVariable(
    String name, {
    required String event,
    required String? url,
    required String? title,
    required String? referrer,
    required String? eventName,
    required String? eventCategory,
    required String? eventAction,
    required Map<String, Object?> eventProperties,
    required Map<String, Object?> context,
  }) {
    final builtIns = <String, Object?>{
      'Page URL': url,
      'Page Title': title,
      'Referrer': referrer,
      'Event': event,
      'Event Name': eventName,
      'Event Category': eventCategory,
      'Event Action': eventAction,
      ...context,
    };
    if (builtIns.containsKey(name)) return builtIns[name];
    final property = RegExp(r'^Event Property:\s*(.+)$').firstMatch(name);
    if (property != null && eventProperties.containsKey(property.group(1))) {
      return _stringValue(eventProperties[property.group(1)]);
    }
    return null;
  }

  static String _stringValue(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    try {
      return jsonEncode(value);
    } on Object {
      return '';
    }
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
