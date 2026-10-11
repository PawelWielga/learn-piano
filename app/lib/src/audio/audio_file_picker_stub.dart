import 'audio_file_picker.dart';

AudioFilePicker createAudioFilePicker() => UnsupportedAudioFilePicker();

class UnsupportedAudioFilePicker implements AudioFilePicker {
  @override
  Future<DecodedAudioFile?> pickAndDecode() async {
    throw const AudioFilePickException(
      'Import MP3 nie jest dostępny na tej platformie.',
    );
  }
}
