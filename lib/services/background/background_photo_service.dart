import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_photo_service.g.dart';

/// Picks the player's own photo to sit behind the board.
///
/// ---------------------------------------------------------------------------
/// THE APP NEVER OWNS THE PICTURE
///
/// The player's request was explicit: the photo must not become part of the
/// app. It does not. Nothing is bundled, nothing reaches the database, and the
/// APK is the same size with this feature as without it — what persists is one
/// PATH in `shared_preferences`, about a hundred bytes.
///
/// One honest qualification, because it cannot be engineered away: Android's
/// photo picker hands back a COPY in the app's own cache directory rather than
/// a live handle on the gallery file. That is the platform API, not a choice
/// here. So exactly one copy exists at a time, and it is:
///
///   * deleted on uninstall, by Android, along with everything else the app
///     stored — which is the player's "uninstall ke baad chala jaye" already
///     satisfied by the OS rather than by code that could get it wrong;
///   * deleted by the system whenever it wants the cache space back;
///   * deleted HERE the moment a different photo is picked ([_clearOld]).
///
/// The alternative — keeping a URI and re-reading the gallery every launch —
/// is not reliable under scoped storage: the permission a picker grants is not
/// persistable, so the background would vanish at an unpredictable point and
/// look like a bug. A cache copy that the OS is free to evict is the honest
/// version of the same intent, and `AppBackground` already treats a missing
/// file as an ordinary state.
///
/// Behind an interface for the reason every vendor SDK in this codebase is
/// (`AudioService`, `AdGateway`, `NotificationService`): a widget test must be
/// able to drive the picker without a platform channel.
abstract interface class BackgroundPhotoService {
  /// Opens the system photo picker and stores a downscaled copy.
  ///
  /// Returns the new file's path, or null if the player backed out or the
  /// platform refused — both are ordinary outcomes and neither is reported.
  Future<String?> pickAndStore();

  /// Removes the stored copy, if there is one.
  Future<void> clear();
}

/// Answers "nothing picked" to everything. The binding in tests and on any
/// platform without a picker.
final class NoopBackgroundPhotoService implements BackgroundPhotoService {
  const NoopBackgroundPhotoService();

  @override
  Future<String?> pickAndStore() async => null;

  @override
  Future<void> clear() async {}
}

/// The real one, over `image_picker`.
final class ImagePickerBackgroundPhotoService
    implements BackgroundPhotoService {
  ImagePickerBackgroundPhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Downscale ceiling, applied by the picker itself before a single byte
  /// reaches Dart.
  ///
  /// A 12MP photo is ~48MB once decoded, on a phone this game targets at 2GB
  /// of RAM total (CLAUDE.md's product thesis). Handing that to `Image.file`
  /// is how a background costs a level. At 1080x2400 the copy is a few hundred
  /// KB and decodes to something a low-end device can hold, and the loss is
  /// invisible on an image that is dimmed and sits behind opaque cards anyway.
  static const double _maxWidth = 1080;
  static const double _maxHeight = 2400;

  /// JPEG quality for the stored copy. High enough that a gradient sky does
  /// not band, low enough that the cache entry stays small.
  static const int _quality = 85;

  static const String _prefix = 'wsm_background_';

  @override
  Future<String?> pickAndStore() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxWidth,
        maxHeight: _maxHeight,
        imageQuality: _quality,
      );
      if (picked == null) return null;

      final directory = await getTemporaryDirectory();
      await _clearOld(directory);

      // A FRESH FILENAME EVERY TIME, never one fixed name. Flutter's image
      // cache keys a `FileImage` on its PATH, not on the file's contents or
      // mtime — so overwriting one name in place would leave the previous
      // photo on screen, and a player who picked a new one would be told,
      // convincingly, that the picker is broken.
      final destination = File(
        '${directory.path}/$_prefix'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(picked.path).copy(destination.path);

      // The picker's own temp file is a second copy of the same image; the
      // whole point of this class is that exactly one exists.
      await _deleteQuietly(File(picked.path));

      return destination.path;
    } catch (_) {
      // No gallery app, a permission refused on an older Android, a full
      // disk. None of these is worth a dialog — the player tapped a
      // decoration button and nothing happened, which is what "fail silently"
      // means everywhere else in this codebase.
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _clearOld(await getTemporaryDirectory());
    } catch (_) {
      // Same rule: a background that could not be removed is not an error the
      // player needs to hear about.
    }
  }

  /// Deletes every copy this class has ever written. Sweeps by PREFIX rather
  /// than deleting one remembered path, so a file orphaned by a crash between
  /// the copy and the preference write cannot sit in the cache forever.
  Future<void> _clearOld(Directory directory) async {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith(_prefix)) {
        await _deleteQuietly(entity);
      }
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best effort — the OS clears this directory on uninstall regardless.
    }
  }
}

/// Overridden in `bootstrap.dart` with the real picker. Defaults to the Noop
/// so every widget test — and the Style Gallery — builds with no plugin
/// registered, the same shape `audioServiceProvider` uses.
@Riverpod(keepAlive: true)
BackgroundPhotoService backgroundPhotoService(Ref ref) =>
    const NoopBackgroundPhotoService();
