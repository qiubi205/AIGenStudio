import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaKind {
  audio,
  video,
  voiceClone,
}

class WorkItem {
  final String id;
  final String title;
  final String description;
  final String filePath;
  final String? remoteUrl;
  final MediaKind kind;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  WorkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.filePath,
    this.remoteUrl,
    required this.kind,
    required this.createdAt,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'filePath': filePath,
        'remoteUrl': remoteUrl,
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        'metadata': metadata,
      };

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        filePath: json['filePath'] ?? '',
        remoteUrl: json['remoteUrl'],
        kind: MediaKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => MediaKind.audio,
        ),
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        metadata: json['metadata'] != null ? Map<String, dynamic>.from(json['metadata']) : null,
      );
}

class ClonedVoice {
  final String voiceId;
  final String name;
  final DateTime createdAt;
  final String? sampleAudioPath;

  ClonedVoice({
    required this.voiceId,
    required this.name,
    required this.createdAt,
    this.sampleAudioPath,
  });

  Map<String, dynamic> toJson() => {
        'voiceId': voiceId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'sampleAudioPath': sampleAudioPath,
      };

  factory ClonedVoice.fromJson(Map<String, dynamic> json) => ClonedVoice(
        voiceId: json['voiceId'] ?? '',
        name: json['name'] ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        sampleAudioPath: json['sampleAudioPath'],
      );
}

class AppStorage {
  static const _kApiKey = 'minimax_api_key';
  static const _kBaseUrl = 'minimax_base_url';
  static const _kClonedVoices = 'cloned_voices_list';
  static const _kWorkHistory = 'work_history_list';

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

  // 音色库
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

  // 历史作品库
  static Future<List<WorkItem>> getWorkHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWorkHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List list = json.decode(raw);
      return list.map((e) => WorkItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addWorkItem(WorkItem item) async {
    final list = await getWorkHistory();
    list.removeWhere((w) => w.id == item.id);
    list.insert(0, item);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWorkHistory, json.encode(list.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteWorkItem(String id) async {
    final list = await getWorkHistory();
    list.removeWhere((w) => w.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWorkHistory, json.encode(list.map((e) => e.toJson()).toList()));
  }
}
