// =============================================================================
// ShiftEase — app shell (M1)
// =============================================================================
// Top-level MaterialApp. Screens receive the ScheduleService through their
// constructors (constructor injection — no global/service-locator, plan5
// D-UI-3). Navigation is plain Navigator pushes between feature screens.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/jobs/jobs_screen.dart';

class ShiftEaseApp extends StatelessWidget {
  final ScheduleService service;

  const ShiftEaseApp({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShiftEase',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: JobsScreen(service: service),
    );
  }
}
