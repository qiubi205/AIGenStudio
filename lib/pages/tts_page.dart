import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/minimax_service.dart';
import '../services/app_storage.dart';

class TTSPage extends StatefulWidget {
  const TTSPage({super.key});

  @override
  State<TTSPage> createState() => TTSPageState();
}

class TTSPageState extends State<TTSPage> {
  final _textController = TextEditingController(
    text: '亲爱的老师，欢迎使用 AIGenStudio！无论是声音复刻、文本朗读还是视频创作，这里都能轻松搞定。',
  );

  String _selectedModel = 'speech-01-turbo';
  String _selectedVoiceId = 'male-qn-qingse';
  String _selectedVoiceName = '青涩青年 (系统预设)';
  double _speed = 1.0;
  double _vol = 1.0;
  int _pitch = 0;
  String _selectedEmotion = 'happy';

  bool _isGenerating = false;
  String _statusMsg = '';

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  String? _lastGeneratedAudioPath;

  List<ClonedVoice> _customVoices = [];

  final List<Map<String, String>> _systemVoices = [
    {'id': 'male-qn-qingse', 'name': '青涩青年 (中文预设)'},
    {'id': 'female-shaonv', 'name': '少女音 (中文预设)'},
    {'id': 'female-yujie', 'name': '御姐音 (中文预设)'},
    {'id': 'male-chengshu', 'name': '成熟男声 (中文预设)'},
    {'id': 'Chinese (Mandarin)_Lyrical_Voice', 'name': '抒情女声 (Mandarin Lyrical)'},
    {'id': 'English_radiant_girl', 'name': '阳光女孩 (English Radiant)'},
    {'id': 'Japanese_Whisper_Belle', 'name': '日系轻语 (Japanese Whisper)'},
  ];

  final List<String> _models = [
    'speech-01-turbo',
    'speech-01-hd',
    'speech-2.8-turbo',
    'speech-2.8-hd',
    'speech-2.6-turbo',
    'speech-02-turbo',
  ];

  final List<Map<String, String>> _emotions = [
    {'id': 'happy', 'name': '高兴 (happy)'},
    {'id': 'calm', 'name': '中性/平静 (calm)'},
    {'id': 'sad', 'name': '悲伤 (sad)'},
    {'id': 'angry', 'name': '愤怒 (angry)'},
    {'id': 'fearful', 'name': '害怕 (fearful)'},
    {'id': 'disgusted', 'name': '厌恶 (disgusted)'},
    {'id': 'surprised', 'name': '惊讶 (surprised)'},
    {'id': 'fluent', 'name': '生动 (fluent)'},
  ];

  @override
  void initState() {
    super.initState();
    loadCustomVoices();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> loadCustomVoices() async {
    final list = await AppStorage.getClonedVoices();
    if (mounted) {
      setState(() {
        _customVoices = list;
        if (list.isNotEmpty && _selectedVoiceId == 'male-qn-qingse') {
          // 默认选中第一个自定义音色
          _selectedVoiceId = list.first.voiceId;
          _selectedVoiceName = '${list.first.name} (我的克隆)';
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _generateSpeech() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showMsg('请输入需要合成的文字内容');
      return;
    }

    final apiKey = await AppStorage.getApiKey();
    if (apiKey.isEmpty) {
      _showMsg('请先在"设置"页面填写 MiniMax API Key');
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMsg = '正在生成语音...';
    });

    try {
      final baseUrl = await AppStorage.getBaseUrl();
      final service = MiniMaxService(apiKey: apiKey, baseUrl: baseUrl);

      final audioBytes = await service.synthesizeSpeech(
        text: text,
        voiceId: _selectedVoiceId,
        model: _selectedModel,
        speed: _speed,
        vol: _vol,
        pitch: _pitch,
        emotion: _selectedEmotion,
      );

      final tempDir = await getTemporaryDirectory();
      final filename = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(audioBytes);

      setState(() {
        _lastGeneratedAudioPath = file.path;
        _statusMsg = '🎉 语音生成成功 (${(audioBytes.length / 1024).toStringAsFixed(1)} KB)';
      });

      // 自动播放
      await _playAudio(file.path);
    } catch (e) {
      setState(() {
        _statusMsg = '❌ 生成失败: $e';
      });
      _showMsg('生成失败: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _playAudio(String path) async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() => _isPlaying = true);
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _selectVoiceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('选择发音音色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    if (_customVoices.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text('⭐ 我的克隆音色', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                      ),
                      ..._customVoices.map((v) => ListTile(
                            leading: const Icon(Icons.stars, color: Colors.deepPurple),
                            title: Text(v.name),
                            subtitle: Text(v.voiceId, style: const TextStyle(fontSize: 11)),
                            trailing: _selectedVoiceId == v.voiceId ? const Icon(Icons.check, color: Colors.deepPurple) : null,
                            onTap: () {
                              setState(() {
                                _selectedVoiceId = v.voiceId;
                                _selectedVoiceName = '${v.name} (我的克隆)';
                              });
                              Navigator.pop(ctx);
                            },
                          )),
                      const Divider(),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text('🌐 系统预设音色', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                    ..._systemVoices.map((v) => ListTile(
                          leading: const Icon(Icons.record_voice_over, color: Colors.blue),
                          title: Text(v['name']!),
                          subtitle: Text(v['id']!, style: const TextStyle(fontSize: 11)),
                          trailing: _selectedVoiceId == v['id'] ? const Icon(Icons.check, color: Colors.blue) : null,
                          onTap: () {
                            setState(() {
                              _selectedVoiceId = v['id']!;
                              _selectedVoiceName = v['name']!;
                            });
                            Navigator.pop(ctx);
                          },
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                        child: Icon(Icons.volume_up, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '文本转语音 (TTS)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. 选择音色
                  const Text('1. 发音人音色', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectVoiceDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_pin, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_selectedVoiceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('ID: $_selectedVoiceId', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. 文本内容
                  const Text('2. 合成文本内容', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('支持添加 (laughs) (breath) 等语气词标签', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: '请输入您想朗读的文本...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 模型与情绪
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TTS 模型', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _selectedModel,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: _models.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12)))).toList(),
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
                            const Text('情绪风格', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _selectedEmotion,
                              isDense: true,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: _emotions.map((e) => DropdownMenuItem(value: e['id'], child: Text(e['name']!, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (v) => setState(() => _selectedEmotion = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. 参数微调 (语速 / 音量 / 语调)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('语速: ${_speed.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12)),
                      Text('音量: ${_vol.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                      Text('音调: $_pitch', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '语速: ${_speed.toStringAsFixed(1)}',
                    onChanged: (v) => setState(() => _speed = v),
                  ),
                  const SizedBox(height: 8),

                  // 生成按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateSpeech,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_circle_fill),
                      label: Text(
                        _isGenerating ? '合成中...' : '生成并朗读语音',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  if (_statusMsg.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_statusMsg, style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 试听与导出卡片
          if (_lastGeneratedAudioPath != null)
            Card(
              elevation: 2,
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton.filled(
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () => _playAudio(_lastGeneratedAudioPath!),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('最新生成的音频', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('点击左侧播放，或分享/保存到外部', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: '分享/导出音频文件',
                      onPressed: () {
                        Share.shareXFiles([XFile(_lastGeneratedAudioPath!)], text: '分享由 AIGenStudio 生成的音频');
                      },
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
