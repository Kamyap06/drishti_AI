import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/tts_service.dart';
import '../../services/language_service.dart';
import '../../services/voice_service.dart';
import '../widgets/mic_widget.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'; // ML Kit Import

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({Key? key}) : super(key: key);

  @override
  State<ObjectDetectionScreen> createState() =>
      _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> {

  CameraController? _controller;
  Interpreter? _efficientDet;
  // Interpreter? _yolo; // Removed unused
  Interpreter? _yoloInterpreter;

  final int inputSize = 320;

  bool _isListening=false; // Controls Mic state only
  bool _triggerActiveScan=false; // One-shot trigger for full pipeline
  bool _canProcess=false;
  bool _isBusy=false;
  bool _isNavigatingBack = false;

  double _previousArea=0;
  DateTime _lastSpeakTime=DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWarningTime=DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0); // Throttle
  DateTime _lastMlKitRunTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  // Advanced Path Prediction State
  final List<_Detection> _detectionBuffer = []; // Buffer for smoothing
  final int _bufferSize = 6;
  double _currentApproachSpeed = 0.0; // Area change factor
 // Cooldown
  String _lastAnnouncedObject = "";
  String _lastAnnouncedDirection = "";
  int _lastAnnouncedSteps = 0;

  List<String> labels=[];

  // ML Kit Fallback
  ObjectDetector? _mlKitDetector;
  int _missedFrames = 0;
  static const int _kMissedFrameThreshold = 6;


  /// EfficientDet important objects (safety layer)
  final Set<String> importantObjects={
    "person","chair","bottle","laptop","cell phone","bench","backpack"
  };

  /// Your YOLO navigation classes
  final List<String> yoloLabels=[
    "gate","lift","stairs","corridor","building"
  ];

  /// 🔥 Adaptive Navigation Priority
  final Map<String,int> navigationPriority = {
    "stairs":5,
    "gate":4,
    "lift":3,
    "corridor":2,
    "building":1,
    };
    
    void _sortDetectionsAdaptive(List<_Detection> detections){
      
      detections.sort((a,b){

    // 1️⃣ Danger proximity ALWAYS highest
    bool aDanger = a.area > 0.42;
    bool bDanger = b.area > 0.42;

    if(aDanger != bDanger){
      return aDanger ? -1 : 1;
    }

    // 2️⃣ Navigation objects before normal objects
    if(a.isNavigation != b.isNavigation){
      return a.isNavigation ? -1 : 1;
    }

    // 3️⃣ If both navigation → apply priority ranking
    if(a.isNavigation && b.isNavigation){
      int pa = navigationPriority[a.label] ?? 0;
      int pb = navigationPriority[b.label] ?? 0;

      if(pa != pb){
        return pb.compareTo(pa);
      }
    }

    // 4️⃣ Fallback → closer object wins
    return b.area.compareTo(a.area);
  });
}



  @override
  void initState(){
    super.initState();
    _initializeCamera();
    _loadModels();
    _loadLabels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening(); // Auto-start listening
      _startPassiveDetection(); // Auto-start camera in passive mode
    });
  }

  /// ================= LOAD MODELS =================
  Future<void> _loadModels() async{
    _efficientDet = await Interpreter.fromAsset(
      "assets/models/efficientdet_lite0.tflite",
      options: InterpreterOptions()..threads=2,
    );

    // Initialize ML Kit Object Detector
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _mlKitDetector = ObjectDetector(options: options);
  }

  Future<void> _loadLabels() async{
    final data = await rootBundle.loadString('assets/models/labels.txt');
    labels = data.split('\n');

    // 2. YOLO Navigation Model
    _yoloInterpreter = await Interpreter.fromAsset(
      "assets/models/yolo_college.tflite",
      options: InterpreterOptions()..threads = 2,
    );
  }

  /// ================= CAMERA =================
  void _initializeCamera() async{
    final cameras=await availableCameras();
    _controller=CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio:false,
      imageFormatGroup:
      Platform.isAndroid?ImageFormatGroup.nv21:ImageFormatGroup.bgra8888,
    );
    await _controller!.initialize();
    if(mounted) setState((){});
  }

  void _startPassiveDetection(){
    if(_controller==null) return;

    setState(() {
      _canProcess=true;
    });

    _controller!.startImageStream((CameraImage image){
      if(_canProcess && !_isBusy){
        _isBusy=true;
        _runModels(image);
      }
    });
  }

  void _startListening() {
    setState(() => _isListening = true);
    _listenForVoiceCommands();
  }

  void _stopListening() {
     setState(() => _isListening = false);
     final voice = Provider.of<VoiceService>(context, listen: false);
     voice.stopListening();
  }

  
  void _listenForVoiceCommands() {
    if(!_isListening) return;

    final voice = Provider.of<VoiceService>(context, listen: false);
    final langService = Provider.of<LanguageService>(context, listen: false);
    
    voice.startListening(
      languageCode: langService.currentLocale.languageCode,
      continuous: true,
      onResult: (text) {
        if (_isNavigatingBack) return;
        
        String t = text.toLowerCase();
        
        // 1. Navigation Command
        if (t.contains("back") || 
            t.contains("piche") || t.contains("wapas") || 
            t.contains("maghe") || t.contains("parat")) {
           _handleBackCommand();
           return;
        }

        // 2. Active Scan Command (Detect/Capture/Scan)
        // Hindi: "dekho", "kya hai"
        // Marathi: "baga", "kay aahe"
        if (t.contains("detect") || t.contains("scan") || t.contains("capture") ||
            t.contains("dekho") || t.contains("kya hai") ||
            t.contains("baga") || t.contains("kay aahe")) {
            
            if(!_triggerActiveScan){
              debugPrint("OD: Voice trigger received: $text -> ACTIVE SCAN");
              _triggerActiveScan = true; 
              // Reset timestamps to force immediate run
               _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0); 
            }
        }
      },
    );
  }

  Future<void> _handleBackCommand() async {
    if (_isNavigatingBack) return;
    
    setState(() {
      _isNavigatingBack = true;
      _isListening = false;
      _canProcess = false;
    });

    print("ObjectDetectionScreen: Voice 'back' command detected. Cleaning up...");

    final tts = Provider.of<TtsService>(context, listen: false);
    final voice = Provider.of<VoiceService>(context, listen: false);

    // 1. Halt all active pipelines
    await tts.stop();
    await voice.stopListening();
    
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }

    // 2. Dispose interpreters to free resources
    _efficientDet?.close();

    _yoloInterpreter?.close();

    // 3. Hard navigation reset to dashboard
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  /// ================= PREPROCESS =================
  Float32List _convert(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final Float32List buffer = Float32List(inputSize * inputSize * 3);

    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;

      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      int index = 0;
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          int srcX = (x * width) ~/ inputSize;
          int srcY = (y * height) ~/ inputSize;

          int yIndex = srcY * image.planes[0].bytesPerRow + srcX;
          int uvX = srcX ~/ 2;
          int uvY = srcY ~/ 2;
          int uvIndex = uvY * uvRowStride + uvX * uvPixelStride;

          final yp = yPlane[yIndex];
          final up = uPlane[uvIndex] - 128;
          final vp = vPlane[uvIndex] - 128;

          int r = (yp + 1.370705 * vp).round().clamp(0, 255);
          int g = (yp - 0.337633 * up - 0.698001 * vp).round().clamp(0, 255);
          int b = (yp + 1.732446 * up).round().clamp(0, 255);

          buffer[index++] = r / 255.0;
          buffer[index++] = g / 255.0;
          buffer[index++] = b / 255.0;
        }
      }
    } else {
      final bytes = image.planes[0].bytes;
      int index = 0;
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          int srcX = (x * width) ~/ inputSize;
          int srcY = (y * height) ~/ inputSize;
          int i = srcY * image.planes[0].bytesPerRow + (srcX * 4);

          double bp = bytes[i] / 255.0;
          double gp = bytes[i + 1] / 255.0;
          double rp = bytes[i + 2] / 255.0;

          buffer[index++] = rp;
          buffer[index++] = gp;
          buffer[index++] = bp;
        }
      }
    }
    return buffer;
  }

  /// ================= MAIN PIPELINE =================
  Future<void> _runModels(CameraImage image) async{

    // Determine Mode
    bool isActiveMode = _triggerActiveScan;

    // THROTTLING LOGIC
    // Active Mode: Run immediately (skip throttle check or use very low throttle)
    // Passive Mode: Run at ~700ms interval
    
    int throttleMs = isActiveMode ? 0 : 700;
    
    if (DateTime.now().difference(_lastFrameTime).inMilliseconds < throttleMs) {
      _isBusy=false;
      return; 
    }
    _lastFrameTime = DateTime.now();

    // Debug: Frame received
    if(_canProcess && isActiveMode) debugPrint("OD: Active Scan Started");

    if(_efficientDet==null || _yoloInterpreter==null){ 
      _isBusy=false;
      return;
    }

    final Float32List flatBuffer = _convert(image);
    final reshapedInput = flatBuffer.reshape([1, inputSize, inputSize, 3]);

    final input = [reshapedInput]; 
    List<_Detection> detections=[];

    /// -------- LAYER 1: EfficientDet (Safety) - ALWAYS RUNS (Passive & Active) ----------
    // In passive mode, this is the ONLY model that runs.
    
    var edBoxes = List.generate(1, (_) =>
        List.generate(10, (_) => List.filled(4, 0.0)));
    var edClasses = List.generate(1, (_) => List.filled(10, 0.0));
    var edScores = List.generate(1, (_) => List.filled(10, 0.0));
    var edNum = List.filled(1,0.0);

    // Run inference
    _efficientDet!.runForMultipleInputs(
      input, 
      {0:edBoxes,1:edClasses,2:edScores,3:edNum},
    );

    // Parse EfficientDet
    for(int i=0;i<10;i++){
      double score=edScores[0][i];
      if(score<0.3) continue; // Lowered confidence threshold

      int idx=edClasses[0][i].toInt();
      String label=labels[min(idx,labels.length-1)]
          .trim()
          .toLowerCase();

      if(!importantObjects.contains(label)) continue;

      detections.add(_Detection(
        label:label,
        xmin:edBoxes[0][i][1], // xmin
        ymin:edBoxes[0][i][0], // ymin
        xmax:edBoxes[0][i][3], // xmax
        ymax:edBoxes[0][i][2], // ymax
        isNavigation:false, // Lower priority
      ));
    }

    /// -------- PASSIVE MODE CHECK ----------
    if (!isActiveMode) {
        // Passive mode still checks danger
        _checkProximitySafety(detections);

   // ALSO speak navigation using EfficientDet results
   if(detections.isNotEmpty){
    _sortDetectionsAdaptive(detections);
    final best = detections.first;
    _announce(best.label,best.area,best.centerX);
    }

       _isBusy = false;
       return; // Exit early, do not run YOLO/MLKit or Announce
    }


    /// -------- LAYER 2: YOLO (Navigation Landmarks) - ACTIVE MODE ONLY ----------
    if(_canProcess) debugPrint("OD: YOLO started (Active)");

    var yoloOutputTensor = _yoloInterpreter!.getOutputTensor(0);
    List<int> yoloShape = yoloOutputTensor.shape; 
    int numAnchors = yoloShape.length > 1 ? yoloShape[1] : 8400;
    int numFeatures = yoloShape.length > 2 ? yoloShape[2] : 10;

    var yoloOutput = List.generate(
        1, (_) => List.generate(numAnchors, (_) => List.filled(numFeatures, 0.0)));

    _yoloInterpreter!.run(reshapedInput, yoloOutput); 

    // Parse YOLO
    for(int i=0; i<numAnchors; i++){

      double obj=yoloOutput[0][i][4];
      if(obj<0.25) continue; // Temporarily lowered

      int bestClass=0;
      double bestScore=0;

      for(int c=0; c<yoloLabels.length && (5+c) < numFeatures; c++){
        if(yoloOutput[0][i][5+c]>bestScore){
          bestScore=yoloOutput[0][i][5+c];
          bestClass=c;
        }
      }

      if(bestScore*obj>0.25){

        double cx=yoloOutput[0][i][0];
        double cy=yoloOutput[0][i][1];
        double w=yoloOutput[0][i][2];
        double h=yoloOutput[0][i][3];

        detections.add(_Detection(
          label:yoloLabels[bestClass],
          xmin:cx-w/2,
          ymin:cy-h/2,
          xmax:cx+w/2,
          ymax:cy+h/2,
          isNavigation:true, // HIGHEST PRIORITY
        ));
      }
    }

    /// -------- LAYER 3: ML KIT FALLBACK (Safety) - ACTIVE MODE ONLY ----------
    // Only triggers if Primary Layers (1 & 2) failed to detect anything meaningful
    if (detections.isEmpty) {
      _missedFrames++;
      if (_missedFrames >= _kMissedFrameThreshold && _mlKitDetector != null && _controller != null) {
        
        // ML Kit Cooldown Check (800ms)
        if (DateTime.now().difference(_lastMlKitRunTime).inMilliseconds < 800) {
           if(_canProcess) debugPrint("OD: ML Kit skipped (cooldown)");
           // Do not reset missedFrames yet, wait for cooldown
           _isBusy = false;
           return;
        }
        _lastMlKitRunTime = DateTime.now();

        if(_canProcess) debugPrint("OD: ML Kit fallback triggered (after $_missedFrames missed frames)");

        try {
          final inputImage = _inputImageFromCameraImage(image);
          if (inputImage != null) {
            final mlObjects = await _mlKitDetector!.processImage(inputImage);
            
            if (mlObjects.isNotEmpty) {
              if(_canProcess) debugPrint("OD: ML Kit detection used. Found ${mlObjects.length} objects.");
              _missedFrames = 0; // Reset on success

              for (final obj in mlObjects) {
                 final double w = image.width.toDouble();
                 final double h = image.height.toDouble();
                 final rect = obj.boundingBox;

                 final String labelText = (obj.labels.isNotEmpty) ? obj.labels.first.text.toLowerCase() : "obstacle";
                 
                 // Normalize to 0-1
                 detections.add(_Detection(
                   label: labelText,
                   xmin: rect.left / w,
                   ymin: rect.top / h,
                   xmax: rect.right / w,
                   ymax: rect.bottom / h,
                   isNavigation: false, // Fallback is treated as generic safety object
                 ));
              }
            } else {
               if(_canProcess) debugPrint("OD: ML Kit found nothing.");
            }
          }
        } catch (e) {
          debugPrint("OD: ML Kit Error: $e");
        }
      }
    } else {
      _missedFrames = 0; // Reset as soon as primary models work
    }

    if(detections.isNotEmpty){

      // Sort: Navigation objects FIRST, then by Area (Closer/Bigger -> Better)
      detections.sort((a,b){
        if(a.isNavigation!=b.isNavigation){
          return a.isNavigation?-1:1; // True (Navigation) comes before False
        }
        return b.area.compareTo(a.area); // Descending area
      });

      final best=detections.first;
      
      // Update Trajectory & Smoothing
      _updateTrajectory(best);

      // Use smoothed values for announcement
      // Note: _updateTrajectory updates buffer. We should calculate smoothed values here.
      double smoothedArea = _calculateSmoothedArea();
      double smoothedCenterX = _calculateSmoothedCenterX();
      
      // DEBUG LOGGING
      if(_canProcess) {
          debugPrint("OD: Best: ${best.label} SmoothedArea: ${smoothedArea.toStringAsFixed(2)} Speed: ${_currentApproachSpeed.toStringAsFixed(3)}");
      }

      // Check for Predictive Stair Warning
      if (best.label == 'stairs' && _currentApproachSpeed > 0.02) { // Threshold for "Fast Approach"
          _announceWarning("Approaching Stairs");
      }

      _announce(best.label, smoothedArea, smoothedCenterX);
      
      // Reset trigger after successful announcement
      _triggerActiveScan = false;
      
    } else {
       // Clear buffer if tracking lost to prevent stale smoothing
       _detectionBuffer.clear();
       _currentApproachSpeed = 0.0;

       if(_canProcess) debugPrint("OD: No objects detected");
       // Keep trigger active? Or reset?
       // Usually reset after one cycle to prevent spam if nothing found.
       // But maybe we want to keep trying for a few frames?
       // Let's reset for now to enforce one-shot voice command -> one scan behaviour.
       _triggerActiveScan = false; 
    }

    _isBusy=false;
  }

  /// ================= PASSIVE SAFETY CHECK =================
  void _checkProximitySafety(List<_Detection> detections) async {
    if (detections.isEmpty) return;
    
    // Find closest object
    detections.sort((a,b) => b.area.compareTo(a.area));
    final closest = detections.first;

    if (closest.area > 0.45) { // Danger threshold
       if (DateTime.now().difference(_lastWarningTime).inMilliseconds > 2000) {
          HapticFeedback.heavyImpact();
          // Optional: Short warning beep or word?
          // Keeping it silent haptic or minimal for passive mode as requested "Passive safety detection... trigger haptic warnings"
          _lastWarningTime = DateTime.now();
          debugPrint("OD: Passive Safety Warning! ${closest.label} too close.");
       }
    }
  }

  /// ================= TRAJECTORY & SMOOTHING =================
  void _updateTrajectory(_Detection newDetection) {
     // 1. Add to buffer
     _detectionBuffer.add(newDetection);
     if (_detectionBuffer.length > _bufferSize) {
       _detectionBuffer.removeAt(0);
     }

     // 2. Calculate Speed (Area Growth Rate)
     if (_detectionBuffer.length >= 2) {
        // Compare current (end) vs oldest (start) in buffer
        double areaDiff = _detectionBuffer.last.area - _detectionBuffer.first.area;
        // Positive = Approaching, Negative = Leaving
        _currentApproachSpeed = areaDiff; 
     } else {
        _currentApproachSpeed = 0.0;
     }
  }

  double _calculateSmoothedArea() {
    if (_detectionBuffer.isEmpty) return 0.0;
    double totalArea = 0;
    double totalWeight = 0;
    for (int i = 0; i < _detectionBuffer.length; i++) {
       double weight = (i + 1).toDouble(); // Linear weighting (more recent = higher weight)
       totalArea += _detectionBuffer[i].area * weight;
       totalWeight += weight;
    }
    return totalArea / totalWeight;
  }

  double _calculateSmoothedCenterX() {
    if (_detectionBuffer.isEmpty) return 0.5;
    double totalX = 0;
    double totalWeight = 0;
    for (int i = 0; i < _detectionBuffer.length; i++) {
       double weight = (i + 1).toDouble();
       totalX += _detectionBuffer[i].centerX * weight;
       totalWeight += weight;
    }
    return totalX / totalWeight;
  }

  /// ================= VIRTUAL STICK ASSISTIVE NAVIGATION =================
  Future<void> _announceWarning(String message) async {
     HapticFeedback.heavyImpact();
     // Immediate priority speak
     final tts = Provider.of<TtsService>(context, listen: false);
     final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
     // Simple translation for "Stairs" or "Warning" if needed, 
     // but currently message is English.
     // Ideally should use localized strings.
     await tts.speak(message, languageCode: lang); 
  }

  void _announce(String label, double area, double centerX) async {
    final tts = Provider.of<TtsService>(context, listen: false);
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale.languageCode;

    final now = DateTime.now();

    // 1. Calculate 'Steps' distance (calibration: 0.4 area is ~1 step away)
    // Formula: As area gets smaller, steps increase. 
    // Very rough heuristic: steps = 4 / sqrt(area) - 2? 
    // Let's stick to the requested linear-ish logic or similar:
    // If area=0.4 -> very close (1 step or less).
    // If area=0.01 -> far (10+ steps).
    // Let's try: steps = round( (0.5 - area) * 20 ). 
    // if area=0.4 => 0.1*20 = 2 steps.
    // if area=0.1 => 0.4*20 = 8 steps.
    int steps = ((0.5 - area) * 15).round().clamp(1, 10);
    if(area > 0.45) steps = 0; // Immediate danger

    // 2. Calculate Direction
    String direction = "ahead";
    if (centerX < 0.4) direction = "left";
    else if (centerX > 0.6) direction = "right";

    // 3. Proximity Warning (High Priority)
    bool isDanger = area > 0.45;
    
    if (isDanger) {
      if (now.difference(_lastWarningTime).inMilliseconds > 2000) {
        _announceWarning("Warning! $label is very close. Step back.");
        debugPrint("OD: WARNING! $label too close!");

        String msgEn = "Warning! $label is very close. Step back.";
        String msgHi = "सावधान! $label बहुत पास है। पीछे हटें।";
        String msgMr = "सावधान! $label खूप जवळ आहे. मागे व्हा।";

        String msg = (lang == 'hi') ? msgHi : (lang == 'mr') ? msgMr : msgEn;
        
        // Priority speak (interrupts correctly)
        await tts.speak(msg, languageCode: lang); 
        
        _lastWarningTime = now;
        _lastSpeakTime = now; 
        return;
      }
    }

    // 4. Contextual Speech Intelligence & Motion-Aware Throttling
    // Calculate changes
    bool objectChanged = (label != _lastAnnouncedObject);
    bool directionChanged = (direction != _lastAnnouncedDirection);
    bool sameObject = (label == _lastAnnouncedObject);
    bool sameDir = (direction == _lastAnnouncedDirection);
    bool sameSteps = ((steps - _lastAnnouncedSteps).abs() < 2); // Tolerance of 1 step

    // Adaptive Cooldown Logic
    // Base cooldown: 3000ms (Stationary)
    // Dynamic adjustment: Speed increases -> Cooldown decreases
    // Max reduction: -2000ms (so min cooldown ~1000ms)
    
    int baseCooldown = 3000;
    int speedReduction = (_currentApproachSpeed * 10000).toInt(); // Factor to scale speed (0.01 -> 100ms)
    // Clamp reduction: Max 2000, Min 0 (ignore receding objects for now)
    speedReduction = speedReduction.clamp(0, 2000);
    
    int cooldownMs = baseCooldown - speedReduction;
    
    if (!sameObject || !sameDir || !sameSteps) {
       cooldownMs = 1500; // Even faster if context changes
    }
    
    // Safety floor
    if (cooldownMs < 1000) cooldownMs = 1000;
    
    if(_canProcess) {
      debugPrint("OD: Adaptive Cooldown: ${cooldownMs}ms (Speed: ${_currentApproachSpeed.toStringAsFixed(4)})");
    }
    
    bool shouldSpeak = false;

    if (objectChanged || directionChanged || !sameSteps) {
       // IMMEDIATE update required due to change
       shouldSpeak = true;
       // Optional: Add small throttle to prevent 100ms spam? 
       // If < 1.0s since last speak, maybe wait? 
       // But usually motion isn't THAT fast.
       if (now.difference(_lastSpeakTime).inMilliseconds < 1000) {
         shouldSpeak = false; 
       }
    } else {
       // No change (Stationary or minimal move)
       // Periodic reminder only
       if (now.difference(_lastSpeakTime).inMilliseconds > 4000) {
         shouldSpeak = true;
       }
    }

    if (shouldSpeak) {
      
      String text = "";
      
      if (lang == 'hi') {
        // Format: "[Object] [steps] kadam [direction] hai"
        // e.g. "Chair 3 kadam aage hai"
        String dirHi = _dirHindi(direction); 
        text = "$label $steps कदम $dirHi है";
      } else if (lang == 'mr') {
        // Format: "[Object] [steps] paavle [direction] aahe"
        String dirMr = _dirMarathi(direction);
        text = "$label $steps पावले $dirMr आहे";
      } else {
         // English: "The [object] is [steps] steps ahead to your [direction]"
         // Correction: "The Chair is 3 steps ahead to your left"
         // If "ahead", keep it simple: "The Chair is 3 steps ahead"
         
         String dirEn = "";
         if(direction == "ahead") {
            dirEn = "ahead";
         } else {
            dirEn = "ahead to your $direction";
         }
         text = "The $label is $steps steps $dirEn";
      }

      debugPrint("OD: Contextual Speak: $text (Steps: $steps, Dir: $direction)");
      
      // Async speak
      await tts.speak(text, languageCode: lang);

      _lastSpeakTime = now;
      _lastAnnouncedObject = label;
      _lastAnnouncedDirection = direction;
      _lastAnnouncedSteps = steps;
    }
  }

  String _dirHindi(String dir){
    if(dir=="left") return "बाएं तरफ"; // "Left side" natural flow
    if(dir=="right") return "दाएं तरफ";
    return "आगे"; // "Ahead"
  }

  String _dirMarathi(String dir){
    if(dir=="left") return "डावीकडे";
    if(dir=="right") return "उजवीकडे";
    return "समोर"; // "Ahead"
  }

  @override
  void dispose(){
    _canProcess = false;
    _controller?.dispose();
    _efficientDet?.close();


    _yoloInterpreter?.close();
    _mlKitDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){

    if(_controller==null || !_controller!.value.isInitialized){
      return const Scaffold(body:Center(child:CircularProgressIndicator()));
    }

    return Scaffold(
      body:Stack(
        children:[
          SizedBox.expand(child:CameraPreview(_controller!)),
          Positioned(
            bottom:40,left:24,right:24,
            child:MicWidget(
              isListening:_isListening,
              onTap:_isListening?_stopListening:_startListening,
            ),
          )
        ],
      ),
    );
  }

  /// ================= ML KIT HELPERS =================
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    // Android: sensorOrientation is usually 90 or 270.
    // iOS: usually 90.
    // InputImageRotationValue definition:
    // rotation0deg = 0, rotation90deg = 90, ...
    
    InputImageRotation rotation = InputImageRotation.rotation0deg;
    switch (sensorOrientation) {
      case 90: rotation = InputImageRotation.rotation90deg; break;
      case 180: rotation = InputImageRotation.rotation180deg; break;
      case 270: rotation = InputImageRotation.rotation270deg; break;
      default: rotation = InputImageRotation.rotation0deg;
    }

    // Creating InputImage from bytes
    // For Android, format is usually nv21 (YUV_420_888 in newer/camera2, but CameraImage calls it yuv420 or nv21 depending on platform impl)
    // The previous code explicitly requested ImageFormatGroup.nv21 for Android.
    
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;
    
    // Concatenate planes
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );
  }
}

class _Detection{
  final String label;
  final double xmin,ymin,xmax,ymax;
  final bool isNavigation;

  _Detection({
    required this.label,
    required this.xmin,
    required this.ymin,
    required this.xmax,
    required this.ymax,
    required this.isNavigation,
  });

  double get area => (xmax-xmin)*(ymax-ymin);
  double get centerX => (xmin+xmax)/2;
}
