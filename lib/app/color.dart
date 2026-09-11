// =============================================================================
// Shared UI color helper. Template colors are stored as "#RRGGBB" strings
// (ShiftTemplate.color is time/UI only, INVARIANT-005). Tolerant parse: an
// unparsable value gets a neutral fallback — never a crash from a cosmetic
// field.
// =============================================================================

import 'package:flutter/material.dart';

Color colorFromHex(String hex, {Color fallback = Colors.blueGrey}) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return fallback;
  return Color(v);
}
