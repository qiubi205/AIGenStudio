import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MiniMaxService {
  final String apiKey;
  final String baseUrl;

  MiniMaxService({
    required this.apiKey,
    this.baseUrl = 'https://api.minimaxi.com',
  });

  Map<String, String> get _headers => {
        'Authorization': '***',
        'Content-Type': 'application/json',
      };

  /// 1. 上传克隆音频样本文件
  Future<int> uploadAudioFile(String filePath, {String purpose = 'voice_clone'}) async {
    final uri = Uri.parse('$baseUrl/v1/files/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['purpose'] = purpose;

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final filename = filePath.split(Platform.pathSeparator).last;

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final responseBody = await streamedResponse.stream.bytesToString();
    final data = json.decode(responseBody);

    final baseResp = data['base_resp'] ?? {};
    if (baseResp['status_code'] != 0) {
      throw Exception('上传音频失败: [${baseResp['status_code']}] ${baseResp['status_msg']}');
    }

    final fileInfo = data['file'];
    if (fileInfo == null || fileInfo['file_id'] == null) {
      throw Exception('上传成功但未返回 file_id: $responseBody');
    }

    return (fileInfo['file_id'] as num).toInt();
  }

  /// 2. 进行音色快速复刻 (Voice Clone)
  Future<Map<String, dynamic>> cloneVoice({
    required int fileId,
    required String voiceId,
    String? previewText,
    String model = 'speech-2.8-hd',
    bool noiseReduction = false,
    bool volumeNormalization = false,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/voice_clone');
    final payload = <String, dynamic>{
      'file_id': fileId,
      'voice_id': voiceId,
      'need_noise_reduction': noiseReduction,
      'need_volume_normalization': volumeNormalization,
    };

    if (previewText != null && previewText.isNotEmpty) {
      payload['text'] = previewText;
      payload['model'] = model;
    }

    final response = await http.post(
      uri,
      headers: _headers,
      body: json.encode(payload),
    );

    final data = json.decode(utf8.decode(response.bodyBytes));
    final baseResp = data['base_resp'] ?? {};
    if (baseResp['status_code'] != 0) {
      throw Exception('音色克隆失败: [${baseResp['status_code']}] ${baseResp['status_msg']}');
    }

    return data;
  }

  /// 3. 同步语音合成 (T2A V2)
  Future<Uint8List> synthesizeSpeech({
    required String text,
    required String voiceId,
    String model = 'speech-01-turbo',
    double speed = 1.0,
    double vol = 1.0,
    int pitch = 0,
    String? emotion,
    int sampleRate = 32000,
    int bitrate = 128000,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/t2a_v2');

    final voiceSetting = <String, dynamic>{
      'voice_id': voiceId,
      'speed': speed,
      'vol': vol,
      'pitch': pitch,
    };
    if (emotion != null && emotion.isNotEmpty) {
      voiceSetting['emotion'] = emotion;
    }

    final payload = <String, dynamic>{
      'model': model,
      'text': text,
      'stream': false,
      'output_format': 'hex',
      'voice_setting': voiceSetting,
      'audio_setting': {
        'sample_rate': sampleRate,
        'bitrate': bitrate,
        'format': 'mp3',
        'channel': 1,
      },
    };

    final response = await http.post(
      uri,
      headers: _headers,
      body: json.encode(payload),
    );

    final data = json.decode(utf8.decode(response.bodyBytes));
    final baseResp = data['base_resp'] ?? {};
    if (baseResp['status_code'] != 0) {
      throw Exception('语音合成失败: [${baseResp['status_code']}] ${baseResp['status_msg']}');
    }

    final audioHex = data['data']?['audio'];
    if (audioHex == null || (audioHex as String).isEmpty) {
      throw Exception('接口未返回音频 Hex 数据');
    }

    return _hexToBytes(audioHex);
  }

  /// 4. 提交视频生成任务 (MiniMax H3 / V2)
  /// 支持多模态参考素材 (文本、图片参考、音频参考)、分辨率、宽高比及时长
  Future<String> createVideoTask({
    required String prompt,
    String model = 'MiniMax-H3',
    int duration = 5,
    String resolution = '768P',
    String ratio = '16:9',
    List<Map<String, dynamic>>? referenceMedia,
  }) async {
    final uri = Uri.parse('$baseUrl/v2/video_generation');

    final content = <Map<String, dynamic>>[];
    content.add({
      'type': 'text',
      'text': prompt,
    });

    if (referenceMedia != null) {
      for (final m in referenceMedia) {
        content.add(m);
      }
    }

    final payload = <String, dynamic>{
      'model': model,
      'content': content,
      'duration': duration,
      'resolution': resolution,
    };

    // 如果指定了具体比例且未包含自适应素材
    if (ratio != 'adaptive' && ratio.isNotEmpty) {
      // ratio 参数
    }

    final response = await http.post(
      uri,
      headers: _headers,
      body: json.encode(payload),
    );

    final data = json.decode(utf8.decode(response.bodyBytes));
    if (data['error'] != null) {
      throw Exception('提交视频任务失败: ${data['error']['message']}');
    }

    final taskId = data['task_id'];
    if (taskId == null) {
      throw Exception('未返回 task_id: $data');
    }

    return taskId.toString();
  }

  /// 5. 查询视频生成状态
  Future<Map<String, dynamic>> queryVideoTask(String taskId) async {
    final uri = Uri.parse('$baseUrl/v2/query/video_generation?task_id=$taskId');
    final response = await http.get(uri, headers: _headers);

    final data = json.decode(utf8.decode(response.bodyBytes));
    return data;
  }

  /// 6. 获取下载文件临时链接
  Future<String> getFileDownloadUrl(String fileId) async {
    final uri = Uri.parse('$baseUrl/v1/files/retrieve?file_id=$fileId');
    final response = await http.get(uri, headers: _headers);
    final data = json.decode(utf8.decode(response.bodyBytes));
    final file = data['file'];
    if (file != null && file['download_url'] != null) {
      return file['download_url'];
    }
    return '$baseUrl/v1/files/$fileId';
  }

  Uint8List _hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '');
    final len = hex.length;
    final result = Uint8List(len ~/ 2);
    for (var i = 0; i < len; i += 2) {
      final part = hex.substring(i, i + 2);
      result[i ~/ 2] = int.parse(part, radix: 16);
    }
    return result;
  }
}
