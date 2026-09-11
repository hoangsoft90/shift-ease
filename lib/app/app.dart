// =============================================================================
// ShiftEase — app shell (M1)
// =============================================================================
// Top-level MaterialApp. Screens receive the ScheduleService through their
// constructors (constructor injection — no global/service-locator, plan5
// D-UI-3). Navigation is plain Navigator pushes between feature screens.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:shiftease/domain/schedule_service.dart';
import 'package:shiftease/features/ads/ad_banner_widget.dart';
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
      // Monetization banner (2026-09-11) pinned under the app shell;
      // self-hiding when ads are disabled/unloaded — zero layout impact
      // on the calendar itself (INVARIANT-008 untouched).
      home: Column(
        children: [
          Expanded(child: JobsScreen(service: service)),
          const AdBannerWidget(),
        ],
      ),
    );
  }
}
