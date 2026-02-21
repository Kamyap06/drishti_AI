import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_controller.dart';
import '../widgets/mic_widget.dart';
import '../../services/app_interaction_controller.dart';
import '../../services/translation_manager.dart';
import '../../services/speech_formatter.dart';

class ImageToSpeechScreen extends StatefulWidget {
  const ImageToSpeechScreen({super.key});

  @override
  State<ImageToSpeechScreen> createState() => _ImageToSpeechScreenState();
}

class _ImageToSpeechScreenState extends State<ImageToSpeechScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  final TextRecognizer _textRecognizer = TextRecognizer();

  // Conversation State
  bool _askingToTranslate = false;
  String _lastExtractedText = "";
  String _detectedLangCode = "";
  List<String> _translationOptions = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final interaction = Provider.of<AppInteractionController>(
        context,
        listen: false,
      );
      interaction.setActiveFeature(ActiveFeature.imageSpeech);
      interaction.registerFeatureCallbacks(
        onDetect: _captureAndProcess,
        onCommand: _handleCustomVoiceCommand,
        onDispose: () {
          _controller?.dispose();
          _textRecognizer.close();
          TranslationManager().dispose();
        },
      );
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
      await tts.speak(SpeechFormatter.formatGreeting(lang), languageCode: lang);
    });
  }

  void _handleCustomVoiceCommand(String t) {
    if (_askingToTranslate) {
      if (t.contains("no") ||
          t.contains("nahi") ||
          t.contains("nako") ||
          t.contains("stop")) {
        _reset();
        return;
      }

      String? targetLang;
      if (t.contains("hindi")) {
        targetLang = 'hi';
      } else if (t.contains("marathi"))
        targetLang = 'mr';
      else if (t.contains("english"))
        targetLang = 'en';

      if (targetLang != null) {
        if (targetLang == _detectedLangCode) {
          _askingToTranslate = false;
          _reset();
        } else if (_translationOptions.contains(targetLang)) {
          _askingToTranslate = false;
          _handleTranslationRequest(targetLang);
        }
      } else if (t.contains("yes") || t.contains("haan") || t.contains("ho")) {
        // Ask for which language explicitly because they just said "yes"
        _askLanguage();
      }
    }
  }

  Future<void> _captureAndProcess() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing)
      return;

    final interaction = Provider.of<AppInteractionController>(
      context,
      listen: false,
    );

    await interaction.runExclusive(() async {
      setState(() => _isProcessing = true);
      final tts = Provider.of<TtsService>(context, listen: false);
      final lang = Provider.of<LanguageService>(
        context,
        listen: false,
      ).currentLocale.languageCode;

      await tts.speak(SpeechFormatter.formatScanning(lang), languageCode: lang);

      try {
        final image = await _controller!.takePicture();
        if (!mounted) return;
        final inputImage = InputImage.fromFilePath(image.path);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        if (!mounted) return;

        _lastExtractedText = recognizedText.text;

        if (_lastExtractedText.trim().isEmpty) {
          await tts.speak(
            SpeechFormatter.formatNoText(lang),
            languageCode: lang,
          );
          _reset();
        } else {
          // Detect Source Language
          _detectedLangCode = await TranslationManager().identifyLanguage(
            _lastExtractedText,
          );

          // Read detected text in its native language
          await tts.speak(_lastExtractedText, languageCode: _detectedLangCode);

          // Generate remaining options
          final allLangs = ['en', 'hi', 'mr'];
          _translationOptions = allLangs
              .where((l) => l != _detectedLangCode)
              .toList();

          // Ask for translation
          setState(() => _askingToTranslate = true);
          String prompt = SpeechFormatter.formatTranslationPrompt(
            _translationOptions,
            lang,
          );
          await tts.speak(prompt, languageCode: lang);
        }
      } catch (e) {
        debugPrint('OCR Error: $e');
        await tts.speak(SpeechFormatter.formatError(lang), languageCode: lang);
        _reset();
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    });
  }

  Future<void> _askLanguage() async {
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
      String prompt = SpeechFormatter.formatTranslationPrompt(
        _translationOptions,
        lang,
      );
      await tts.speak(prompt, languageCode: lang);
    });
  }

  Future<void> _handleTranslationRequest(String targetLangCode) async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final interaction = Provider.of<AppInteractionController>(
      context,
      listen: false,
    );

    await interaction.runExclusive(() async {
      setState(() => _isProcessing = true);
      try {
        final translated = await TranslationManager().translate(
          _lastExtractedText,
          _detectedLangCode,
          targetLangCode,
        );
        if (!mounted) return;
        await tts.speak(translated, languageCode: targetLangCode);
      } catch (e) {
        if (!mounted) return;
        final lang = Provider.of<LanguageService>(
          context,
          listen: false,
        ).currentLocale.languageCode;
        await tts.speak(SpeechFormatter.formatError(lang), languageCode: lang);
      } finally {
        if (mounted) setState(() => _isProcessing = false);
        _reset();
      }
    });
  }

  void _reset() {
    _askingToTranslate = false;
    _lastExtractedText = "";
    _detectedLangCode = "";
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
            bottom: 20,
            left: 0,
            right: 0,
            child: Consumer<AppInteractionController>(
              builder: (ctx, interaction, _) {
                final voice = Provider.of<VoiceController>(context);
                return MicWidget(
                  isListening: voice.isListening || interaction.isBusy,
                  onTap: () {
                    if (voice.isListening) {
                      interaction.stopGlobalListening();
                    } else {
                      interaction.startGlobalListening();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
