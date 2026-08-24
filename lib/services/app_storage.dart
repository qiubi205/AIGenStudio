import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClonedVoice {
  final String voiceId;
  final String name;
  final DateTime createdAt;
  final String? previewPath;

  ClonedVoice({
    required this.voiceId,
    required this.name,
    required this.createdAt,
    this.previewPath,
  });

  Map<String, dynamic> toJson() => {
        'voiceId': voiceId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'previewPath': previewPath,
      };

  factory ClonedVoice.fromJson(Map<String, dynamic> json) => ClonedVoice(
        voiceId: json['voiceId'] ?? '',
        name: json['name'] ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        previewPath: json['previewPath'],
      );
}

class AppStorage {
  static const _kApiKey = 'minimax_api_key';
  static const _kBaseUrl = 'minimax_base_url';
  static const _kClonedVoices = 'cloned_voices_list';

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey) ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key);
  }

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBaseUrl) ?? 'https://api.minimaxi.com';
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, url);
  }

  static Future<List<ClonedVoice>> getClonedVoices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kClonedVoices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List list = json.decode(raw);
      return list.map((e) => ClonedVoice.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveClonedVoice(ClonedVoice voice) async {
    final list = await getClonedVoices();
    list.removeWhere((v) => v.voiceId == voice.voiceId);
    list.insert(0, voice);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClonedVoices, json.encode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteClonedVoice(String voiceId) async {
    final list = await getClonedVoices();
    list.removeWhere((v) => v.voiceId == voiceId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClonedVoices, json.encode(list.map((e) => e.toJson()).toList()));
  }
}
