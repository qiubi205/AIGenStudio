import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import '../services/minimax_service.dart';
import '../services/app_storage.dart';
import '../services/storage_service.dart';

class MediaAsset {
  final String path;
  final String name;
  final String type; // 'image_url' or 'audio_url'
  final String role; // 'reference_image', 'first_frame', 'last_frame', 'reference_audio'

  MediaAsset({
    required this.path,
    required this.name,
    required this.type,
    required this.role,
  });
}

class VideoGenPage extends StatefulWidget {
  final VoidCallback? onWorkCreated;
  const VideoGenPage({super.key, this.onWorkCreated});

  @override
  State<VideoGenPage> createState() => _VideoGenPageState();
}

class _VideoGenPageState extends State<VideoGenPage> {
  final _promptController = TextEditingController(text: '阳光洒在金色的麦田上，微风吹拂，波光粼粼的河流缓缓流淌，4K 超清写实电影质感。');
  String _selectedModel = 'MiniMax-H3';
  int _duration = 5;
  String _resolution = '768P';
  String _aspectRatio = '16:9';

  final List<MediaAsset> _mediaAssets = [];

  bool _isSubmitting = false;
  String _taskStatus = '';
  String? _savedLocalPath;
  Timer? _pollTimer;

  final List<String> _resolutions = ['768P', '1080P'];
  final List<String> _ratios = ['16:9', '9:16', '1:1', 'adaptive'];

  @override
  void dispose() {
    _promptController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickMedia(String kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: kind == 'image' ? FileType.image : FileType.audio,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      setState(() {
        _mediaAssets.add(MediaAsset(
          path: path,
          name: name,
          type: kind == 'image' ? 'image_url' : 'audio_url',
          role: kind == 'image' ? 'reference_image' : 'reference_audio',
        ));
      });
    }
  }

  Future<void> _submitVideoTask() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showMsg('请输入视频画面描述 Prompt');
      return;
    }

    final apiKey = await AppStorage.getApiKey();
    if (apiKey.isEmpty) {
      _showMsg('请先在"设置"页面填写 MiniMax API Key');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _taskStatus = '正在准备多模态素材并提交任务...';
      _savedLocalPath = null;
    });

    try {
      final baseUrl = await AppStorage.getBaseUrl();
      final service = MiniMaxService(apiKey: apiKey, baseUrl: baseUrl);

      List<Map<String, dynamic>>? referenceMedia;
      if (_mediaAssets.isNotEmpty) {
        referenceMedia = [];
        for (final asset in _mediaAssets) {
          final file = File(asset.path);
          final bytes = await file.readAsBytes();
          final b64 = base64Encode(bytes);
          final ext = asset.name.split('.').last.toLowerCase();
          
          String mime = 'image/jpeg';
          if (asset.type == 'image_url') {
            if (ext == 'png') mime = 'image/png';
            if (ext == 'webp') mime = 'image/webp';
            referenceMedia.add({
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,$b64'},
              'role': asset.role,
            });
          } else {
            if (ext == 'mp3') mime = 'audio/mpeg';
            if (ext == 'wav') mime = 'audio/wav';
            if (ext == 'm4a') mime = 'audio/mp4';
            referenceMedia.add({
              'type': 'audio_url',
              'audio_url': {'url': 'data:$mime;base64,$b64'},
              'role': asset.role,
            });
          }
        }
      }

      final taskId = await service.createVideoTask(
        prompt: prompt,
        model: _selectedModel,
        duration: _duration,
        resolution: _resolution,
        ratio: _aspectRatio,
        referenceMedia: referenceMedia,
      );

      setState(() {
        _taskStatus = '任务已提交 (ID: $taskId)，正在排队生成...';
      });

      _startPolling(service, taskId, prompt);
    } catch (e) {
      setState(() {
        _taskStatus = '❌ 提交失败: $e';
        _isSubmitting = false;
      });
      _showMsg('提交失败: $e');
    }
  }

  void _startPolling(MiniMaxService service, String taskId, String prompt) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      try {
        final queryRes = await service.queryVideoTask(taskId);
        final status = queryRes['status'] ?? '';

        if (status == 'succeeded' || status == 'Success' || status == 'SUCCESS') {
          timer.cancel();
          final fileId = queryRes['file_id'];
          String? downloadUrl = queryRes['video_url'] ?? queryRes['download_url'];

          if (downloadUrl == null && fileId != null) {
            downloadUrl = await service.getFileDownloadUrl(fileId.toString());
          }

          setState(() {
            _taskStatus = '🎉 视频生成完成！正在自动保存至本地 AIGenStudio 目录...';
          });

          // 自动下载并保存到本地专属目录
          if (downloadUrl != null) {
            await _autoSaveVideo(downloadUrl, prompt, taskId);
          }

          setState(() {
            _isSubmitting = false;
          });
        } else if (status == 'failed' || status == 'FAILED' || status == 'Fail') {
          timer.cancel();
          setState(() {
            _isSubmitting = false;
            _taskStatus = '❌ 视频生成失败: ${queryRes['error'] ?? queryRes['fail_reason'] ?? '未知原因'}';
          });
        } else {
          setState(() {
            _taskStatus = '⏳ 正在生成中... (状态: $status)';
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _autoSaveVideo(String url, String prompt, String taskId) async {
    try {
      final resp = await http.get(Uri.parse(url));
      final filename = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savedFile = await StorageService.saveMediaFile(
        bytes: resp.bodyBytes,
        filename: filename,
        subFolder: 'videos',
      );

      final work = WorkItem(
        id: 'work_vid_$taskId',
        title: prompt.length > 20 ? '${prompt.substring(0, 20)}...' : prompt,
        description: '模型: $_selectedModel, 分辨率: $_resolution, 时长: ${_duration}s',
        filePath: savedFile.path,
        remoteUrl: url,
        kind: MediaKind.video,
        createdAt: DateTime.now(),
        metadata: {
          'prompt': prompt,
          'duration': _duration,
          'resolution': _resolution,
        },
      );

      await AppStorage.addWorkItem(work);
      widget.onWorkCreated?.call();

      if (mounted) {
        setState(() {
          _savedLocalPath = savedFile.path;
          _taskStatus = '🎉 视频生成完成并已存入作品库: ${savedFile.path}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskStatus = '🎉 视频已生成，但本地保存失败: $e';
        });
      }
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.video_library, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'AI 视频生成工坊 (MiniMax H3)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. 提示词
                  const Text('1. 视频画面描述 (Prompt) *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _promptController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: '描述你想要生成的视频镜头、光影、主体动作...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. 多模态素材 (参考图片 / 参考音频)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('2. 多模态参考素材 (可选)', style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.image, size: 18),
                            label: const Text('参考图', style: TextStyle(fontSize: 12)),
                            onPressed: _isSubmitting ? null : () => _pickMedia('image'),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.audiotrack, size: 18),
                            label: const Text('参考音频', style: TextStyle(fontSize: 12)),
                            onPressed: _isSubmitting ? null : () => _pickMedia('audio'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_mediaAssets.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '暂无素材。点击右上角按钮可添加图片（用于图生视频/主体参考）或音频（用于音频驱动视频生成）。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _mediaAssets.map((asset) {
                        final isImage = asset.type == 'image_url';
                        return Chip(
                          avatar: Icon(isImage ? Icons.image : Icons.audiotrack, size: 16),
                          label: Text('${asset.name} (${isImage ? "图" : "音频"})', style: const TextStyle(fontSize: 11)),
                          onDeleted: _isSubmitting
                              ? null
                              : () => setState(() => _mediaAssets.remove(asset)),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),

                  // 3. 模型与分辨率、画幅、时长
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('清晰度', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _resolution,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: _resolutions
                                  .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (v) => setState(() => _resolution = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('画幅比例', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _aspectRatio,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: _ratios
                                  .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (v) => setState(() => _aspectRatio = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('时长', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              value: _duration,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 5, child: Text('5 秒', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 10, child: Text('10 秒', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) => setState(() => _duration = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 提交按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitVideoTask,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.movie_creation),
                      label: Text(
                        _isSubmitting ? '生成中...' : '开始生成视频',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  if (_taskStatus.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_taskStatus, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 结果展示与分享
          if (_savedLocalPath != null)
            Card(
              elevation: 2,
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('视频已存入成果库', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '文件路径: $_savedLocalPath',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Text('分享 / 发送视频'),
                        onPressed: () {
                          Share.shareXFiles([XFile(_savedLocalPath!)], text: '由 AIGenStudio 生成的视频');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
