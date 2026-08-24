import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  Map<String, dynamic> _localizedStrings = {};
  String _currentLanguage = 'vi';
  
  final ValueNotifier<String> languageNotifier = ValueNotifier<String>('vi');

  String get currentLanguage => _currentLanguage;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString('language') ?? 'vi';
    languageNotifier.value = _currentLanguage;
    await _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      String jsonString = await rootBundle.loadString('assets/lang/$_currentLanguage.json');
      _localizedStrings = jsonDecode(jsonString);
    } catch (e) {
      debugPrint('Error loading language file: $e');
    }
  }

  Future<void> setLanguage(String lang) async {
    if (lang == _currentLanguage) return;
    _currentLanguage = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    await _loadLanguage();
    languageNotifier.value = lang;
  }

  String translate(String key, {String? defaultString}) {
    if (_localizedStrings.containsKey(key)) {
      return _localizedStrings[key].toString();
    }
    return defaultString ?? key;
  }
}

String T(String key, {String? def}) {
  return LocalizationService().translate(key, defaultString: def);
}
