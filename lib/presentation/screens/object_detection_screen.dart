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

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({Key? key}) : super(key: key);

  @override
  State<ObjectDetectionScreen> createState() =>
      _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> {

  CameraController? _controller;
  Interpreter? _efficientDet;
  Interpreter? _yolo;
  Interpreter? _yoloInterpreter;

  final int inputSize = 320;

  bool _isDetecting=false;
  bool _canProcess=false;
  bool _isBusy=false;
  bool _isNavigatingBack = false;

  double _previousArea=0;
  DateTime _lastSpeakTime=DateTime.fromMillisecondsSinceEpoch(0);

  List<String> labels=[];

  /// EfficientDet important objects (safety layer)
  final Set<String> importantObjects={
    "person","chair","bottle","laptop","cell phone","bench","backpack"
  };

  /// Your YOLO navigation classes
  final List<String> yoloLabels=[
    "gate","lift","stairs","corridor","building"
  ];

  @override
  void initState(){
    super.initState();
    _initializeCamera();
    _loadModels();
    _loadLabels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForBackCommand();
    });
  }

  /// ================= LOAD MODELS =================
  Future<void> _loadModels() async{
    _efficientDet = await Interpreter.fromAsset(
      "assets/models/efficientdet_lite0.tflite",
      options: InterpreterOptions()..threads=2,
    );

    _yolo = await Interpreter.fromAsset(
      "assets/models/yolo.tflite",
      options: InterpreterOptions()..threads=2,
    );
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

  void _startDetection(){
    if(_controller==null) return;

    setState(() {
      _isDetecting=true;
      _canProcess=true;
    });

    _controller!.startImageStream((CameraImage image){
      if(_canProcess && !_isBusy){
        _isBusy=true;
        _runModels(image);
      }
    });
  }

  void _stopDetection() async{
    setState(() {
      _isDetecting=false;
      _canProcess=false;
    });
    await _controller?.stopImageStream();
  }

  void _listenForBackCommand() {
    final voice = Provider.of<VoiceService>(context, listen: false);
    final langService = Provider.of<LanguageService>(context, listen: false);
    
    voice.startListening(
      languageCode: langService.currentLocale.languageCode,
      continuous: true,
      onResult: (text) {
        if (_isNavigatingBack) return;
        
        String t = text.toLowerCase();
        if (t.contains("back") || 
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
      _canProcess = false;
      _isDetecting = false;
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
    _yolo?.close();
    _yoloInterpreter?.close();

    // 3. Hard navigation reset to dashboard
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    }
  }

  /// ================= PREPROCESS =================
  Float32List _convert(CameraImage image){

    final width=image.width;
    final height=image.height;

    final Float32List buffer =
        Float32List(inputSize*inputSize*3);

    final bytes=image.planes[0].bytes;
    int index=0;

    for(int y=0;y<inputSize;y++){
      for(int x=0;x<inputSize;x++){
        int srcX=(x*width~/inputSize);
        int srcY=(y*height~/inputSize);
        int i=srcY*image.planes[0].bytesPerRow+srcX;

        double v=bytes[i]/255.0;

        buffer[index++]=v;
        buffer[index++]=v;
        buffer[index++]=v;
      }
    }
    return buffer;
  }

  /// ================= MAIN PIPELINE =================
  Future<void> _runModels(CameraImage image) async{

    if(_efficientDet==null || _yolo==null){
      _isBusy=false;
      return;
    }

    final input=_convert(image);

    /// -------- EfficientDet ----------
    var edBoxes = List.generate(1, (_) =>
        List.generate(10, (_) => List.filled(4, 0.0)));
    var edClasses = List.generate(1, (_) => List.filled(10, 0.0));
    var edScores = List.generate(1, (_) => List.filled(10, 0.0));
    var edNum = List.filled(1,0.0);

    _efficientDet!.runForMultipleInputs(
      [input],
      {0:edBoxes,1:edClasses,2:edScores,3:edNum},
    );

    /// -------- YOLO ----------
    var yoloOutput = List.generate(
        1, (_) => List.generate(8400, (_) => List.filled(10,0.0)));

    _yolo!.run(input,yoloOutput);

    List<_Detection> detections=[];

    /// EfficientDet parsing
    for(int i=0;i<10;i++){
      double score=edScores[0][i];
      if(score<0.5) continue;

      int idx=edClasses[0][i].toInt();
      String label=labels[min(idx,labels.length-1)];

      if(!importantObjects.contains(label)) continue;

      detections.add(_Detection(
        label:label,
        xmin:edBoxes[0][i][1],
        ymin:edBoxes[0][i][0],
        xmax:edBoxes[0][i][3],
        ymax:edBoxes[0][i][2],
        isNavigation:false,
      ));
    }

    /// YOLO parsing
    for(int i=0;i<8400;i+=120){

      double obj=yoloOutput[0][i][4];
      if(obj<0.4) continue;

      int bestClass=0;
      double bestScore=0;

      for(int c=0;c<yoloLabels.length;c++){
        if(yoloOutput[0][i][5+c]>bestScore){
          bestScore=yoloOutput[0][i][5+c];
          bestClass=c;
        }
      }

      if(bestScore*obj>0.45){

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
          isNavigation:true,
        ));
      }
    }

    if(detections.isNotEmpty){

      detections.sort((a,b){
        if(a.isNavigation!=b.isNavigation){
          return a.isNavigation?-1:1;
        }
        return b.area.compareTo(a.area);
      });

      final best=detections.first;
      _announce(best.label,best.area,best.centerX);
    }

    _isBusy=false;
  }

  /// ================= ULTRA NATURAL MULTI LANGUAGE SPEECH =================
  void _announce(String label,double area,double centerX) async{

    final tts=Provider.of<TtsService>(context,listen:false);
    final lang=Provider.of<LanguageService>(context,listen:false)
        .currentLocale.languageCode;

    final now=DateTime.now();

    int steps=((1-area)*10).round().clamp(1,15);

    String direction="front";
    if(centerX<0.35) direction="left";
    else if(centerX>0.65) direction="right";

    double growth=area-_previousArea;

    String enMsg="Careful. $label about $steps steps to your $direction.";
    String hiMsg="सावधान। $label आपसे $steps कदम ${_dirHindi(direction)} की ओर है।";
    String mrMsg="काळजी घ्या. $label तुमच्यापासून $steps पावले ${_dirMarathi(direction)} आहे.";

    String enWarn="Go back! $label very close.";
    String hiWarn="$label बहुत पास है, पीछे हटिए।";
    String mrWarn="$label खूप जवळ आहे, मागे या.";

    /// 🔥 EARLY COLLISION WARNING
    if(area>0.45 && growth>0.02){

      if(lang=="hi"){
        await tts.speak(hiWarn,languageCode:"hi");
      }else if(lang=="mr"){
        await tts.speak(mrWarn,languageCode:"mr");
      }else{
        await tts.speak(enWarn,languageCode:"en");
      }

      _previousArea=area;
      _lastSpeakTime=now;
      return;
    }

    /// NORMAL ANNOUNCE
    if(now.difference(_lastSpeakTime).inMilliseconds>1200){

      if(lang=="hi"){
        await tts.speak(hiMsg,languageCode:"hi");
      }else if(lang=="mr"){
        await tts.speak(mrMsg,languageCode:"mr");
      }else{
        await tts.speak(enMsg,languageCode:"en");
      }

      _lastSpeakTime=now;
    }

    _previousArea=area;
  }

  String _dirHindi(String dir){
    if(dir=="left") return "बाएँ";
    if(dir=="right") return "दाएँ";
    return "सामने";
  }

  String _dirMarathi(String dir){
    if(dir=="left") return "डावीकडे";
    if(dir=="right") return "उजवीकडे";
    return "समोर";
  }

  @override
  void dispose(){
    _canProcess = false;
    _controller?.dispose();
    _efficientDet?.close();
    _yolo?.close();
    _yoloInterpreter?.close();
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
              isListening:_isDetecting,
              onTap:_isDetecting?_stopDetection:_startDetection,
            ),
          )
        ],
      ),
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
