//presentation/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/language_service.dart';
// import '../../services/auth_service.dart'; // Future use if login state needed

import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkState();
  }

  Future<void> _checkState() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    final languageService = Provider.of<LanguageService>(context, listen: false);
    
    // 1. Check Permissions
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      Navigator.pushReplacementNamed(context, '/permissions');
      return;
    }

    // 2. Check Auth State
    if (await auth.isLoggedIn()) {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
    } else {
      // Not logged in -> Always select language first
      Navigator.pushNamedAndRemoveUntil(context, '/language', (route) => false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Drishti',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.blue),
        ),
      ),
    );
  }
}
