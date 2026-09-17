import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latch_swipe_confirm/latch_swipe_confirm.dart';

Widget _app({required FutureOr<bool?> Function() onConfirm, List<LatchState>? states, bool reduceMotion = false, Duration? resetAfter}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: LatchSwipeConfirm(
                key: const Key('latch'),
                label: 'Swipe to pay',
                doneLabel: 'Paid',
                failedLabel: 'Payment failed',
                haptics: false,
                resetAfter: resetAfter,
                onConfirm: onConfirm,
                onStateChanged: states?.add,
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _drag(WidgetTester tester, double dx) async {
  final start = tester.getTopLeft(find.byKey(const Key('latch'))) + const Offset(32, 32);
  final gesture = await tester.startGesture(start);
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
}

void main() {
  group('maths', () {
    test('progress is the share of the travel covered', () {
      expect(latchProgress(0, 360, 64), 0);
      expect(latchProgress(148, 360, 64), 0.5);
      expect(latchProgress(1000, 360, 64), 1);
      expect(latchProgress(-20, 360, 64), 0);
      expect(latchProgress(50, 40, 64), 0);
    });

    test('resistance holds the thumb back only at the start', () {
      expect(latchResistance(0), 0);
      expect(latchResistance(0.05), lessThan(0.05));
      expect(latchResistance(0.12), closeTo(0.12, 1e-9));
      expect(latchResistance(0.6), 0.6);
      // Still moves forward the whole way.
      var last = 0.0;
      for (var i = 1; i <= 20; i++) {
        final v = latchResistance(i / 100);
        expect(v, greaterThan(last));
        last = v;
      }
    });

    test('latching needs the threshold or a strong fling past halfway', () {
      expect(shouldLatch(0.9, 0), isTrue);
      expect(shouldLatch(0.7, 0), isFalse);
      expect(shouldLatch(0.6, 2.4), isTrue);
      expect(shouldLatch(0.3, 5), isFalse);
      expect(shouldLatch(0.8, 0, threshold: 0.75), isTrue);
    });
  });

  group('LatchSwipeConfirm', () {
    testWidgets('a short drag springs back without confirming', (tester) async {
      var calls = 0;
      final states = <LatchState>[];
      await tester.pumpWidget(_app(onConfirm: () => calls++ > -1, states: states));
      await _drag(tester, 120);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(states, [LatchState.dragging, LatchState.idle]);
      expect(find.text('Swipe to pay'), findsOneWidget);
    });

    testWidgets('dragging to the end confirms and shows the done label', (tester) async {
      final completer = Completer<bool>();
      final states = <LatchState>[];
      await tester.pumpWidget(_app(onConfirm: () => completer.future, states: states));
      await _drag(tester, 340);
      await tester.pump(const Duration(milliseconds: 100));
      expect(states.last, LatchState.confirming);
      completer.complete(true);
      await tester.pumpAndSettle();
      expect(states.last, LatchState.done);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('a failed confirm shakes, says so and returns to idle', (tester) async {
      final states = <LatchState>[];
      await tester.pumpWidget(_app(onConfirm: () async => throw StateError('declined'), states: states));
      await _drag(tester, 340);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Payment failed'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(states, [LatchState.dragging, LatchState.confirming, LatchState.failed, LatchState.idle]);
      expect(find.text('Swipe to pay'), findsOneWidget);
    });

    testWidgets('returning false also fails', (tester) async {
      final states = <LatchState>[];
      await tester.pumpWidget(_app(onConfirm: () => false, states: states));
      await _drag(tester, 340);
      await tester.pump(const Duration(milliseconds: 60));
      expect(states, contains(LatchState.failed));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('keyboard users confirm with Enter', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          onConfirm: () {
            calls++;
            return true;
          },
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('screen readers get a button they can activate', (tester) async {
      final handle = tester.ensureSemantics();
      var calls = 0;
      await tester.pumpWidget(
        _app(
          onConfirm: () {
            calls++;
            return true;
          },
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Swipe to pay')),
        matchesSemantics(
          label: 'Swipe to pay',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('Swipe to pay'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.bySemanticsLabel('Paid'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('resets after the given delay', (tester) async {
      await tester.pumpWidget(_app(onConfirm: () => true, resetAfter: const Duration(seconds: 2)));
      await _drag(tester, 340);
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Swipe to pay'), findsOneWidget);
    });

    testWidgets('reduced motion jumps instead of springing', (tester) async {
      await tester.pumpWidget(_app(onConfirm: () => true, reduceMotion: true));
      await _drag(tester, 340);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('Paid'), findsOneWidget);
    });
  });
}
