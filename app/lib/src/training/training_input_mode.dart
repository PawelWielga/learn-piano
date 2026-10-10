/// Exactly one source drives Wait for Note at a time, to avoid microphone
/// feedback from the on-screen synthesizer being counted as a second strike.
enum TrainingInputMode { microphone, keyboard }
