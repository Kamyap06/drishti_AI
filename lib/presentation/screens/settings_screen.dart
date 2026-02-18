import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../../services/auth_service.dart'; // Make sure this exists or creates
import '../widgets/mic_widget.dart';
import '../widgets/large_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announce();
    });
  }

  Future<void> _announce() async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    await tts.speak("Settings. What would you like to do? Change Language or Log Out?", languageCode: lang);
    _listen();
  }

  void _listen() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final langService = Provider.of<LanguageService>(context, listen: false);
    
    voice.startListening(
      languageCode: langService.currentLocale.languageCode,
      onResult: (text) {
        // Run adaptive check first - REMOVED: Strict locking enforced
        // langService.checkAndAdaptLanguage(text);
        
        String t = text.toLowerCase();
        
        if (t.contains("change") && t.contains("language")) {
          // Identify which language
          if (t.contains("hindi")) {
            langService.setLanguage("hi");
            _speak("Language changed to Hindi", "hi");
          } else if (t.contains("marathi")) {
            langService.setLanguage("mr");
            _speak("Language changed to Marathi", "mr");
          } else if (t.contains("english")) {
            langService.setLanguage("en");
            _speak("Language changed to English", "en");
          } else {
             _speak("Which language? Hindi, Marathi, or English?", langService.currentLocale.languageCode);
          }
        } else if (t.contains("log") && t.contains("out")) {
          _speak("Logging out...", langService.currentLocale.languageCode);
          Provider.of<AuthService>(context, listen: false).logout(); 
          langService.clearLanguage();
          Navigator.pushNamedAndRemoveUntil(context, '/language', (route) => false);
        } else if (t.contains("back")) {

          Navigator.pop(context);
        }
      },
    );
  }
  
  Future<void> _speak(String text, String lang) async {
    await Provider.of<TtsService>(context, listen: false).speak(text, languageCode: lang);
  }

  @override
  Widget build(BuildContext context) {
    // Basic settings UI
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
             ListTile(
               title: const Text("Change Language"),
               trailing: const Icon(Icons.language),
               onTap: () {
                 // Show dialog? Or just cycle. 
                 // For now, maybe navigate to LanguageSelection to contain logic
                 Navigator.pushNamed(context, '/language_selection');
               },
             ),
             ListTile(
               title: const Text("Log Out"),
               trailing: const Icon(Icons.logout),
               onTap: () {
                 // Logic
                 Provider.of<AuthService>(context, listen: false).logout();
                 Provider.of<LanguageService>(context, listen: false).clearLanguage();
                 Navigator.pushNamedAndRemoveUntil(context, '/language', (route) => false);
               },

             ),
             const Spacer(),
             Consumer<VoiceService>(
               builder: (ctx, voice, _) => MicWidget(
                 isListening: voice.isListening,
                 onTap: () {
                   if(voice.isListening) voice.stopListening();
                   else _listen();
                 }
               )
             )
          ],
        ),
      ),
    );
  }
}
