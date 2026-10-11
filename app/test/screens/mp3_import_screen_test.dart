import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/midi_recording_export.dart';
import 'package:learn_piano/src/screens/mp3_import_screen.dart';

class _AudioFileFake implements AudioFilePicker {
  DecodedAudioFile? selected;
  AudioFilePickException? failure;
  int picks = 0;

  @override
  Future<DecodedAudioFile?> pickAndDecode() async {
    picks++;
    if (failure case final e?) throw e;
    return selected;
  }
}

class _PreparableFileFake extends _AudioFileFake
    implements PreparableAudioFilePicker {
  final Completer<void> ready = Completer<void>();
  int preparations = 0;

  @override
  Future<void> prepare() {
    preparations++;
    return ready.future;
  }
}

class _RetryPickerFake extends _AudioFileFake
    implements PreparableAudioFilePicker {
  int preparations = 0;

  @override
  Future<void> prepare() async {
    preparations++;
    if (preparations == 1) {
      throw const AudioFilePickException('Nie załadowano modułu MP3.');
    }
  }
}

class _MidiExporterFake implements MidiRecordingExporter {
  Uint8List? saved;
  @override
  bool save(Uint8List data, String fileName) {
    saved = data;
    return true;
  }
}

DecodedAudioFile _shortNote() {
  final samples = Float32List.fromList(
    List<double>.generate(
      48000,
      (i) => i < 32000 ? 0.35 * math.sin(2 * math.pi * 440 * i / 48000) : 0,
    ),
  );
  return DecodedAudioFile(
    name: 'melody.mp3',
    samples: samples,
    sampleRate: 48000,
  );
}

void main() {
  testWidgets('file chooser stays disabled until the browser bridge is ready', (
    tester,
  ) async {
    final picker = _PreparableFileFake()..selected = _shortNote();
    await tester.pumpWidget(MaterialApp(home: Mp3ImportScreen(picker: picker)));
    expect(picker.preparations, 1);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('mp3-select'))).onPressed,
      isNull,
    );
    expect(picker.picks, 0);

    picker.ready.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('mp3-select'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('Rozpoznane nuty: 1'), findsOneWidget);
  });

  testWidgets('bridge load error offers retry instead of blaming MP3 file', (
    tester,
  ) async {
    final picker = _RetryPickerFake()..selected = _shortNote();
    await tester.pumpWidget(MaterialApp(home: Mp3ImportScreen(picker: picker)));
    await tester.pumpAndSettle();

    expect(find.text('Nie załadowano modułu MP3.'), findsOneWidget);
    expect(picker.picks, 0);
    expect(find.text('Ponów przygotowanie wyboru MP3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pumpAndSettle();
    expect(picker.preparations, 2);
    expect(find.text('Wybierz plik MP3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('Rozpoznane nuty: 1'), findsOneWidget);
  });


  testWidgets('selects MP3, recognizes notes and exports playable MIDI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final picker = _AudioFileFake()..selected = _shortNote();
    final exporter = _MidiExporterFake();
    await tester.pumpWidget(
      MaterialApp(
        home: Mp3ImportScreen(picker: picker, exporter: exporter),
      ),
    );
    expect(find.text('Rozpoznane nuty: 0'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('mp3-save')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pumpAndSettle();
    expect(picker.picks, 1);
    expect(find.text('Rozpoznane nuty: 1'), findsOneWidget);
    expect(find.textContaining('melody.mp3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mp3-save')));
    await tester.pump();
    expect(const MidiParser().parse(exporter.saved!).noteCount, 1);
  });

  testWidgets('cancel and decode errors remain recoverable', (tester) async {
    final picker = _AudioFileFake();
    await tester.pumpWidget(MaterialApp(home: Mp3ImportScreen(picker: picker)));
    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pump();
    expect(find.text('Rozpoznane nuty: 0'), findsOneWidget);
    picker.failure = const AudioFilePickException('Nie można dekodować MP3.');
    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pump();
    expect(find.text('Nie można dekodować MP3.'), findsOneWidget);
    picker.failure = null;
    picker.selected = _shortNote();
    await tester.tap(find.byKey(const Key('mp3-select')));
    await tester.pumpAndSettle();
    expect(find.text('Rozpoznane nuty: 1'), findsOneWidget);
  });
}
