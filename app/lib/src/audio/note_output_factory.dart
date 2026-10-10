import 'note_output.dart';
import 'note_output_stub.dart'
    if (dart.library.js_interop) 'note_output_web.dart'
    as platform;

NoteOutput createNoteOutput() => platform.createNoteOutput();
