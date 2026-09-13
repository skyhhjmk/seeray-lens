import 'package:flutter/material.dart';

/// Searchable convenience choices; the backend remains the authority for the
/// complete IANA timezone database and validates manually entered values.
class TimezonePicker extends StatelessWidget {
  const TimezonePicker({required this.controller, super.key});

  final TextEditingController controller;

  static const _zones = <String>[
    'UTC',
    'Africa/Johannesburg',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/New_York',
    'America/Sao_Paulo',
    'Asia/Bangkok',
    'Asia/Dubai',
    'Asia/Hong_Kong',
    'Asia/Kolkata',
    'Asia/Shanghai',
    'Asia/Singapore',
    'Asia/Tokyo',
    'Australia/Sydney',
    'Europe/Berlin',
    'Europe/London',
    'Europe/Paris',
    'Pacific/Auckland',
  ];

  @override
  Widget build(BuildContext context) => DropdownMenu<String>(
    controller: controller,
    enableFilter: true,
    requestFocusOnTap: true,
    label: const Text('IANA timezone'),
    dropdownMenuEntries: _zones
        .map((zone) => DropdownMenuEntry<String>(value: zone, label: zone))
        .toList(growable: false),
  );
}
