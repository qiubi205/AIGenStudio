import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import '../services/app_storage.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<WorkItem> _works = [];
  String _selectedFilter = 'all'; // 'all', 'audio', 'video'

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    loadWorks();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> loadWorks() async {
    final list = await AppStorage.getWorkHistory();
    if (mounted) {
      setState(() {
        _works = list;
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayAudio(String path) async {
    if (_currentlyPlayingPath == path && _isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      _currentlyPlayingPath = path;
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _openFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _showMsg('文件在本地已被移动或删除');
      return;
    }
    final res = await OpenFile.open(path);
    if (res.type != ResultType.done) {
      _showMsg('打开失败: ${res.message}');
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    var filtered = _works;
    if (_selectedFilter == 'audio') {
      filtered = _works.where((w) => w.kind == MediaKind.audio).toList();
    } else if (_selectedFilter == 'video') {
      filtered = _works.where((w) => w.kind == MediaKind.video).toList();
    }

    return Scaffold(
      body: Column(
        children: [
          // 顶部筛选标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('全部 (${_works.length})'),
                  selected: _selectedFilter == 'all',
                  onSelected: (v) => setState(() => _selectedFilter = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('音频 (${_works.where((w) => w.kind == MediaKind.audio).length})'),
                  selected: _selectedFilter == 'audio',
                  onSelected: (v) => setState(() => _selectedFilter = 'audio'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('视频 (${_works.where((w) => w.kind == MediaKind.video).length})'),
                  selected: _selectedFilter == 'video',
                  onSelected: (v) => setState(() => _selectedFilter = 'video'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('暂无作品记录', style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 4),
                        Text('生成 TTS 语音或视频后会自动保存至 AIGenStudio 目录并展示在这里', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isAudio = item.kind == MediaKind.audio;
                      final isPlayingCurrent = isAudio && _currentlyPlayingPath == item.filePath && _isPlaying;

                      return Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isAudio
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : Colors.amber.shade100,
                                    child: Icon(
                                      isAudio ? Icons.audiotrack : Icons.movie,
                                      color: isAudio ? Theme.of(context).colorScheme.primary : Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          item.createdAt.toLocal().toString().substring(0, 16),
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share, size: 20),
                                    onPressed: () {
                                      final file = File(item.filePath);
                                      if (file.existsSync()) {
                                        Share.shareXFiles([XFile(item.filePath)], text: item.title);
                                      } else {
                                        _showMsg('本地文件不存在');
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除作品记录'),
                                          content: const Text('确定从历史列表中删除此作品记录吗？（不会删除实际磁盘文件）'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await AppStorage.deleteWorkItem(item.id);
                                        await loadWorks();
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.description,
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '路径: ${item.filePath}',
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isAudio)
                                    TextButton.icon(
                                      icon: Icon(isPlayingCurrent ? Icons.pause : Icons.play_arrow, size: 18),
                                      label: Text(isPlayingCurrent ? '暂停' : '播放'),
                                      onPressed: () => _togglePlayAudio(item.filePath),
                                    ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.open_in_new, size: 18),
                                    label: const Text('外部打开'),
                                    onPressed: () => _openFile(item.filePath),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
