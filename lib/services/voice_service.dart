import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'dart:async';
import '../core/constants.dart';
import 'package:flutter/foundation.dart';

class VoiceService with ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  bool _isPaused = false;
  bool _continuousMode = false;
  
  // Stored config for auto-restart
  String _currentLanguageCode = 'en';
  Function(String)? _onResultCallback;
  bool _isSpeaking = false; // VoiceGuard State
  Timer? _watchdogTimer;
  final List<String> _intentQueue = [];

  // Initialize STT
  Future<bool> init() async {
    if (_isAvailable) return true;
    
    try {
      _isAvailable = await _speechToText.initialize(
        onError: (error) {
          print('STT: Error: $error');
          // Don't auto-restart immediately on error to avoid rapid loops
          _isListening = false;
          notifyListeners();
          if (_continuousMode && !_isPaused) {
             _scheduleRestart();
          }
        },
        onStatus: (status) {
          print('STT: Status: $status');
          if (status == 'listening') {
            _isListening = true;
          } else if (status == 'notListening' || status == 'done') {
            _isListening = false;
             if (_continuousMode && !_isPaused) {
               _scheduleRestart();
             }
          }
          notifyListeners();
        },
      );
    } catch (e) {
      print("STT Init Error: $e");
    }
    return _isAvailable;
  }

  void _scheduleRestart() {
    _watchdogTimer?.cancel();
    // Increase delay slightly to prevent tight loops
    _watchdogTimer = Timer(const Duration(seconds: 1), () {
      if (!_isListening && _continuousMode && !_isPaused) {
        _startListeningInternal();
      }
    });
  }

  Future<void> startListening({
    required Function(String) onResult,
    required String languageCode,
    bool continuous = true,
  }) async {
    if (!_isAvailable) {
      bool initialized = await init();
      if (!initialized) return;
    }

    _onResultCallback = onResult;
    _currentLanguageCode = languageCode;
    _continuousMode = continuous;
    
    // Reset pause state on explicit start
    _isPaused = false; 

    // Stop existing if any, then start fresh
    if (_isListening) {
      await _speechToText.stop(); 
      // The onStatus 'done' will trigger restart because _continuousMode is set
    } else {
      _startListeningInternal();
    }
  }

  Future<void> _startListeningInternal() async {
    if (_isPaused || _isListening) return;

    final localeId = AppConstants.ttsLocales[_currentLanguageCode] ?? 'en_US';
    print('STT: Starting session ($localeId)');

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          if (result.finalResult) {
            print('STT: Final: ${result.recognizedWords}');
            // LOGICAL GATING: Queue if speaking
            if (_isSpeaking) {
               print("STT: Queued result (Speaking): ${result.recognizedWords}");
               _intentQueue.add(result.recognizedWords);
            } else {
               _onResultCallback?.call(result.recognizedWords);
            }
          } 
          // Explicitly IGNORING partial results for stability as requested.
        },
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        cancelOnError: false,
        partialResults: false,
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          partialResults: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      print("STT Start Error: $e");
      _scheduleRestart(); // retry
    }
  }

  Future<void> stopListening() async {
    print('STT: Stop Called');
    _continuousMode = false;
    _isPaused = false; // Reset pause since we are fully stopping
    _watchdogTimer?.cancel();
    await _speechToText.stop();
    _isListening = false;
    notifyListeners();
  }

  Future<void> pause() async {
    print("STT: Pausing for external event");
    _isPaused = true;
    _watchdogTimer?.cancel(); // Critical: cancel restart timer
    if (_isListening) {
      await _speechToText.stop();
    }
    _isListening = false;
    notifyListeners();
  }

  Future<void> resume() async {
    print("STT: Resuming...");
    _isPaused = false;
    if (_continuousMode && !_isListening) {
      _startListeningInternal();
    }
  }
  
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

  /// VOICE GUARD: Prevents self-listening during TTS and flushes queued intents
  Future<void> speakWithGuard(dynamic ttsService, String text, String languageCode) async {
      print("VoiceGuard: Speaking '$text'");
      
      _isSpeaking = true;
      notifyListeners(); 
      
      // Pause listener to avoid capturing TTS audio
      await pause();
      
      // Speak
      await ttsService.speak(text, languageCode: languageCode);
      
      // Resume listener
      await resume();
      
      // Microtask delay to ensure recognition pipeline re-arms
      await Future.microtask(() {});
      
      print("VoiceGuard: Done speaking. Unmuting and flushing queue...");
      _isSpeaking = false;
      notifyListeners();
      
      if (_intentQueue.isNotEmpty) {
         print("VoiceGuard: Flushing ${_intentQueue.length} queued intents");
         final queue = List<String>.from(_intentQueue);
         _intentQueue.clear();
         for (var intentText in queue) {
            _onResultCallback?.call(intentText);
         }
      }
  }

  /// Manually set speaking state for external TTS usage (e.g. sequential prompt)
  void setSpeaking(bool speaking) {
    _isSpeaking = speaking;
    notifyListeners();
  }

}
