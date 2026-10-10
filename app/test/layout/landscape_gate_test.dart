import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/learn_piano_app.dart';

void main() {
  testWidgets('portrait blocks interaction but preserves the navigator', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LearnPianoApp());

    expect(find.byKey(const Key('landscape-required')), findsOneWidget);
    expect(find.text('Obróć urządzenie poziomo'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final gate = tester.widget<IgnorePointer>(find.byType(IgnorePointer).first);
    expect(gate.ignoring, isTrue);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landscape-required')), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)),
      same(navigator),
    );
    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('landscape-required')), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)),
      same(navigator),
    );
  });
}
