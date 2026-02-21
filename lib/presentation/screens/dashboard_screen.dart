//presentation/screen/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_controller.dart';
import '../widgets/mic_widget.dart';
import '../../services/app_interaction_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final interaction = Provider.of<AppInteractionController>(
        context,
        listen: false,
      );
      interaction.setActiveFeature(ActiveFeature.dashboard);
      _speakOptions();
    });
  }

  Future<void> _speakOptions() async {
    final interaction = Provider.of<AppInteractionController>(
      context,
      listen: false,
    );
    await interaction.runExclusive(() async {
      final tts = Provider.of<TtsService>(context, listen: false);
      final lang = Provider.of<LanguageService>(
        context,
        listen: false,
      ).currentLocale.languageCode;

      String prompt =
          "Please say a command. Object detection, currency check, read text, or settings.";
      if (lang == 'hi')
        prompt =
            "कृपया कमांड बोलें। वस्तु पहचान, पैसे की जांच, टेक्स्ट पढ़ना, या सेटिंग्स।";
      if (lang == 'mr')
        prompt =
            "कृपया कमांड सांगा. वस्तू ओळख, पैसे तपासणे, मजकूर वाचणे, किंवा सेटिंग्ज.";

      await tts.speak(prompt, languageCode: lang);
    });
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Welcome Back!",
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      _buildGridCard(
                        context,
                        "Object\nDetection",
                        Icons.adf_scanner,
                        [Colors.blueAccent, Colors.cyanAccent],
                        () =>
                            Provider.of<AppInteractionController>(
                              context,
                              listen: false,
                            ).navigatorKey.currentState?.pushNamed(
                              '/object_detection',
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildGridCard(
                        context,
                        "Currency\nCheck",
                        Icons.attach_money,
                        [Colors.green, Colors.tealAccent],
                        () =>
                            Provider.of<AppInteractionController>(
                              context,
                              listen: false,
                            ).navigatorKey.currentState?.pushNamed(
                              '/currency_detection',
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildGridCard(
                        context,
                        "Read\nText",
                        Icons.text_fields,
                        [Colors.deepPurpleAccent, Colors.purpleAccent],
                        () =>
                            Provider.of<AppInteractionController>(
                              context,
                              listen: false,
                            ).navigatorKey.currentState?.pushNamed(
                              '/image_to_speech',
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildGridCard(
                        context,
                        "Settings",
                        Icons.settings_suggest,
                        [Colors.orangeAccent, Colors.amber],
                        () => Provider.of<AppInteractionController>(
                          context,
                          listen: false,
                        ).navigatorKey.currentState?.pushNamed('/settings'),
                      ),
                    ],
                  ),
                ),
              ),
              // Mic Area
              Container(
                padding: const EdgeInsets.only(bottom: 40, top: 20),
                child: Center(
                  child: Consumer<AppInteractionController>(
                    builder: (context, interaction, child) {
                      final voice = Provider.of<VoiceController>(context);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MicWidget(
                            isListening:
                                voice.isListening || interaction.isBusy,
                            onTap: () {
                              if (voice.isListening) {
                                interaction.stopGlobalListening();
                              } else {
                                interaction.startGlobalListening();
                              }
                            },
                          ),
                          const SizedBox(height: 15),
                          AnimatedOpacity(
                            opacity: voice.isListening ? 1.0 : 0.5,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              voice.isListening
                                  ? "Listening..."
                                  : "Tap to Speak",
                              style: const TextStyle(
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    String title,
    IconData icon,
    List<Color> gradients,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: gradients),
          boxShadow: [
            BoxShadow(
              color: gradients.first.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                icon,
                size: 100,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
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
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white70),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
