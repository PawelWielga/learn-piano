import 'dart:convert';
import 'dart:typed_data';

List<int> _int16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _int32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

List<int> variableLength(int value) {
  if (value < 0 || value > 0x0FFFFFFF) {
    throw ArgumentError.value(value, 'value');
  }
  final result = [value & 0x7F];
  var rest = value >> 7;
  while (rest > 0) {
    result.insert(0, (rest & 0x7F) | 0x80);
    rest >>= 7;
  }
  return result;
}

List<int> event(int delta, List<int> message) => [
  ...variableLength(delta),
  ...message,
];

List<int> endOfTrack([int delta = 0]) => event(delta, [0xFF, 0x2F, 0]);

List<int> tempo(int delta, int microsecondsPerBeat) => event(delta, [
  0xFF,
  0x51,
  3,
  (microsecondsPerBeat >> 16) & 0xFF,
  (microsecondsPerBeat >> 8) & 0xFF,
  microsecondsPerBeat & 0xFF,
]);

List<int> trackName(String name) {
  final bytes = utf8.encode(name);
  return event(0, [0xFF, 0x03, ...variableLength(bytes.length), ...bytes]);
}

List<int> trackBytes(List<List<int>> events) => [
  for (final value in events) ...value,
];

Uint8List midiFixture({
  required int format,
  required List<List<int>> tracks,
  int ppq = 480,
}) {
  final bytes = <int>[
    ...ascii.encode('MThd'),
    ..._int32(6),
    ..._int16(format),
    ..._int16(tracks.length),
    ..._int16(ppq),
  ];
  for (final events in tracks) {
    bytes.addAll(ascii.encode('MTrk'));
    bytes.addAll(_int32(events.length));
    bytes.addAll(events);
  }
  return Uint8List.fromList(bytes);
}
