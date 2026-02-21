import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_controller.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../widgets/mic_widget.dart';
import '../../core/voice_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum AuthMode { login, register }

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final BiometricService _biometricService = BiometricService();

  // Login Steps: 0=User, 1=Pass, 2=Biometric
  int _step = 0;
  final AuthMode _mode = AuthMode.login;
  bool _isSpeaking = false;
  bool _biometricAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initVoiceFlow();
    });
  }

  void _initVoiceFlow() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    if (!mounted) return;
    _speakPromptForStep();
    _startPersistentListening();
  }

  void _startPersistentListening() {
    final voice = Provider.of<VoiceController>(context, listen: false);
    final lang = Provider.of<LanguageService>(
      context,
      listen: false,
    ).currentLocale.languageCode;

    voice.startListening(
      languageCode: lang,
      onResult: (text) {
        if (!voice.isTtsSpeaking && !_isSpeaking) {
          _handleVoiceInput(text);
        }
      },
    );
  }

  Future<void> _speakPrompt(String message, String lang) async {
    if (!mounted) return;
    final voice = Provider.of<VoiceController>(context, listen: false);

    // Use VoiceGuard to handle mic lifecycle
    await voice.speakWithGuard(
      message, 
      lang,
      onResult: (text) => _handleVoiceInput(text),
    );
  }

  Future<void> _speakPromptForStep() async {
    if (!mounted) return;

    final lang = Provider.of<LanguageService>(
      context,
      listen: false,
    ).currentLocale.languageCode;
    String prompt = "";

    if (_mode == AuthMode.login) {
      if (_step == 0) {
        prompt =
            "Please say your Username to login, or say 'Register' to create an account.";
        if (lang == 'hi')
          prompt =
              "लॉगिन करने के लिए अपना Username बोलें, या अकाउंट बनाने के लिए 'Register' बोलें।";
        if (lang == 'mr')
          prompt =
              "लॉगिन करण्यासाठी आपले Username बोला, किंवा खाते तयार करण्यासाठी 'Register' म्हणा.";
      } else if (_step == 1) {
        prompt = "Please say your Password.";
        if (lang == 'hi') prompt = "कृपया अपना Password बोलें।";
        if (lang == 'mr') prompt = "कृपया आपला Password बोला.";
      } else if (_step == 2) {
        prompt = "Please authenticate with biometrics to complete login.";
        if (lang == 'hi')
          prompt =
              "लॉगिन पूरा करने के लिए कृपया बायोमेट्रिक्स के साथ प्रमाणित करें।";
        if (lang == 'mr')
          prompt = "लॉगिन पूर्ण करण्यासाठी कृपया बायोमेट्रिक्ससह प्रमाणित करा.";
      }
    } else if (_mode == AuthMode.register) {
      prompt = "No users found. Redirecting to registration.";
    }

    await _speakPrompt(prompt, lang);

    if (_mode == AuthMode.register) {
      Navigator.pushNamed(context, '/registration');
      return;
    }

    // Trigger biometric
    if (_mode == AuthMode.login && _step == 2 && mounted) {
      final voice = Provider.of<VoiceController>(context, listen: false);
      
      // Wait for TTS to finish
      while (voice.isTtsSpeaking && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (!mounted) return;
      await voice.stop(); // Ensure stopped for biometrics

      bool authenticated = await _biometricService.authenticate();
      if (mounted) {
        if (authenticated) {
          setState(() {
            _biometricAuthenticated = true;
          });
          _processLogin();
        } else {
          await _speakPrompt(
            "Biometric authentication failed. Please try again.",
            lang,
          );
          _speakPromptForStep();
        }
      }
    }
  }

  void _handleVoiceInput(String text) async {
    text = VoiceUtils.normalizeToEnglish(
      text,
    ); // Apply universal normalization early
    String input = text.toLowerCase();
    if (input.isEmpty) return;

    // Use unified intent mapping
    final intent = VoiceUtils.getIntent(text);
    print("LoginIntent: $intent (Input: $text)");

    // Global Navigation
    if (intent == VoiceIntent.back) {
      if (_step > 0) {
        setState(() {
          _step--;
          if (_step == 0) {
            _passwordController.clear();
            _biometricAuthenticated = false;
          }
        });
        _speakPromptForStep();
      }
      return;
    }

    if (intent == VoiceIntent.repeat) {
      _speakPromptForStep();
      return;
    }

    // Register switch
    if (intent == VoiceIntent.register && _step == 0) {
      await Navigator.pushNamed(context, '/registration');
      // Initialize context again upon return if needed
      _checkInitialState();
      return;
    }

    // Logic per step
    if (_mode == AuthMode.login) {
      if (_step == 0) {
        // If intents match "login", ignore. User is saying username.
        if (intent == VoiceIntent.login) return;

        setState(() {
          _usernameController.text = text; // Sanitized by early _normalizeInput
          _step = 1;
        });
        _speakPromptForStep();
      } else if (_step == 1) {
        // Password input
        String pass = text; // Sanitized by early _normalizeInput
        setState(() {
          _passwordController.text = pass;
          _step = 2; // Move to biometric
          // Trigger biometrics immediately after step update?
          // Yes, _speakPromptForStep handles it.
        });
        _speakPromptForStep();
      }
    }
  }

  Future<void> _processLogin() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final voice = Provider.of<VoiceController>(context, listen: false);
    final lang = Provider.of<LanguageService>(
      context,
      listen: false,
    ).currentLocale.languageCode;

    // Speak status
    await _speakPrompt("Checking credentials...", lang);

    // At this point voice is RESUMED by _speakPrompt, which might be risky if we navigate immediately.
    // However, navigation usually disposes the screen/service listeners.
    // For strictness, let's pause before async work if we want.
    // But "Checking credentials" is short.

    final success = await auth.login(
      _usernameController.text,
      _passwordController.text,
    );

    if (success) {
      await voice.stop(); // Clean stop before nav

      String msg = "Login successful.";
      if (lang == 'hi') msg = "लॉगिन सफल (Login Successful).";
      if (lang == 'mr') msg = "लॉगिन यशस्वी (Login Successful).";

      // Direct speak (VoiceGuard logic not needed as we are leaving)
      final tts = Provider.of<TtsService>(context, listen: false);
      await tts.speak(msg, languageCode: lang);

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
    } else {
      String error = "Login failed. Invalid username or password.";
      if (lang == 'hi') error = "लॉगिन विफल। अमान्य Username या Password.";
      if (lang == 'mr')
        error = "लॉगिन अयशस्वी. अमान्य Username किंवा Password.";

      // Use Guard for retry prompt
      await _speakPrompt(error, lang);

      setState(() {
        _step = 0; // Reset
        _passwordController.clear();
        _biometricAuthenticated = false;
      });
      _speakPromptForStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (_step >= 0)
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 24),
              ),
            const SizedBox(height: 16),
            if (_step >= 1)
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                style: const TextStyle(fontSize: 24),
              ),
            if (_step == 2)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fingerprint, size: 80, color: Colors.blue),
                    const SizedBox(height: 20),
                    Text(
                      _biometricAuthenticated
                          ? "Authenticated"
                          : "Waiting for Biometrics...",
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            if (_step < 2) const Spacer(),

            if (_step < 2)
              Consumer<VoiceController>(
                builder: (context, voice, child) {
                  return MicWidget(
                    isListening: (voice.isListening && !_isSpeaking),
                    onTap: () {
                      // no-op or force restart?
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
