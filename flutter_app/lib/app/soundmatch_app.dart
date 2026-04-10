import 'package:flutter/material.dart';

import '../controller/music_recognition_controller.dart';
import '../presentation/home_page.dart';

class SoundMatchApp extends StatelessWidget {
  const SoundMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoundMatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF8C42),
          secondary: Color(0xFF25D366),
          surface: Color(0xFF151821),
        ),
        scaffoldBackgroundColor: const Color(0xFF111318),
        useMaterial3: true,
      ),
      home: HomePage(controller: MusicRecognitionController()),
    );
  }
}
