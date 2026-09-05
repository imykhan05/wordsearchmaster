import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/diagnostics/error_reporter.dart';
import 'name_report_api.dart';

/// The real [NameReportApi]. A bare `add()` — `firestore.rules` shapes what a
/// report may contain, and `onNameReportCreated` (server-side) is the only
/// reader of what gets written here.
final class FirestoreNameReportApi implements NameReportApi {
  const FirestoreNameReportApi({
    required FirebaseFirestore firestore,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final ErrorReporter _reporter;

  @override
  Future<bool> reportDisplayName({
    required String reporterUid,
    required String reportedUid,
  }) async {
    try {
      await _firestore.collection('nameReports').add({
        'reportedUid': reportedUid,
        'reporterUid': reporterUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'nameReport.reportDisplayName'},
      );
      return false;
    }
  }
}
