/// Firebase Android credentials for the `prod` flavor — project
/// `wsm-prod-a750e`, package `com.educativz.wordsearchmaster`.
///
/// Values copied from that project's `google-services.json`
/// (`docs/firebase-setup.md` §2). Android only — this app has no iOS/web
/// target (CLAUDE.md → scope is a 2GB-RAM Android phone).
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

abstract final class ProdFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyBJxS0urvCkLy1yofFfmgke-Gu2aSW3xsk',
    appId: '1:145564669719:android:75f716015efe1d44634952',
    messagingSenderId: '145564669719',
    projectId: 'wsm-prod-a750e',
    storageBucket: 'wsm-prod-a750e.firebasestorage.app',
  );
}
