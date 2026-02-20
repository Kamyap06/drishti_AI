//presentation/screens/language_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/voice_utils.dart'; // Unified Intents
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../widgets/mic_widget.dart';
import '../widgets/large_button.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({Key? key}) : super(key: key);

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String _statusToSpeak = "Welcome to Drishti. Please select your language. English, Hindi, or Marathi.";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakPrompt();
    });
  }

  Future<void> _speakPrompt() async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);
    
    // LOGICAL GATING: Mic stays active but ignores input
    voice.setSpeaking(true);
    
    // Speak prompt
    await tts.speakSequentially([
      {'text': "Welcome to Drishti. Please select your language. English, Hindi, or Marathi.", 'lang': 'en'},
    ]);
    
    // UNMUTE
    // Use delay to prevent catching own echo if TTS finishes abruptly
    await Future.delayed(const Duration(milliseconds: 1000));
    voice.setSpeaking(false);
    
    // Start Listening if not already (safeguard)
    if (mounted) {
       _startListening();
    }
  }

  void _startListening() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    
    // Single continuous session
    voice.startListening(
      languageCode: 'en-IN', // Start with English locale, can detect mixed usually
      continuous: true,
      onResult: (text) {
          if (!mounted) return;
          _handleVoiceInput(text);
      }
    );
  }

  void _handleVoiceInput(String text) {
    final voice = Provider.of<VoiceService>(context, listen:false);
    if (voice.isSpeaking) return;

     print("LANG DETECT RAW: $text");
     final intent = VoiceUtils.getIntent(text);
     print("LANG INTENT: $intent");

     if (intent == VoiceIntent.languageEnglish) {
       _selectLanguage(AppConstants.langEn);
     } else if (intent == VoiceIntent.languageHindi) {
       _selectLanguage(AppConstants.langHi); 
     } else if (intent == VoiceIntent.languageMarathi) {
       _selectLanguage(AppConstants.langMr);
     }
  }

  Future<void> _selectLanguage(String langCode) async {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final tts = Provider.of<TtsService>(context, listen: false);

    await voice.stopListening();
    await languageService.setLanguage(langCode);

    String confirmation = "Language selected.";
    if (langCode == AppConstants.langHi) confirmation = "भाषा चुनी गई (Language Selected)"; 
    if (langCode == AppConstants.langMr) confirmation = "भाषा निवडली (Language Selected)";

    await tts.speak(confirmation, languageCode: langCode);
    
    if (!mounted) return;
    // Clean Stop before changing screens/routes?
    // User requested "without VoiceService watchdogs or auto-restart triggers during route transitions"
    // So we invoke stopListening().
    await voice.stopListening(); 

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Language")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LargeButton(
              label: "English",
              onPressed: () => _selectLanguage(AppConstants.langEn),
            ),
            const SizedBox(height: 20),
            LargeButton(
              label: "हिंदी (Hindi)",
              onPressed: () => _selectLanguage(AppConstants.langHi),
            ),
            const SizedBox(height: 20),
            LargeButton(
              label: "मराठी (Marathi)",
              onPressed: () => _selectLanguage(AppConstants.langMr),
            ),
            const Spacer(),
            Consumer<VoiceService>(
              builder: (context, voice, child) {
                return MicWidget(
                  isListening: voice.isListening,
                  onTap: () {
                    if (voice.isListening) {
                       voice.stopListening();
                    } else {
                       _startListening();
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
