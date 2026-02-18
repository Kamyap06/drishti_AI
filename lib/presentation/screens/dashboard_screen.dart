//presentation/screen/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../widgets/mic_widget.dart';
import '../widgets/large_button.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isNavigating = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakOptions();
    });
  }

  Future<void> _speakOptions() async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    
    String prompt = "Please say a command. Object detection, currency check, read text, or settings.";
    if (lang == 'hi') prompt = "कृपया कमांड बोलें। वस्तु पहचान, पैसे की जांच, टेक्स्ट पढ़ना, या सेटिंग्स।";
    if (lang == 'mr') prompt = "कृपया कमांड सांगा. वस्तू ओळख, पैसे तपासणे, मजकूर वाचणे, किंवा सेटिंग्ज.";

    await tts.speak(prompt, languageCode: lang);
    _listenForCommand();
  }

  void _listenForCommand() {
    if (_isNavigating) return;
    
    final voice = Provider.of<VoiceService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;

    voice.startListening(
      languageCode: lang,
      onResult: (text) {
        if (_isNavigating) return;
        
        String t = text.toLowerCase();
        
        // 1. Object Detection Commands
        if (t.contains("object") || t.contains("detection") || 
            t.contains("वस्तु") || t.contains("ओळख") || t.contains("बघा")) {
          _navigateTo('/object_detection', "Object Detection");
        } 
        // 2. Currency Detection Commands
        else if (t.contains("currency") || t.contains("money") || t.contains("check") || 
                 t.contains("पैसे") || t.contains("चलन") || t.contains("रुपया") || t.contains("तपास")) {
          _navigateTo('/currency_detection', "Currency Check");
        } 
        // 3. Image to Speech Commands
        else if (t.contains("read") || t.contains("text") || t.contains("speech") || t.contains("image") || 
                 t.contains("वाचा") || t.contains("वाचन") || t.contains("पुस्तक") || t.contains("मजकूर")) {
          _navigateTo('/image_to_speech', "Text Reading");
        } 
        // 4. Settings Commands
        else if (t.contains("settings") || t.contains("option") || 
                 t.contains("सेटिंग्स") || t.contains("पर्याय")) {
          _navigateTo('/settings', "Settings");
        }
      },
    );
  }

  Future<void> _navigateTo(String route, String featureName) async {
    if (_isNavigating) return;

    setState(() => _isNavigating = true);
    
    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;

    await voice.stopListening();
    await tts.stop();

    String confirmation = "Opening $featureName.";
    if (lang == 'hi') {
      if (featureName.contains("Object")) confirmation = "वस्तु पहचान खोल रहे हैं।";
      else if (featureName.contains("Currency")) confirmation = "पैसे की जांच खोल रहे हैं।";
      else if (featureName.contains("Text")) confirmation = "टेक्स्ट पढ़ना खोल रहे हैं।";
      else confirmation = "$featureName खोल रहे हैं।";
    }
    if (lang == 'mr') {
      if (featureName.contains("Object")) confirmation = "वस्तू ओळख उघडत आहे.";
      else if (featureName.contains("Currency")) confirmation = "पैसे तपासणे उघडत आहे.";
      else if (featureName.contains("Text")) confirmation = "मजकूर वाचन उघडत आहे.";
      else confirmation = "$featureName उघडत आहे.";
    }

    await tts.speak(confirmation, languageCode: lang);

    if (!mounted) return;
    
    // Wait for the result of the navigation to resume listening when coming back
    await Navigator.pushNamed(context, route);
    
    // Resume listening when returning to dashboard
    if (mounted) {
      setState(() => _isNavigating = false);
      _speakOptions(); // Re-prompt when coming back
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Drishti", style: TextStyle(letterSpacing: 2)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF141E30), const Color(0xFF243B55)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                       Text(
                         "Welcome Back!",
                         style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                           color: Colors.white70,
                         ),
                       ),
                       const SizedBox(height: 20),
                       _buildGridCard(
                         context,
                         "Object\nDetection",
                         Icons.adf_scanner,
                         [Colors.blueAccent, Colors.cyanAccent],
                         () => Navigator.pushNamed(context, '/object_detection'),
                       ),
                       const SizedBox(height: 16),
                       _buildGridCard(
                         context,
                         "Currency\nCheck",
                         Icons.attach_money,
                         [Colors.green, Colors.tealAccent],
                         () => Navigator.pushNamed(context, '/currency_detection'),
                       ),
                       const SizedBox(height: 16),
                       _buildGridCard(
                         context,
                         "Read\nText",
                         Icons.text_fields,
                         [Colors.deepPurpleAccent, Colors.purpleAccent],
                         () => Navigator.pushNamed(context, '/image_to_speech'),
                       ),
                       const SizedBox(height: 16),
                       _buildGridCard(
                         context,
                         "Settings",
                         Icons.settings_suggest,
                         [Colors.orangeAccent, Colors.amber],
                         () => Navigator.pushNamed(context, '/settings'),
                       ),
                    ],
                  ),
                ),
              ),
              // Mic Area
              Container(
                 padding: const EdgeInsets.only(bottom: 40, top: 20),
                 child: Center(
                   child: Consumer<VoiceService>(
                    builder: (context, voice, child) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MicWidget(
                            isListening: voice.isListening,
                            onTap: () {
                               if (voice.isListening) voice.stopListening();
                               else _listenForCommand();
                            },
                          ),
                          const SizedBox(height: 15),
                          AnimatedOpacity(
                            opacity: voice.isListening ? 1.0 : 0.5,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              voice.isListening ? "Listening..." : "Tap to Speak",
                              style: const TextStyle(color: Colors.white, letterSpacing: 1.2),
                            ),
                          )
                        ],
                      );
                    },
                   ),
                 ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, String title, IconData icon, List<Color> gradients, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: gradients),
          boxShadow: [
            BoxShadow(color: gradients.first.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
          ],
        ),
        child: Stack(
           children: [
             Positioned(
               right: -20, bottom: -20,
               child: Icon(icon, size: 100, color: Colors.white.withOpacity(0.2)),
             ),
             Padding(
               padding: const EdgeInsets.all(24),
               child: Row(
                 children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 20, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.white,
                          letterSpacing: 1.1
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white70)
                 ],
               ),
             )
           ],
        ),
      ),
    );
  }
}
