import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/minimax_service.dart';
import '../services/app_storage.dart';

class VideoGenPage extends StatefulWidget {
  const VideoGenPage({super.key});

  @override
  State<VideoGenPage> createState() => _VideoGenPageState();
}

class _VideoGenPageState extends State<VideoGenPage> {
  final _promptController = TextEditingController(text: '阳光洒在金色的麦田上，微风吹拂，波光粼粼的河流缓缓流淌，4K 超清写实电影质感。');
  String _selectedModel = 'MiniMax-H3';
  int _duration = 5;
  String _resolution = '768P';

  String? _refImagePath;
  String? _refImageName;

  bool _isSubmitting = false;
  String _taskId = '';
  String _taskStatus = '';
  String? _videoUrl;
  Timer? _pollTimer;

  @override
  void dispose() {
    _promptController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _refImagePath = result.files.single.path;
        _refImageName = result.files.single.name;
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
      _taskStatus = '正在提交任务...';
      _videoUrl = null;
      _taskId = '';
    });

    try {
      final baseUrl = await AppStorage.getBaseUrl();
      final service = MiniMaxService(apiKey: apiKey, baseUrl: baseUrl);

      List<Map<String, dynamic>>? referenceMedia;
      if (_refImagePath != null) {
        final bytes = await File(_refImagePath!).readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = _refImagePath!.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        final dataUri = 'data:$mime;base64,$b64';

        referenceMedia = [
          {
            'type': 'image_url',
            'image_url': {'url': dataUri},
            'role': 'reference_image',
          }
        ];
      }

      final taskId = await service.createVideoTask(
        prompt: prompt,
        model: _selectedModel,
        duration: _duration,
        resolution: _resolution,
        referenceMedia: referenceMedia,
      );

      setState(() {
        _taskId = taskId;
        _taskStatus = '任务已提交 (ID: $taskId)，正在排队生成...';
      });

      _startPolling(service, taskId);
    } catch (e) {
      setState(() {
        _taskStatus = '❌ 提交失败: $e';
        _isSubmitting = false;
      });
      _showMsg('提交失败: $e');
    }
  }

  void _startPolling(MiniMaxService service, String taskId) {
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
            _isSubmitting = false;
            _taskStatus = '🎉 视频生成完成！';
            _videoUrl = downloadUrl;
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
      } catch (e) {
        // 网络抖动重试
      }
    });
  }

  Future<void> _downloadAndShareVideo() async {
    if (_videoUrl == null) return;
    try {
      _showMsg('正在下载视频...');
      final resp = await http.get(Uri.parse(_videoUrl!));
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(resp.bodyBytes);
      _showMsg('视频已下载，正在调起分享...');
      await Share.shareXFiles([XFile(file.path)], text: '由 AIGenStudio 生成的视频');
    } catch (e) {
      _showMsg('下载/分享失败: $e');
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
                        'AI 视频生成 (MiniMax H3)',
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

                  // 2. 参考图 (图生视频 / 角色参考)
                  const Text('2. 参考图片 (可选)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _isSubmitting ? null : _pickImage,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                        color: _refImagePath != null ? Colors.purple.withOpacity(0.05) : null,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.image, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _refImageName ?? '点击添加参考图片 (用于图生视频或保持角色一致)',
                              style: TextStyle(
                                color: _refImagePath != null ? Colors.black87 : Colors.grey,
                                fontWeight: _refImagePath != null ? FontWeight.w500 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_refImagePath != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _refImagePath = null;
                                _refImageName = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 模型与时长
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('模型', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _selectedModel,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'MiniMax-H3', child: Text('MiniMax-H3 (推荐)', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) => setState(() => _selectedModel = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('视频时长', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                  const SizedBox(height: 16),

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

          // 结果展示与下载
          if (_videoUrl != null)
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
                        Text('视频已就绪', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '下载链接: $_videoUrl',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('下载并保存/分享视频 (MP4)'),
                        onPressed: _downloadAndShareVideo,
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
