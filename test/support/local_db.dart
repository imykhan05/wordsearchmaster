import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/integrity.dart';
import 'package:word_search_master/services/diagnostics/error_reporter.dart';

/// Captures the non-fatals the code under test files, so a test can assert
/// that a tamper was REPORTED and not just silently dropped.
final class RecordingErrorReporter implements ErrorReporter {
  final List<Object> errors = <Object>[];

  @override
  void nonFatal(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) => errors.add(error);

  Iterable<IntegrityViolation> get integrityViolations =>
      errors.whereType<IntegrityViolation>();
}

/// An opened test database plus everything a repository needs to read it.
typedef TestDatabase = ({
  AppDatabase database,
  RowIntegrity integrity,
  RecordingErrorReporter reporter,
});

/// Opens an in-memory database. Fine for anything that does not need the
/// bytes to survive a close.
Future<TestDatabase> openMemoryDatabase() =>
    _open(NativeDatabase.memory(), reporter: RecordingErrorReporter());

/// Opens a FILE-backed database at [file].
///
/// The tamper test needs a real file: "edit the row" has to mean editing the
/// bytes on disk through a separate connection, the way a player with a
/// SQLite editor would, not calling an update method that the code under test
/// also owns.
Future<TestDatabase> openFileDatabase(
  File file, {
  RecordingErrorReporter? reporter,
}) =>
    _open(NativeDatabase(file), reporter: reporter ?? RecordingErrorReporter());

Future<TestDatabase> _open(
  QueryExecutor executor, {
  required RecordingErrorReporter reporter,
}) async {
  // Several tests legitimately open two databases at once (comparing install
  // ids, migrating a second file). They never share an executor, so Drift's
  // corruption warning does not apply and only clutters the output.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final database = AppDatabase(executor, reporter: reporter);
  // Forces Drift to actually open, so onCreate/onUpgrade/beforeOpen have run
  // by the time the test's first assertion executes.
  final integrity = await database.integrity();
  return (database: database, integrity: integrity, reporter: reporter);
}

/// A scratch directory that cleans itself up.
Directory createTempDbDir() {
  final dir = Directory.systemTemp.createTempSync('wsm_db_test');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
