import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/audio/sound_settings.dart';
import 'package:word_search_master/services/haptics/haptics_service.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// A recording double for the provider-sync tests below, parallel to
/// `audio_service_test.dart`'s `_FakeAudioService`.
final class _FakeHapticsService implements HapticsService {
  final List<String> calls = [];

  @override
  void selectionTick() => calls.add('selectionTick');

  @override
  void wordFound() => calls.add('wordFound');

  @override
  void levelComplete() => calls.add('levelComplete');

  @override
  void buttonTap() => calls.add('buttonTap');

  @override
  void setEnabled(bool enabled) => calls.add('setEnabled:$enabled');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoopHapticsService', () {
    test('every call is a harmless no-op', () {
      const service = NoopHapticsService();
      service.selectionTick();
      service.wordFound();
      service.levelComplete();
      service.buttonTap();
      service.setEnabled(false);
      // Reaching here without throwing IS the assertion.
    });
  });

  group('SystemHapticsService — the full Ch03 map', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              platformCalls.add(call);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// The real `HapticFeedback.*` static methods all invoke ONE platform
    /// method (`HapticFeedback.vibrate`) and pass a `HapticFeedbackType.*`
    /// STRING as the argument to say which — see
    /// `package:flutter/src/services/haptic_feedback.dart`.
    String? lastType() =>
        platformCalls.isEmpty ? null : platformCalls.last.arguments as String?;

    test('wordFound is lightImpact — "0ms audio + lightImpact" (Ch03)', () {
      SystemHapticsService().wordFound();
      expect(lastType(), 'HapticFeedbackType.lightImpact');
    });

    test('selectionTick is selectionClick — one per newly entered cell', () {
      SystemHapticsService().selectionTick();
      expect(lastType(), 'HapticFeedbackType.selectionClick');
    });

    test('buttonTap is selectionClick — a light UI tick', () {
      SystemHapticsService().buttonTap();
      expect(lastType(), 'HapticFeedbackType.selectionClick');
    });

    test('levelComplete is a stronger mediumImpact — the biggest moment', () {
      SystemHapticsService().levelComplete();
      expect(lastType(), 'HapticFeedbackType.mediumImpact');
    });

    test('setEnabled(false) silences every touchpoint instantly', () {
      final service = SystemHapticsService()..setEnabled(false);

      service.selectionTick();
      service.wordFound();
      service.levelComplete();
      service.buttonTap();

      expect(
        platformCalls,
        isEmpty,
        reason: 'the master toggle must gate every call, not just future ones',
      );
    });

    test('setEnabled(true) after a mute lets haptics fire again', () {
      SystemHapticsService()
        ..setEnabled(false)
        ..setEnabled(true)
        ..wordFound();

      expect(lastType(), 'HapticFeedbackType.lightImpact');
    });
  });

  group('hapticsEnabledSyncProvider', () {
    ProviderContainer containerWith(
      HapticsService fake, {
      bool hapticsEnabled = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          hapticsServiceProvider.overrideWithValue(fake),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(hapticsEnabled: hapticsEnabled),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('syncs the stored toggle immediately on first read', () {
      final fake = _FakeHapticsService();
      containerWith(
        fake,
        hapticsEnabled: false,
      ).read(hapticsEnabledSyncProvider);

      expect(fake.calls, ['setEnabled:false']);
    });

    test('toggling mid-session reaches the service instantly', () {
      final fake = _FakeHapticsService();
      final container = containerWith(fake, hapticsEnabled: true);
      container.read(hapticsEnabledSyncProvider);

      container.read(hapticsEnabledProvider.notifier).set(false);

      expect(fake.calls, ['setEnabled:true', 'setEnabled:false']);
    });
  });
}
