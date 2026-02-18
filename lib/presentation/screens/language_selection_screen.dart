//presentation/screens/language_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
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
    
    // Speak sequentially with correct voice for each language
    await tts.speakSequentially([
      {'text': "Welcome to Drishti. Please select your language. English, Hindi, or Marathi.", 'lang': 'en'},
      {'text': "दृष्टि में आपका स्वागत है। कृपया अपनी भाषा चुनें। अंग्रेजी, हिंदी, या मराठी।", 'lang': 'hi'},
      {'text': "दृष्टीमध्ये आपले स्वागत आहे. कृपया आपली भाषा निवडा. इंग्रजी, हिंदी, किंवा मराठी।", 'lang': 'mr'},
    ]);
    
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final tts = Provider.of<TtsService>(context, listen: false);

    voice.startListening(
      languageCode: 'en', // Listen in English initially for lang selection
      onResult: (text) {
        String t = text.toLowerCase();
        if (t.contains("english") || t.contains("angrezi")) {
          _selectLanguage(AppConstants.langEn);
        } else if (t.contains("hindi") || t.contains("hindi") || t.contains("हिन्दी")) {
          _selectLanguage(AppConstants.langHi);
        } else if (t.contains("marathi") || t.contains("marathi") || t.contains("मराठी")) {
          _selectLanguage(AppConstants.langMr);
        }
      },
    );
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
