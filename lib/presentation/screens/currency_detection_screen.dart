import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_controller.dart';
import '../widgets/mic_widget.dart';
import '../../services/app_interaction_controller.dart';
import '../../services/currency_classifier_service.dart';

class CurrencyDetectionScreen extends StatefulWidget {
  const CurrencyDetectionScreen({super.key});

  @override
  State<CurrencyDetectionScreen> createState() =>
      _CurrencyDetectionScreenState();
}

class _CurrencyDetectionScreenState extends State<CurrencyDetectionScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  final bool _isNavigatingBack = false;
  final TextRecognizer _textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final interaction = Provider.of<AppInteractionController>(
        context,
        listen: false,
      );
      interaction.setActiveFeature(ActiveFeature.currencyDetection);
      interaction.registerFeatureCallbacks(onDetect: _captureAndProcess);
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
      await tts.speak(
        CurrencySpeechFormatter.formatGreeting(lang),
        languageCode: lang,
      );
    });
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

      await tts.speak(
        CurrencySpeechFormatter.formatScanning(lang),
        languageCode: lang,
      );

      try {
        final image = await _controller!.takePicture();
        final inputImage = InputImage.fromFilePath(image.path);
        final recognizedText = await _textRecognizer.processImage(inputImage);

        final pipeline = MultilingualCurrencyPipeline();
        final result = await pipeline.process(recognizedText.text, lang);

        String ttsMessage = CurrencySpeechFormatter.formatResult(result);

        await tts.speak(ttsMessage, languageCode: lang);
      } catch (e) {
        await tts.speak(
          CurrencySpeechFormatter.formatError(lang),
          languageCode: lang,
        );
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }); // runExclusive
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
                    Colors.black.withAlpha(153),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withAlpha(204),
                  ],
                  stops: const [0.0, 0.2, 0.7, 1.0],
                ),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Consumer<AppInteractionController>(
                  builder: (context, interaction, _) {
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
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(153),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.cyanAccent.withAlpha(128)),
                  ),
                  child: const Text(
                    "Say 'Detect' to scan",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
