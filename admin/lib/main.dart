import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/seeray_api.dart';
import 'features/auth/application/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final apiBaseUrl = preferences.getString('seeray.api.base_url');
  runApp(
    ProviderScope(
      overrides: [
        if (apiBaseUrl != null && apiBaseUrl.isNotEmpty)
          apiProvider.overrideWithValue(SeeRayApi(baseUrl: apiBaseUrl)),
      ],
      child: const SeeRayLensAdminApp(),
    ),
  );
}
