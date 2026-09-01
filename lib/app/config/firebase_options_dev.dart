/// Firebase Android credentials for the `dev` flavor — project
/// `wsm-dev-45b7c`, package `com.educativz.wordsearchmaster.dev`.
///
/// Values copied from that project's `google-services.json`
/// (`docs/firebase-setup.md` §2). Android only — this app has no iOS/web
/// target (CLAUDE.md → scope is a 2GB-RAM Android phone).
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

abstract final class DevFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyCdyShWhWGcmlYrN1gfWXlA2IrMHjIRSQ4',
    appId: '1:102773080765:android:c7e2015a7537e3ca6d2dd4',
    messagingSenderId: '102773080765',
    projectId: 'wsm-dev-45b7c',
    storageBucket: 'wsm-dev-45b7c.firebasestorage.app',
  );
}
