import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const AeroVueloApp());
}

class AeroVueloApp extends StatelessWidget {
  const AeroVueloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AeroVuelo · Sky Booking System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}
