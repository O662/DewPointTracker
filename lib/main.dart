import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';

import 'screens/root_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap cached base-map/forecast tile freshness at 1h. This keeps forecast
  // tiles fresh and silences flutter_map's "fallback freshness age" logs for
  // servers that don't send cache headers. (No-op on web.)
  BuiltInMapCachingProvider.getOrCreateInstance(
    overrideFreshAge: const Duration(hours: 1),
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(const DewPointApp());
}

class DewPointApp extends StatelessWidget {
  const DewPointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dew Point Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const RootShell(),
    );
  }
}
