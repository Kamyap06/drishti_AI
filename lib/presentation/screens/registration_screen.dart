import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart'; 
import '../widgets/mic_widget.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({Key? key}) : super(key: key);

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

enum RegStep { username, confirmUsername, password, biometric, confirmRegister, processing }

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final BiometricService _biometricService = BiometricService();
  
  RegStep _currentStep = RegStep.username;
  String _tempUsername = "";
  
  bool _isProcessing = false;
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
    // Initial delay to let TTS service be ready
    await Future.delayed(const Duration(milliseconds: 500));
    _speakPromptForStep();
    _startPersistentListening();
  }

  void _startPersistentListening() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;

    // Start listening once. The service handles restarts/watchdogs.
    voice.startListening(
      languageCode: lang,
      continuous: true,
      onResult: (text) {
        if (!_isSpeaking && !_isProcessing) {
           _handleVoiceInput(text);
        }
      },
    );
  }

  Future<void> _speakPrompt(String message, String lang) async {
    if (!mounted) return;
    setState(() { _isSpeaking = true; });

    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);

    // 1. Pause
    await voice.pause();

    // 2. Speak
    await tts.speak(message, languageCode: lang);
    
    // 3. Debounce
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() { _isSpeaking = false; });
      // 4. Resume
      await voice.resume();
    }
  }

  Future<void> _speakPromptForStep() async {
    if (!mounted) return;
    
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    String prompt = "";
    
    switch (_currentStep) {
      case RegStep.username:
        prompt = "Please say your desired Username.";
        if (lang == 'hi') prompt = "कृपया अपना वांछित Username बोलें।";
        if (lang == 'mr') prompt = "कृपया आपले इच्छित Username बोला.";
        break;
      case RegStep.confirmUsername:
        prompt = "You said $_tempUsername. Say 'Next' to confirm, or 'Retry' to change.";
        if (lang == 'hi') prompt = "आपने कहा $_tempUsername. पुष्टि के लिए 'Next' बोलें, या बदलने के लिए 'Retry' बोलें।";
        if (lang == 'mr') prompt = "तुम्ही म्हणालात $_tempUsername. पुष्टी करण्यासाठी 'Next' म्हणा, किंवा बदलण्यासाठी 'Retry' म्हणा.";
        break;
      case RegStep.password:
        prompt = "Please say your Password.";
        if (lang == 'hi') prompt = "कृपया अपना Password बोलें।";
        if (lang == 'mr') prompt = "कृपया आपला Password बोला.";
        break;
      case RegStep.biometric:
        prompt = "Please authenticate with your fingerprint or face to secure your account.";
        if (lang == 'hi') prompt = "अपने खाते को सुरक्षित करने के लिए कृपया अपने फिंगरप्रिंट या चेहरे से प्रमाणित करें।";
        if (lang == 'mr') prompt = "आपले खाते सुरक्षित करण्यासाठी कृपया आपल्या फिंगरप्रिंट किंवा चेहऱ्याने प्रमाणित करा.";
        break;
      case RegStep.confirmRegister:
        prompt = "All set. Say 'Register' to create your account, or 'Back' to start over.";
        if (lang == 'hi') prompt = "सब तैयार है। खाता बनाने के लिए 'Register' बोलें, या शुरू से शुरू करने के लिए 'Back' बोलें।";
        if (lang == 'mr') prompt = "सर्व सेट आहे. खाते तयार करण्यासाठी 'Register' म्हणा, किंवा पुन्हा सुरू करण्यासाठी 'Back' म्हणा.";
        break;
      case RegStep.processing:
        return; 
    }

    // Use shared helper
    await _speakPrompt(prompt, lang);

    // Trigger biometric automatically after speak
    if (_currentStep == RegStep.biometric && mounted) {
       final voice = Provider.of<VoiceService>(context, listen: false);
       await voice.pause(); // Ensure paused for biometrics
       
       bool params = await _biometricService.authenticate();
       
       if (mounted) {
         if (params) {
            final tts = Provider.of<TtsService>(context, listen: false);
            await tts.speak("Authentication successful.", languageCode: lang);
            setState(() {
              _biometricAuthenticated = true;
              _currentStep = RegStep.confirmRegister;
            });
            await voice.resume();
            _speakPromptForStep();
         } else {
            // Use helper for failure case to handle voice resume
            await _speakPrompt("Authentication failed. Retrying in 3 seconds.", lang);
            
            await Future.delayed(const Duration(seconds: 3));
            // _speakPrompt already resumed voice, but we might want to ensure it stays active or loop back
            _speakPromptForStep(); 
         }
       }
    }
  }

  void _handleVoiceInput(String text) async {
    String input = text.toLowerCase().trim();
    if (input.isEmpty) return;

    print("RegWizard: Input received: $input (Step: $_currentStep)");

    // Global navigation commands
    if (input.contains("back") || input.contains("piche") || input.contains("mage") || input.contains("parat") || input.contains("wapas")) {
        if (_currentStep == RegStep.username) {
           Navigator.pop(context); // Go back to Login
           return;
        }
        setState(() {
           // Simple back logic: go to start or previous logical block
           _currentStep = RegStep.username; 
           _usernameController.clear();
           _passwordController.clear();
           _biometricAuthenticated = false;
        });
        _speakPromptForStep();
        return;
    }
    
    if (input.contains("repeat") || input.contains("again") || input.contains("fir se") || input.contains("punha")) {
      _speakPromptForStep();
      return;
    }

    switch (_currentStep) {
      case RegStep.username:
         setState(() {
          _tempUsername = text; // Keep original case
          _usernameController.text = text;
          _currentStep = RegStep.confirmUsername;
        });
        _speakPromptForStep();
        break;

      case RegStep.confirmUsername:
        if (input.contains("next") || input.contains("yes") || input.contains("confirm") || input.contains("haan") || input.contains("ho")) {
          setState(() {
            _currentStep = RegStep.password;
          });
          _speakPromptForStep();
        } else if (input.contains("retry") || input.contains("change") || input.contains("no") || input.contains("nahi") || input.contains("nako")) {
          setState(() {
            _currentStep = RegStep.username;
            _usernameController.clear();
          });
          _speakPromptForStep();
        }
        break;

      case RegStep.password:
        // Accept anything as password, clean whitespace
        String pass = text.replaceAll(' ', '');
        setState(() {
          _passwordController.text = pass;
          _currentStep = RegStep.biometric; // Move to biometric
        });
        _speakPromptForStep();
        break;

      case RegStep.biometric:
        break;

      case RegStep.confirmRegister:
        if (input.contains("register") || input.contains("create") || input.contains("submit") || input.contains("khata") || input.contains("banva")) {
           setState(() {
             _currentStep = RegStep.processing;
             _isProcessing = true;
           });
           _performRegistration();
        } else if (input.contains("retry") || input.contains("change") || input.contains("badal")) {
           setState(() {
             _currentStep = RegStep.password;
             _passwordController.clear();
             _biometricAuthenticated = false;
           });
           _speakPromptForStep();
        }
        break;
        
      case RegStep.processing:
        break;
    }
  }

  Future<void> _performRegistration() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;

    bool exists = await auth.userExists(_usernameController.text);
    if (exists) {
       await _speakPrompt("Username already taken. Please say a different username.", lang);
       setState(() {
         _currentStep = RegStep.username;
         _isProcessing = false;
         _usernameController.clear();
       });
       // _speakPrompt resumes voice, so we can just wait for input
       return;
    }

    // Strict await for registration result
    bool success = await auth.register(
      _usernameController.text, 
      _passwordController.text
    );
    
    if (success) {
      await voice.stopListening();
      
      // Use direct speak here because we are leaving
      final tts = Provider.of<TtsService>(context, listen: false);
      await tts.speak("Registration successful. Please log in.", languageCode: lang);
      
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } else {
      await _speakPrompt("Registration failed. Please try again.", lang);
      setState(() {
         _currentStep = RegStep.username;
         _isProcessing = false;
         _usernameController.clear(); // Clear for retry
      });
      // Voice resumed by _speakPrompt
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Registration")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               _buildStepIndicator(),
               const SizedBox(height: 40),
               Text(
                 _getStepInstruction(),
                 textAlign: TextAlign.center,
                 style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
               ),
               const SizedBox(height: 20),
               if (_currentStep == RegStep.username || _currentStep == RegStep.confirmUsername)
                 Text(
                   _usernameController.text.isEmpty ? "..." : _usernameController.text,
                   style: const TextStyle(fontSize: 32, color: Colors.blue),
                 ),
               if (_currentStep == RegStep.password || _currentStep == RegStep.biometric || _currentStep == RegStep.confirmRegister)
                 Text(
                   _passwordController.text.isEmpty ? "..." : List.filled(_passwordController.text.length, "*").join(),
                   style: const TextStyle(fontSize: 32, color: Colors.blue),
                 ),
               if (_currentStep == RegStep.biometric)
                 const Icon(Icons.fingerprint, size: 80, color: Colors.green),
                 
               const SizedBox(height: 60),
               if (_isProcessing) const CircularProgressIndicator(),
               if (!_isProcessing)
                 Consumer<VoiceService>(
                    builder: (context, voice, child) {
                      return Icon(
                        (voice.isListening && !_isSpeaking) ? Icons.mic : Icons.mic_none,
                        size: 64,
                        color: (voice.isListening && !_isSpeaking) ? Colors.red : Colors.grey,
                      );
                    }
                 ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _getStepInstruction() {
    switch (_currentStep) {
      case RegStep.username: return "Speak Username";
      case RegStep.confirmUsername: return "Say 'Next' to confirm";
      case RegStep.password: return "Speak Password";
      case RegStep.biometric: return "Authenticate Biometrics";
      case RegStep.confirmRegister: return "Say 'Register' to finish";
      case RegStep.processing: return "Creating Account...";
    }
  }
  
  Widget _buildStepIndicator() {
     return Row(
       mainAxisAlignment: MainAxisAlignment.center,
       children: [
         _stepDot(RegStep.username),
         _stepLine(),
         _stepDot(RegStep.password),
         _stepLine(),
         _stepDot(RegStep.biometric),
         _stepLine(),
         _stepDot(RegStep.confirmRegister),
       ],
     );
  }
  
  Widget _stepDot(RegStep step) {
    bool active = _currentStep.index >= step.index;
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        color: active ? Colors.blue : Colors.grey[300],
        shape: BoxShape.circle,
      ),
    );
  }
  
  Widget _stepLine() {
    return Container(width: 40, height: 4, color: Colors.grey[300]);
  }
}
