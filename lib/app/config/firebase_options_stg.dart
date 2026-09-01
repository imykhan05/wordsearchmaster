/// Firebase Android credentials for the `stg` flavor — project
/// `wsm-stg-b1d5f`, package `com.educativz.wordsearchmaster.stg`.
///
/// Values copied from that project's `google-services.json`
/// (`docs/firebase-setup.md` §2). Android only — this app has no iOS/web
/// target (CLAUDE.md → scope is a 2GB-RAM Android phone).
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

abstract final class StgFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyCeNvnaV8vPSB19VCsKRI8pugWtWpe-LTE',
    appId: '1:186642919120:android:78afac3ffaec6b81de38d5',
    messagingSenderId: '186642919120',
    projectId: 'wsm-stg-b1d5f',
    storageBucket: 'wsm-stg-b1d5f.firebasestorage.app',
  );
}
