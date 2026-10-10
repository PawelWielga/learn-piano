import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/learn_piano_app.dart';

void main() {
  testWidgets('home opens the microphone preview', (tester) async {
    await tester.pumpWidget(const LearnPianoApp());

    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);
    expect(find.byKey(const Key('training-coming-soon')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-microphone-preview')));
    await tester.pumpAndSettle();

    expect(find.text('Tester mikrofonu jest w przygotowaniu'), findsOneWidget);

    await tester.tap(find.text('Wróć'));
    await tester.pumpAndSettle();

    expect(find.text('Ucz się na swoim pianinku'), findsOneWidget);
  });
}
