import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light({Color? seedColor}) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor ?? const Color(0xFF2855D9),
    ),
    useMaterial3: true,
  );
}
