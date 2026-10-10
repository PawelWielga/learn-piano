import 'package:flutter/material.dart';

class MicrophonePreviewScreen extends StatelessWidget {
  const MicrophonePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test mikrofonu')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic_none,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tester mikrofonu jest w przygotowaniu',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tutaj sprawdzisz pojedyncze nuty z fizycznego '
                    'instrumentu. Ta wersja jeszcze nie prosi o '
                    'dostęp do mikrofonu.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Wróć'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
