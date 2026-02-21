import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import 'tts_service.dart';

class VoiceController with ChangeNotifier {
  static final VoiceController _instance = VoiceController._internal();
  factory VoiceController() => _instance;
  VoiceController._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  bool _isInitializing = false;
  DateTime? _lastListenTime;
  String _currentLocaleId = 'en_IN';
  Function(String)? _onResultCallback;
  TtsService? _ttsService;

  bool _isTtsSpeaking = false;

  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;
  bool get isTtsSpeaking => _isTtsSpeaking;

  void setTtsService(TtsService tts) {
    _ttsService = tts;
    _ttsService?.setCompletionHandler(() {
      debugPrint('VoiceController: TTS Completed');
      _isTtsSpeaking = false;
      notifyListeners();
      
      // If we were waiting for TTS to finish to resume listening
      if (_onResultCallback != null) {
        startListening(
          onResult: _onResultCallback!,
          languageCode: _currentLocaleId.substring(0, 2), // Simplistic map back
        );
      }
    });
  }

  Future<bool> init() async {
    if (_isAvailable) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    try {
      _isAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('VoiceController: Error: $error');
          _isListening = false;
          notifyListeners();
        },
        onStatus: (status) {
          debugPrint('VoiceController: Status: $status');
          if (status == 'listening') {
            _isListening = true;
          } else {
            _isListening = false;
          }
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('VoiceController: Init exception: $e');
      _isAvailable = false;
    } finally {
      _isInitializing = false;
    }
    return _isAvailable;
  }

  Future<void> startListening({
    required Function(String) onResult,
    required String languageCode,
  }) async {
    // 0. Prevent mic if TTS is active
    if (_isTtsSpeaking) {
      debugPrint('VoiceController: Cannot start listening while TTS is speaking');
      _onResultCallback = onResult; // Store it for completion handler
      return;
    }

    // 1. Debounce rapid sequential triggers
    final now = DateTime.now();
    if (_lastListenTime != null && 
        now.difference(_lastListenTime!) < const Duration(milliseconds: 500)) {
      debugPrint('VoiceController: Debouncing rapid listen request');
      return;
    }
    _lastListenTime = now;

    // 2. Safe permission & availability check
    if (!_isAvailable) {
      bool initialized = await init();
      if (!initialized) {
        debugPrint('VoiceController: Cannot start - not available');
        return;
      }
    }

    var status = await Permission.microphone.status;
    if (status.isDenied) {
      debugPrint('VoiceController: Microphone permission denied. Requesting...');
      status = await Permission.microphone.request();
      if (!status.isGranted) return;
    }

    if (_isListening) {
      debugPrint('VoiceController: Already listening, ignoring request.');
      return;
    }

    _onResultCallback = onResult;
    _currentLocaleId = AppConstants.ttsLocales[languageCode] ?? 'en_IN';

    // 3. Force stop TTS if we are manually starting (rare if Guard is used)
    if (_ttsService != null) {
      await _ttsService!.stop();
      _isTtsSpeaking = false;
    }

    // 4. Short delay for audio focus release
    await Future.delayed(const Duration(milliseconds: 250));

    // 5. Start recognition
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            debugPrint('VoiceController: Heard Final: ${result.recognizedWords}');
            Future.microtask(() => _onResultCallback?.call(result.recognizedWords));
          }
        },
        localeId: _currentLocaleId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        cancelOnError: false,
        partialResults: false,
      );
    } catch (e) {
      debugPrint('VoiceController: Listen Error: $e');
    }
  }

  Future<void> stop() async {
    if (!_isListening) return;
    debugPrint('VoiceController: Stopping...');
    await _speech.stop();
    _isListening = false;
    notifyListeners();
  }

  Future<void> cancel() async {
    debugPrint('VoiceController: Cancelling...');
    await _speech.cancel();
    _isListening = false;
    notifyListeners();
  }

  Future<void> speakWithGuard(
    String text,
    String languageCode,
    {Function(String)? onResult}
  ) async {
    if (_ttsService == null) {
      debugPrint('VoiceController: Cannot speakWithGuard - TtsService not set');
      return;
    }

    debugPrint("VoiceController: speakWithGuard starting for '$text'");
    
    // 1. Stop current listening
    await stop();

    // 2. Set speaking flag
    _isTtsSpeaking = true;
    if (onResult != null) {
      _onResultCallback = onResult;
    }
    notifyListeners();

    // 3. Speak - TTS Completion handler will trigger resumption
    await _ttsService!.speak(text, languageCode: languageCode);
  }

  void setSpeaking(bool speaking) {
    if (speaking) {
      stop();
      _isTtsSpeaking = true;
    } else {
      _isTtsSpeaking = false;
    }
    notifyListeners();
  }
}
