// =============================================================================
// Write error boundary (RC plan §A1). The single seam where a UI event
// handler converts a persistence/domain exception into a user-visible
// message. Every write path — override (CREATE/UPDATE/REPLACE/DELETE/SPLIT/
// SWAP), roster re-version, import commit, PayRule save, template save,
// pattern save, ICS export, backup/restore — must route exceptions through
// [writeErrorMessage] (or [runWrite]/[runWriteAsync]) so an exception NEVER
// escapes an onPressed/onCommit handler into an unhandled crash.
//
// Nothing is swallowed silently: every failure surfaces a message, and the
// DB layer already guarantees the data is untouched when an exception leaves
// a repository (transactions roll back before the exception escapes).
// =============================================================================

import 'package:shiftease/core/db/schedule_repository.dart'
    show ImmutableHistoryError;

/// Map any exception to a user-facing message. Specific types first (their
/// messages are meaningful); the catch-all never fabricates a fake success.
String? writeErrorMessage(Object error) {
  if (error is ImmutableHistoryError) {
    return 'Cannot rewrite history: ${error.message}';
  }
  if (error is ArgumentError) {
    final m = error.message;
    return (m == null || m.toString().isEmpty)
        ? 'Invalid input.'
        : m.toString();
  }
  if (error is StateError) {
    return error.message;
  }
  if (error is FormatException) {
    return 'Invalid format: ${error.message}';
  }
  return 'Unexpected error: $error';
}

/// Runs a synchronous write action; returns null on success or a user-facing
/// message when the write threw. The caller shows the message where its other
/// validation errors appear (form error line / snackbar) — never rethrows.
String? runWrite(void Function() action) {
  try {
    action();
    return null;
  } catch (e) {
    return writeErrorMessage(e);
  }
}

/// Async flavour of [runWrite] for handlers that are already Future-returning.
Future<String?> runWriteAsync(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (e) {
    return writeErrorMessage(e);
  }
}