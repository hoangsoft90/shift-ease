// =============================================================================
// ICS file saver (Gate C B3) — offline-only. Writes the generated calendar
// text to the app support directory (path_provider); falls back to the system
// temp directory when the plugin is unavailable (e.g. widget-test harness).
// Never touches a server. Returns the written path or null on failure.
// =============================================================================

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveIcsFile({
  required String fileName,
  required String content,
}) async {
  Directory? dir;
  try {
    final support = await getApplicationSupportDirectory();
    dir = support;
  } catch (_) {
    dir = Directory.systemTemp;
  }
  try {
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
