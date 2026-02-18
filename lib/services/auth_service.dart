import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'database_service.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🔥 NEW

class AuthService {
  static const String _authKey = 'auth_token';
  final DatabaseService _dbService = DatabaseService();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance; // 🔥 NEW

  Future<void> init() async {
    // Database initialization is handled by DatabaseService
  }

  Future<bool> userExists(String username) async {
    final db = await _dbService.database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    return result.isNotEmpty;
  }

  Future<bool> hasUsers() async {
    final db = await _dbService.database;
    final users = await db.query('users');
    return users.isNotEmpty;
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  // 🔥 UPDATED REGISTER (keeps local DB + adds Firebase)
  Future<bool> register(String username, String password) async {
    final db = await _dbService.database;
    final hashedPassword = _hashPassword(password);
    
    try {
      await db.insert('users', {
        'username': username,
        'password_hash': hashedPassword,
        // 'recovery_pin_hash': null, 
      });

      // 🔥 Create Firebase user (cloud sync)
      // Note: In a real app we might want to handle this more robustly
      try {
        await _firebaseAuth.createUserWithEmailAndPassword(
          email: "$username@drishti.app",
          password: password,
        );
      } catch (e) {
        print("Firebase auth error (ignored for offline): $e");
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // Password reset methods removed as per new biometric flow requirements.

  // 🔥 UPDATED LOGIN (local auth + Firebase sync)
  Future<bool> login(String username, String password) async {
    final db = await _dbService.database;
    final hashedPassword = _hashPassword(password);

    final users = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username, hashedPassword],
    );

    if (users.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_authKey, true);

      // 🔥 Firebase sign-in (Silent, best effort)
      try {
        await _firebaseAuth.signInWithEmailAndPassword(
          email: "$username@drishti.app",
          password: password,
        );
      } catch (e) {
        print("Firebase login error (ignored for offline): $e");
      }

      return true;
    }
    return false;
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authKey) ?? false;
  }

  // 🔥 UPDATED LOGOUT
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authKey, false);
    await _firebaseAuth.signOut();
  }
}
