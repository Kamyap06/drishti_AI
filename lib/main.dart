import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart'; // NEW
import 'core/theme.dart';
import 'services/language_service.dart';
import 'services/tts_service.dart';
import 'services/voice_service.dart';
import 'services/auth_service.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/language_selection_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/object_detection_screen.dart';
import 'presentation/screens/currency_detection_screen.dart';
import 'presentation/screens/image_to_speech_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/registration_screen.dart';

import 'presentation/screens/permissions_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // NEW
  
  final authService = AuthService();
  await authService.init();

  final languageService = LanguageService();
  await languageService.init();

  final ttsService = TtsService();
  await ttsService.init();

  final voiceService = VoiceService();
  await voiceService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: languageService),
        Provider.value(value: ttsService),
        ChangeNotifierProvider.value(value: voiceService),
        Provider.value(value: authService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drishti',
      theme: AppTheme.pTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/permissions': (context) => const PermissionsScreen(),
        '/language': (context) => const LanguageSelectionScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/object_detection': (context) => const ObjectDetectionScreen(),
        '/currency_detection': (context) => const CurrencyDetectionScreen(),
        '/image_to_speech': (context) => const ImageToSpeechScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/registration': (context) => const RegistrationScreen(),
      },
    );
  }
}
