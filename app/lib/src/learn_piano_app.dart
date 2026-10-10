import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class LearnPianoApp extends StatelessWidget {
  const LearnPianoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learn Piano',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087E77),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
