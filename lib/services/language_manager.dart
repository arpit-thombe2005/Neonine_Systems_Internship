import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageManager {
  static final LanguageManager instance = LanguageManager._internal();
  LanguageManager._internal();

  final ValueNotifier<String> currentLanguage = ValueNotifier<String>('en');

  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'hi': 'हिंदी (Hindi)',
    'mr': 'मराठी (Marathi)',
    'kn': 'ಕನ್ನಡ (Kannada)',
    'ta': 'தமிழ் (Tamil)',
  };

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString('selected_language');
      if (savedLang != null && supportedLanguages.containsKey(savedLang)) {
        currentLanguage.value = savedLang;
      }
    } catch (e) {
      debugPrint('LanguageManager init error: $e');
    }
  }

  Future<void> changeLanguage(String langCode) async {
    if (supportedLanguages.containsKey(langCode)) {
      currentLanguage.value = langCode;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_language', langCode);
      } catch (e) {
        debugPrint('LanguageManager save error: $e');
      }
    }
  }
}
