import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/minimax_service.dart';
import '../services/app_storage.dart';

class VoiceClonePage extends StatefulWidget {
  final VoidCallback onVoiceCreated;
  const VoiceClonePage({super.key, required this.onVoiceCreated});

  @override
  State<VoiceClonePage> createState() => _VoiceClonePageState();
}

class _VoiceClonePageState extends State<VoiceClonePage> {
  final _voiceIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _previewTextController = TextEditingController(text: '你好，这是我克隆出的专属音色，试听一下效果怎么样。');

  String? _selectedAudioPath;
  String? _selectedAudioName;
  bool _noiseReduction = true;
  bool _volumeNormalization = true;

  bool _isProcessing = false;
  String _statusMessage = '';

  List<ClonedVoice> _savedVoices = [];

  @override
  void initState() {
    super.initState();
    _loadSavedVoices();
  }

  Future<void> _loadSavedVoices() async {
    final list = await AppStorage.getClonedVoices();
    if (mounted) {
      setState(() {
        _savedVoices = list;
      });
    }
  }

  @override
  void dispose() {
    _voiceIdController.dispose();
    _nameController.dispose();
    _previewTextController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedAudioPath = result.files.single.path;
        _selectedAudioName = result.files.single.name;
      });
    }
  }

  Future<void> _startClone() async {
    final apiKey = await AppStorage.getApiKey();
    if (apiKey.isEmpty) {
      _showMsg('请先在"设置"页面填写 MiniMax API Key');
      return;
    }
    if (_selectedAudioPath == null) {
      _showMsg('请先选择样本音频文件');
      return;
    }
    final voiceId = _voiceIdController.text.trim();
    if (voiceId.isEmpty) {
      _showMsg('请输入自定义 Voice ID（以英文字母开头，8~256位）');
      return;
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{7,255}$').hasMatch(voiceId)) {
      _showMsg('Voice ID 格式不符：须以英文字母开头，长度 8~256 字符');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = '正在上传样本音频...';
    });

    try {
      final baseUrl = await AppStorage.getBaseUrl();
      final service = MiniMaxService(apiKey: apiKey, baseUrl: baseUrl);

      // 1. 上传音频
      final fileId = await service.uploadAudioFile(_selectedAudioPath!, purpose: 'voice_clone');
      setState(() {
        _statusMessage = '音频上传成功 (ID: $fileId)，正在提交音色克隆...';
      });

      // 2. 提交音色复刻
      final previewText = _previewTextController.text.trim();
      await service.cloneVoice(
        fileId: fileId,
        voiceId: voiceId,
        previewText: previewText.isNotEmpty ? previewText : null,
        noiseReduction: _noiseReduction,
        volumeNormalization: _volumeNormalization,
      );

      // 3. 保存至本地
      final name = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : voiceId;

      final cloned = ClonedVoice(
        voiceId: voiceId,
        name: name,
        createdAt: DateTime.now(),
        sampleAudioPath: _selectedAudioPath,
      );
      await AppStorage.saveClonedVoice(cloned);
      await _loadSavedVoices();
      widget.onVoiceCreated();

      setState(() {
        _statusMessage = '🎉 音色复刻成功！Voice ID: $voiceId';
      });
      _showMsg('音色复刻成功！已加入音色列表');
    } catch (e) {
      setState(() {
        _statusMessage = '❌ 失败: $e';
      });
      _showMsg('失败: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
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
                        child: Icon(Icons.mic, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '快速音色复刻 (Voice Clone)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '上传一段 10秒~5分钟 的清晰说话音频（mp3/wav/m4a），即可复刻出您的专属音色。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const Divider(height: 24),

                  // 1. 选择音频
                  const Text('1. 样本音频文件 *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _isProcessing ? null : _pickAudioFile,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(12),
                        color: _selectedAudioPath != null ? Colors.blue.withValues(alpha: 0.05) : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedAudioPath != null ? Icons.audiotrack : Icons.upload_file,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedAudioName ?? '点击选择本地音频文件 (mp3/wav/m4a)',
                              style: TextStyle(
                                color: _selectedAudioPath != null ? Colors.black87 : Colors.grey,
                                fontWeight: _selectedAudioPath != null ? FontWeight.w500 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedAudioPath != null)
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. 自定义 Voice ID
                  const Text('2. 音色编号 (Voice ID) *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    '英文字母开头，8~256位，如 MyVoice_001',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _voiceIdController,
                    decoration: InputDecoration(
                      hintText: '如: HayaseYuuka_01',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        tooltip: '随机生成 ID',
                        onPressed: () {
                          final id = 'Voice_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                          _voiceIdController.text = id;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. 音色备注名称
                  const Text('3. 音色备注名称 (可选)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: '如: 优香的主音色',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. 试听文字
                  const Text('4. 复刻后试听文本 (可选)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _previewTextController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: '输入试听朗读内容...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 选项
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('样本降噪', style: TextStyle(fontSize: 13)),
                          value: _noiseReduction,
                          onChanged: (v) => setState(() => _noiseReduction = v ?? true),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('音量归一化', style: TextStyle(fontSize: 13)),
                          value: _volumeNormalization,
                          onChanged: (v) => setState(() => _volumeNormalization = v ?? true),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 提交按钮
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startClone,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.record_voice_over),
                      label: Text(
                        _isProcessing ? '处理中...' : '开始克隆音色',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 已保存的复刻音色列表
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '已保存的音色库',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '共 ${_savedVoices.length} 个音色',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  if (_savedVoices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无已克隆音色，克隆成功后将展示在这里',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _savedVoices.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final v = _savedVoices[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('ID: ${v.voiceId}\n创建: ${v.createdAt.toLocal().toString().substring(0, 16)}', style: const TextStyle(fontSize: 11)),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('删除音色记录'),
                                  content: Text('确定从本地列表中移除音色 "${v.name}" (${v.voiceId}) 吗？'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await AppStorage.deleteClonedVoice(v.voiceId);
                                await _loadSavedVoices();
                                widget.onVoiceCreated();
                              }
                            },
                          ),
                        );
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
