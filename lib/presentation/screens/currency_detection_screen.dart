import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_service.dart';
import '../widgets/mic_widget.dart';
import 'dart:io';

class CurrencyDetectionScreen extends StatefulWidget {
  const CurrencyDetectionScreen({Key? key}) : super(key: key);

  @override
  State<CurrencyDetectionScreen> createState() => _CurrencyDetectionScreenState();
}

class _CurrencyDetectionScreenState extends State<CurrencyDetectionScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isNavigatingBack = false;
  final TextRecognizer _textRecognizer = TextRecognizer();

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
    final voice = Provider.of<VoiceService>(context, listen: false);
    await voice.stopListening();
    tts.speak("Detection started.", languageCode: lang);
    _listen();
  }

  void _listen() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final langService = Provider.of<LanguageService>(context, listen: false);
    
    voice.startListening(
      languageCode: langService.currentLocale.languageCode,
      continuous: true,
      onResult: (text) {
        print("CurrencyDetectionScreen: Heard: $text");
        // langService.checkAndAdaptLanguage(text); // REMOVED: Strict locking enforced
        String t = text.toLowerCase();
        if (t.contains("detect") || t.contains("scan")) {
           _captureAndProcess();
        } else if (t.contains("back") || 
                   t.contains("piche") || t.contains("wapas") || 
                   t.contains("maghe") || t.contains("parat")) {
           _handleBackCommand();
        }
      },
    );
  }

  Future<void> _handleBackCommand() async {
    if (_isNavigatingBack) return;
    
    setState(() {
      _isNavigatingBack = true;
      _isProcessing = false;
    });

    print("CurrencyDetectionScreen: Voice 'back' command detected. Cleaning up...");

    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);

    // 1. Halt all active pipelines
    await tts.stop();
    await voice.stopListening();
    
    // Stop camera if possible (Currency detection doesn't use stream, but we should dispose)
    // Actually, just dispose in the next step or stop any ongoing takePicture if possible
    
    // 2. Dispose resources
    _textRecognizer.close();
    _controller?.dispose();

    // 3. Hard navigation reset
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    final voice = Provider.of<VoiceService>(context, listen: false);
    await voice.stopListening();
    await tts.speak("Scanning...", languageCode: lang);

    try {
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      String result = _analyzeCurrency(recognizedText.text);
      
      await tts.speak(result, languageCode: lang);

    } catch (e) {
      await tts.speak("Error scanning.", languageCode: lang);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      _listen(); // Resume listening for next command
    }
  }

  String _analyzeCurrency(String text) {
    String t = text.toUpperCase();
    
    // Heuristic for Indian Currency
    bool isIndian = t.contains("RESERVE BANK OF INDIA") || t.contains("RUPEES") || t.contains("₹");
    
    // Numbers
    if (t.contains("2000")) return "₹2000 note detected.";
    if (t.contains("500")) return "₹500 note detected.";
    if (t.contains("200")) return "₹200 note detected.";
    if (t.contains("100")) return "₹100 note detected.";
    if (t.contains("50")) return "₹50 note detected.";
    if (t.contains("20")) return "₹20 note detected.";
    if (t.contains("10")) return "₹10 note detected.";
    
    if (isIndian) return "Indian currency detected but value unclear.";
    
    return "No valid currency detected.";
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Currency Detection"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SizedBox.expand(child: CameraPreview(_controller!)),
          // Pro Overlay
           Positioned.fill(
             child: Container(
               decoration: BoxDecoration(
                 gradient: LinearGradient(
                   begin: Alignment.topCenter,
                   end: Alignment.bottomCenter,
                   colors: [
                     Colors.black.withOpacity(0.6),
                     Colors.transparent,
                     Colors.transparent,
                     Colors.black.withOpacity(0.8)
                   ],
                   stops: const [0.0, 0.2, 0.7, 1.0],
                 )
               ),
             )
           ),
          if (_isProcessing) 
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
            ),
          Positioned(
             bottom: 40, left: 0, right: 0,
             child: Column(
               children: [
                 Consumer<VoiceService>(
                   builder: (ctx, voice, _) => MicWidget(
                     isListening: voice.isListening || _isProcessing, 
                     onTap: _listen
                   )
                 ),
                 const SizedBox(height: 20),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                   decoration: BoxDecoration(
                     color: Colors.black.withOpacity(0.6),
                     borderRadius: BorderRadius.circular(30),
                     border: Border.all(color: Colors.cyanAccent.withOpacity(0.5))
                   ),
                   child: const Text(
                     "Say 'Detect' to scan",
                     style: TextStyle(color: Colors.white, fontSize: 16),
                   ),
                 )
               ],
             )
          )
        ],
      ),
    );
  }
}
