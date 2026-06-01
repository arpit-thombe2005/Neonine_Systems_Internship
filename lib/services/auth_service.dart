import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Authentication service — manages session and user data locally.
/// Communicates with the backend API (Neon DB) instead of Firestore.
class AuthService {
  final ApiService _apiService = ApiService();

  static const String _sessionKey = 'user_phone';
  static const String _userDataKey = 'user_data';

  /// Check if a phone number is registered in the Neon database.
  /// Returns user data map if registered, null otherwise.
  Future<Map<String, dynamic>?> checkUserExists(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\+]'), '');
    debugPrint('Checking if user exists: $cleanPhone');

    try {
      final userData = await _apiService.getUserByPhone(cleanPhone);
      if (userData != null && userData['id'] != null) {
        debugPrint('User found: ${userData['full_name']}');
        return userData;
      }
    } catch (e) {
      debugPrint('Error checking user existence: $e');
      rethrow;
    }

    debugPrint('User not found for phone: $cleanPhone');
    return null;
  }

  /// Save user session locally after successful login/registration.
  /// Stores both the phone number and full user data.
  Future<void> saveSession(String phoneNumber, {Map<String, dynamic>? userData}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, phoneNumber);
    if (userData != null) {
      await prefs.setString(_userDataKey, jsonEncode(userData));
    }
  }

  /// Get the stored phone number from local session.
  Future<String?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// Get the full stored user data from local session.
  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString(_userDataKey);
    if (dataStr != null && dataStr.isNotEmpty) {
      return jsonDecode(dataStr) as Map<String, dynamic>;
    }
    return null;
  }

  /// Get user type from stored session ('farmer' or 'service_provider').
  Future<String?> getUserType() async {
    final data = await getUserData();
    return data?['user_type'] as String?;
  }

  /// Get user's full name from stored session.
  Future<String?> getUserName() async {
    final data = await getUserData();
    return data?['full_name'] as String?;
  }

  /// Get user's ID from stored session.
  Future<String?> getUserId() async {
    final data = await getUserData();
    return data?['id'] as String?;
  }

  /// Check if user is currently signed in.
  Future<bool> isSignedIn() async {
    final session = await getSession();
    return session != null && session.isNotEmpty;
  }

  /// Sign the user out by clearing all session data.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_userDataKey);
  }

  /// Update cached user data (e.g., after location update).
  Future<void> updateCachedUserData(Map<String, dynamic> updates) async {
    final currentData = await getUserData();
    if (currentData != null) {
      currentData.addAll(updates);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userDataKey, jsonEncode(currentData));
    }
  }
}
