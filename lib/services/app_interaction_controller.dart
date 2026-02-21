import 'package:flutter/material.dart';
import 'voice_controller.dart';
import 'tts_service.dart';
import 'language_service.dart';

enum ActiveFeature {
  dashboard,
  objectDetection,
  currencyDetection,
  imageSpeech,
  settings,
  none,
}

class AppInteractionController extends ChangeNotifier {
  ActiveFeature _activeFeature = ActiveFeature.dashboard;
  bool _isBusy = false;

  ActiveFeature get activeFeature => _activeFeature;
  bool get isBusy => _isBusy;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  VoidCallback? onDetectCommand;
  void Function(String)? onCommand;
  VoidCallback? onDisposeFeature;

  final VoiceController voiceController;
  final TtsService ttsService;
  final LanguageService languageService;

  AppInteractionController({
    required this.voiceController,
    required this.ttsService,
    required this.languageService,
  });

  void setActiveFeature(ActiveFeature feature) {
    _activeFeature = feature;
    _isBusy = false;
    onDetectCommand = null;
    onDisposeFeature = null;
    notifyListeners();
  }

  void registerFeatureCallbacks({
    VoidCallback? onDetect,
    void Function(String)? onCommand,
    VoidCallback? onDispose,
  }) {
    onDetectCommand = onDetect;
    this.onCommand = onCommand;
    onDisposeFeature = onDispose;
  }

  void unregisterFeature() {
    onDisposeFeature?.call();
    onDetectCommand = null;
    onCommand = null;
    onDisposeFeature = null;
  }

  void setBusy(bool busy) {
    if (_isBusy == busy) return;
    _isBusy = busy;
    notifyListeners();
  }

  Future<void> runExclusive(Future<void> Function() action) async {
    if (_isBusy) return;
    setBusy(true);
    await stopGlobalListening();
    try {
      await action();
    } finally {
      setBusy(false);
      if (_activeFeature != ActiveFeature.none) {
        startGlobalListening();
      }
    }
  }

  void startGlobalListening() {
    if (_isBusy || _activeFeature == ActiveFeature.none) return;
    String lang = languageService.currentLocale.languageCode;
    voiceController.startListening(
      languageCode: lang,
      onResult: _handleVoiceResult,
    );
  }

  Future<void> stopGlobalListening() async {
    await voiceController.stop();
  }

  Future<void> handleGlobalBack() async {
    if (_activeFeature == ActiveFeature.dashboard) return; // already there
    setBusy(true);
    await ttsService.stop();
    await stopGlobalListening();

    unregisterFeature();
    _activeFeature = ActiveFeature.dashboard;

    while (navigatorKey.currentState!.canPop()) {
      navigatorKey.currentState!.pop();
    }

    navigatorKey.currentState?.pushReplacementNamed('/dashboard');
    setBusy(false);
    startGlobalListening();
  }

  void _handleVoiceResult(String text) {
    if (_isBusy) return;
    debugPrint("AppInteractionController: Heard '$text'");
    String t = text.toLowerCase();

    // Global Back Trigger
    if (t.contains("back") ||
        t.contains("piche") ||
        t.contains("wapas") ||
        t.contains("maghe") ||
        t.contains("parat") ||
        t.contains("stop")) {
      handleGlobalBack();
      return;
    }

    if (_activeFeature == ActiveFeature.dashboard) {
      _routeDashboardCommand(t);
    } else {
      if (t.contains("detect") ||
          t.contains("scan") ||
          t.contains("capture") ||
          t.contains("dekho") ||
          t.contains("kya") ||
          t.contains("baga") ||
          t.contains("kay") ||
          t.contains("ओळखा") ||
          t.contains("पहचानो") ||
          t.contains("शोधा") ||
          t.contains("नोट") ||
          t.contains("coin") ||
          t.contains("rupee") ||
          t.contains("read") ||
          t.contains("वाचा") ||
          t.contains("text")) {
        onDetectCommand?.call();
      }
      onCommand?.call(t);
    }
  }

  Future<void> _routeDashboardCommand(String t) async {
    String route = '';
    String name = '';
    if (t.contains("object") ||
        t.contains("detection") ||
        t.contains("वस्तु") ||
        t.contains("ओळख") ||
        t.contains("बघा")) {
      route = '/object_detection';
      name = "Object Detection";
    } else if (t.contains("currency") ||
        t.contains("money") ||
        t.contains("check") ||
        t.contains("पैसे") ||
        t.contains("चलन") ||
        t.contains("रुपया") ||
        t.contains("तपास")) {
      route = '/currency_detection';
      name = "Currency Check";
    } else if (t.contains("read") ||
        t.contains("text") ||
        t.contains("speech") ||
        t.contains("image") ||
        t.contains("वाचा") ||
        t.contains("वाचन") ||
        t.contains("पुस्तक") ||
        t.contains("मजकूर")) {
      route = '/image_to_speech';
      name = "Text Reading";
    } else if (t.contains("settings") ||
        t.contains("option") ||
        t.contains("सेटिंग्स") ||
        t.contains("पर्याय")) {
      route = '/settings';
      name = "Settings";
    }

    if (route.isNotEmpty) {
      setBusy(
        true,
      ); // Don't use runExclusive directly for navigation or it might un-busy incorrectly
      await stopGlobalListening();
      String lang = languageService.currentLocale.languageCode;
      String confirm = "Opening $name";
      if (lang == 'hi') confirm = "$name खोल रहे हैं";
      if (lang == 'mr') confirm = "$name उघडत आहे";
      await ttsService.speak(confirm, languageCode: lang);
      navigatorKey.currentState?.pushNamed(route);
      // Once pushed, the init state of next screen handles feature registration
      setBusy(false);
    }
  }
}
