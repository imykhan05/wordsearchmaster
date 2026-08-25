import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/presentation/widgets/rolling_counter.dart';

void main() {
  Widget wrap(Widget child, {bool reduceMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('shows the value immediately on first appearance', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const RollingCounter(value: 42)));
    await tester.pump();

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets(
    'a changed value animates through intermediate numbers over 400ms, linearly',
    (tester) async {
      await tester.pumpWidget(wrap(const RollingCounter(value: 0)));
      await tester.pump();
      expect(find.text('0'), findsOneWidget);

      await tester.pumpWidget(wrap(const RollingCounter(value: 100)));
      await tester.pump();
      // Linear, so halfway through 400ms should read close to 50.
      await tester.pump(const Duration(milliseconds: 200));

      final shown = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(shown, closeTo(50, 5));

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('100'), findsOneWidget);
    },
  );

  testWidgets('reduce-motion jumps straight to the new value', (tester) async {
    await tester.pumpWidget(
      wrap(const RollingCounter(value: 0), reduceMotion: true),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(const RollingCounter(value: 50), reduceMotion: true),
    );
    await tester.pump();

    expect(find.text('50'), findsOneWidget);
  });
}
