import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/theme/background_style.dart';
import '../settings/ui_settings_store.dart';
import 'background_photo_service.dart';

part 'background_settings.g.dart';

/// What is painted behind the board, and — when that is a photo — where the
/// photo sits.
///
/// TWO NOTIFIERS, ONE DECISION, deliberately not merged into a record: the
/// style is a swatch a player taps and the path is a file the OS can take
/// away underneath them. `AppBackground` watches both, and keeping them apart
/// means a photo that goes missing does not reset the STYLE — pick the same
/// picture again and the choice is still where it was.
///
/// Both follow `SoundThemeSetting`'s shape exactly: state first, disk second,
/// because a swatch must colour in under the finger and a preference that
/// fails to write is not worth blocking a frame over.
@riverpod
class BackgroundStyleSetting extends _$BackgroundStyleSetting {
  @override
  BackgroundStyle build() => ref.watch(uiSettingsStoreProvider).backgroundStyle;

  void set(BackgroundStyle value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setBackgroundStyle(value);
  }
}

/// The stored photo's path, or null when there is none — or when the file it
/// names is gone.
@riverpod
class BackgroundPhotoPath extends _$BackgroundPhotoPath {
  /// Checked ONCE, HERE, rather than on every frame of the widget that draws
  /// it.
  ///
  /// The file sits in a cache directory the OS may empty whenever it wants the
  /// space, so "the preference names a file that no longer exists" is an
  /// ordinary state rather than a fault. Resolving it at the edge — one `stat`
  /// when the value enters the app, not one per rebuild — means everything
  /// downstream is a plain "photo or no photo" question with no I/O in it.
  ///
  /// `AppBackground` still carries an `errorBuilder` for the case this cannot
  /// cover: an eviction that happens WHILE the app is on screen, after this
  /// has already answered.
  @override
  String? build() {
    final stored = ref.watch(uiSettingsStoreProvider).backgroundPhotoPath;
    if (stored == null) return null;
    return File(stored).existsSync() ? stored : null;
  }

  /// Opens the picker and, if the player chose something, switches the
  /// background to it in one step.
  ///
  /// The style flips ONLY on success. A cancelled picker leaves the screen
  /// exactly as it was — selecting `photo` first and then discovering there is
  /// no photo would blank the background for a player who simply changed
  /// their mind.
  ///
  /// Returns whether a photo was stored, so the caller can decide what (if
  /// anything) to say.
  Future<bool> pick() async {
    // Every `ref` read happens before the first await — the picker owns the
    // screen for as long as the player browses their gallery, which is
    // exactly the window `ProgressionController`'s own header warns about.
    final service = ref.read(backgroundPhotoServiceProvider);
    final store = ref.read(uiSettingsStoreProvider);
    final styleSetting = ref.read(backgroundStyleSettingProvider.notifier);

    final path = await service.pickAndStore();
    if (path == null) return false;

    await store.setBackgroundPhotoPath(path);
    state = path;
    styleSetting.set(BackgroundStyle.photo);
    return true;
  }

  /// Forgets the photo and deletes the copy. Called when the player picks a
  /// gradient instead, so a background they stopped using does not keep
  /// sitting in the cache.
  Future<void> clear() async {
    final service = ref.read(backgroundPhotoServiceProvider);
    final store = ref.read(uiSettingsStoreProvider);

    await store.setBackgroundPhotoPath(null);
    state = null;
    await service.clear();
  }
}
