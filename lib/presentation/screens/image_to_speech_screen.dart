import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../widgets/mic_widget.dart';
import 'dart:io';

class ImageToSpeechScreen extends StatefulWidget {
  const ImageToSpeechScreen({Key? key}) : super(key: key);

  @override
  State<ImageToSpeechScreen> createState() => _ImageToSpeechScreenState();
}

class _ImageToSpeechScreenState extends State<ImageToSpeechScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isNavigatingBack = false;
  final TextRecognizer _textRecognizer = TextRecognizer();
  
  // Conversation State
  bool _askingToTranslate = false;
  bool _askingLanguage = false;
  String _lastExtractedText = "";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announce();
    });
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    _controller = CameraController(
      firstCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _announce() async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    await tts.speak("Image to Speech. Say Detect to read text.", languageCode: lang);
    _listen();
  }

  void _listen() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final langService = Provider.of<LanguageService>(context, listen: false);
    
    voice.startListening(
      languageCode: langService.currentLocale.languageCode,
      continuous: true,
      onResult: (text) {
        print("ImageToSpeechScreen: Heard: $text");
        // langService.checkAndAdaptLanguage(text); // REMOVED: Strict locking enforced
        String t = text.toLowerCase();
        
        if (t.contains("back") || 
            t.contains("piche") || t.contains("wapas") || 
            t.contains("maghe") || t.contains("parat")) {
          _handleBackCommand();
          return;
        }

        if (_askingToTranslate) {
          if (t.contains("yes") || t.contains("haan") || t.contains("ho")) {
            _askingToTranslate = false;
            _askingLanguage = true;
            _askLanguage();
          } else if (t.contains("no") || t.contains("nahi")) {
             _askingToTranslate = false;
             _reset();
          }
        } else if (_askingLanguage) {
             _handleTranslationRequest(t);
        } else {
             if (t.contains("detect") || t.contains("read")) {
               _captureAndProcess();
             }
        }
      },
    );
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    setState(() => _isProcessing = true);
    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    
    await voice.stopListening();
    await tts.speak("Reading...", languageCode: lang);

    try {
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      _lastExtractedText = recognizedText.text;
      
      if (_lastExtractedText.isEmpty) {
        await tts.speak("No text found.", languageCode: lang);
        _reset();
      } else {
        await tts.speak("Captured text: " + _lastExtractedText, languageCode: lang);
        
        setState(() => _askingToTranslate = true);
        await tts.speak("Do you want to translate this text?", languageCode: lang);
        _listen();
      }

    } catch (e) {
      await tts.speak("Error processing.", languageCode: lang);
      _reset();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _askLanguage() async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    await tts.speak("Which language? Hindi or Marathi?", languageCode: lang);
    _listen();
  }

  Future<void> _handleTranslationRequest(String text) async {
     final tts = Provider.of<TtsService>(context, listen: false);
     TranslateLanguage target = TranslateLanguage.hindi;
     String t = text.toLowerCase();
     String langCode = 'hi';

     if (t.contains("marathi")) {
       target = TranslateLanguage.marathi;
       langCode = 'mr';
     } else if (t.contains("english")) { // Edge case
       target = TranslateLanguage.english;
       langCode = 'en';
     }

     final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english, 
        targetLanguage: target
     );
     
     final translated = await translator.translateText(_lastExtractedText);
     await translator.close();
     
     await tts.speak(translated, languageCode: langCode);
     _reset();
  }

  void _handleBackCommand() async {
    if (_isNavigatingBack) return;
    
    setState(() {
      _isNavigatingBack = true;
      _isProcessing = false;
    });

    print("ImageToSpeechScreen: Voice 'back' command detected. Cleaning up...");

    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);

    // 1. Halt all active pipelines
    await tts.stop();
    await voice.stopListening();
    
    // 2. Dispose resources
    _textRecognizer.close();
    _controller?.dispose();

    // 3. Hard navigation reset
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  void _reset() {
    _askingToTranslate = false;
    _askingLanguage = false;
    _lastExtractedText = "";
    _listen();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Scan Text")),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          if (_isProcessing) const Center(child: CircularProgressIndicator()),
          Positioned(
             bottom: 20, left: 0, right: 0,
             child: Consumer<VoiceService>(
               builder: (ctx, voice, _) => MicWidget(
                 isListening: voice.isListening || _isProcessing,
                 onTap: _listen
               )
             )
          )
        ],
      ),
    );
  }
}
