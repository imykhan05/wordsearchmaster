import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/splash_screen.dart';

/// [BootSplash]'s contract: it paints immediately, it reports real progress,
/// and it hands off when STARTUP is done rather than when a clock says so.
///
/// No `ProviderScope` anywhere in this file, and that is the point rather
/// than a convenience — this widget is mounted before one exists (see
/// `bootstrap.dart`'s `_BootGate`), so a version of it that quietly started
/// reading a provider would crash on a real launch and pass a test that had
/// helpfully wrapped it in a scope.
void main() {
  /// Drives the splash against a startup the test completes by hand.
  Future<void> pumpSplash(
    WidgetTester tester, {
    required Future<void> ready,
    required void Function() onFinished,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BootSplash(ready: ready, onFinished: onFinished),
      ),
    );
  }

  testWidgets('paints the artwork and a 0% readout on its very first frame', (
    tester,
  ) async {
    // The whole reason this widget exists: something is on screen at once,
    // rather than a blank window for as long as startup takes.
    await pumpSplash(
      tester,
      ready: Completer<void>().future,
      onFinished: () {},
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('the LOADING caption inks in with the bar, not just beside it', (
    tester,
  ) async {
    // The word itself is masked so it fills along with the bar and the
    // percentage. Asserting the mask EXISTS is the guard worth having: the
    // edge's position comes from the same `progress` the percentage tests
    // above already pin, so what could regress here is the treatment being
    // dropped in a refactor and the caption going back to flat text.
    await pumpSplash(
      tester,
      ready: Completer<void>().future,
      onFinished: () {},
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.textContaining('%').hitTestable(),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
      reason: 'the percentage is a plain readout; only the caption is masked',
    );
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('the bar climbs while startup is still running', (tester) async {
    await pumpSplash(
      tester,
      ready: Completer<void>().future,
      onFinished: () {},
    );
    await tester.pump();

    await tester.pump(BootSplash.fillDuration ~/ 2);
    final midway = _percentShown(tester);
    expect(midway, greaterThan(0));
    expect(midway, lessThan(90));
  });

  testWidgets('it STOPS at the ceiling while startup is outstanding — the bar '
      'never claims to be finished before the app is', (tester) async {
    final startup = Completer<void>();
    var finished = false;
    await pumpSplash(
      tester,
      ready: startup.future,
      onFinished: () => finished = true,
    );
    await tester.pump();

    // Far past the fill, with startup still hanging.
    await tester.pump(BootSplash.fillDuration * 3);

    expect(
      _percentShown(tester),
      (BootSplash.progressCeiling * 100).round(),
      reason: 'the bar ran past the ceiling with work still outstanding',
    );
    expect(
      finished,
      isFalse,
      reason: 'handing off here would drop the player into a half-built app',
    );
  });

  testWidgets('startup completing is what finishes the bar and hands off', (
    tester,
  ) async {
    final startup = Completer<void>();
    var finished = false;
    await pumpSplash(
      tester,
      ready: startup.future,
      onFinished: () => finished = true,
    );
    await tester.pump();
    await tester.pump(BootSplash.fillDuration * 2);
    expect(finished, isFalse);

    startup.complete();
    // SETTLE rather than pump a measured duration. The finishing animation is
    // started from a microtask, so its ticker only registers on the following
    // frame — a single `pump(finishDuration)` lands that first frame at
    // elapsed zero and reads 90%, which says nothing about the widget.
    await tester.pumpAndSettle();

    expect(_percentShown(tester), 100);
    expect(finished, isTrue);
  });

  testWidgets('a startup that finishes FIRST still runs the bar to the end', (
    tester,
  ) async {
    // The fast-launch case. Cutting away the instant services resolve would
    // flash a half-filled bar off the screen; the remaining fill is what
    // makes a quick start read as a start rather than a glitch.
    var finished = false;
    await pumpSplash(
      tester,
      ready: Future<void>.value(),
      onFinished: () => finished = true,
    );
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(
      finished,
      isFalse,
      reason: 'handed off before the bar had gone anywhere',
    );

    await tester.pump(BootSplash.fillDuration + BootSplash.finishDuration);

    expect(finished, isTrue);
    expect(_percentShown(tester), 100);
  });

  testWidgets('a startup that FAILS still hands off', (tester) async {
    // `initializeServices` catches everything and never throws, so this is
    // defence against a future caller rather than a live path — but the one
    // outcome that must not happen is a player stranded on a splash forever.
    final startup = Completer<void>();
    var finished = false;
    await pumpSplash(
      tester,
      ready: startup.future,
      onFinished: () => finished = true,
    );
    await tester.pump();

    // Failed AFTER mounting rather than handed in already-failed: a
    // `Future.error` built in the test body has no listener at the moment it
    // is created, and the test zone reports that as an unhandled error before
    // the widget can attach its own `catch`. Completing it here makes the
    // widget's own `await` the listener, which is also the real sequence.
    startup.completeError(StateError('startup blew up'));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
  });

  testWidgets('it hands off exactly once', (tester) async {
    var calls = 0;
    await pumpSplash(
      tester,
      ready: Future<void>.value(),
      onFinished: () => calls++,
    );
    await tester.pump();
    await tester.pump(BootSplash.fillDuration + BootSplash.finishDuration);
    await tester.pump(BootSplash.fillDuration);

    expect(calls, 1);
  });
}

/// The live "NN%" readout, as an int.
int _percentShown(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .firstWhere(
        (data) => data != null && data.endsWith('%'),
        orElse: () => null,
      );
  return int.parse(text!.substring(0, text.length - 1));
}
