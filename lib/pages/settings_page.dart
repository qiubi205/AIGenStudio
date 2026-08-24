import 'package:flutter/material.dart';
import '../services/app_storage.dart';
import '../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  bool _obscureKey = true;
  String _folderPath = '/sdcard/AIGenStudio';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await AppStorage.getApiKey();
    final url = await AppStorage.getBaseUrl();
    final dir = await StorageService.getAppOutputDirectory();
    setState(() {
      _apiKeyController.text = key;
      _baseUrlController.text = url;
      _folderPath = dir.path;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final key = _apiKeyController.text.trim();
    final url = _baseUrlController.text.trim();

    await AppStorage.setApiKey(key);
    if (url.isNotEmpty) {
      await AppStorage.setBaseUrl(url);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存！')),
      );
    }
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
                        child: Icon(Icons.key, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'MiniMax API 配置',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  const Text('MiniMax API Key *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('在 MiniMax 开放平台获取的 API Secret Key（音视频通用）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      hintText: 'sk-api...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('API Base URL', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('默认 https://api.minimaxi.com', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      hintText: 'https://api.minimaxi.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('保存配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 存储与文件管理卡片
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder_special, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('成果存储目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 16),
                  const Text('所有生成的 TTS 音频和 MiniMax 视频均会自动持久化保存在以下设备目录中：', style: TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _folderPath,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final granted = await StorageService.requestStoragePermission();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(granted ? '已授予存储访问权限！' : '未能获取完全存储权限，请检查系统设置')),
                        );
                      }
                    },
                    icon: const Icon(Icons.security),
                    label: const Text('重新检查并申请存储权限'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于 AIGenStudio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Divider(height: 16),
                  Text('版本: v0.2.0 (Release)', style: TextStyle(fontSize: 13)),
                  SizedBox(height: 6),
                  Text('功能特性: 音色复刻、TTS 语音合成、MiniMax H3 多模态视频、成果自动归档与作品库管理。', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  SizedBox(height: 6),
                  Text('所有本地数据均储存在手机中，安全私密。', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
