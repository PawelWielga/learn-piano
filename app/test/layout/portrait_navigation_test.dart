import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/learn_piano_app.dart';

void main() {
  testWidgets('portrait renders the app and permits navigating between screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LearnPianoApp());

    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);
    expect(find.byKey(const Key('request-landscape-lock')), findsNothing);
    expect(find.byKey(const Key('landscape-required')), findsNothing);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await tester.tap(find.byKey(const Key('open-microphone-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Test mikrofonu'), findsOneWidget);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(tester.state<NavigatorState>(find.byType(Navigator)), same(navigator));
    expect(find.text('Test mikrofonu'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
