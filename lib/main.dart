import 'package:flutter/material.dart';
import 'pages/voice_clone_page.dart';
import 'pages/tts_page.dart';
import 'pages/video_gen_page.dart';
import 'pages/settings_page.dart';
import 'services/app_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AIGenStudioApp());
}

class AIGenStudioApp extends StatelessWidget {
  const AIGenStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIGenStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainHomePage(),
    );
  }
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;
  final GlobalKey<TTSPageState> _ttsPageKey = GlobalKey<TTSPageState>();

  @override
  void initState() {
    super.initState();
    _checkInitialKey();
  }

  Future<void> _checkInitialKey() async {
    final key = await AppStorage.getApiKey();
    if (key.isEmpty) {
      // 首次使用如果发现 videogen 中有现成 key，自动导入
      // 方便用户开箱即用
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TTSPage(key: _ttsPageKey),
      VoiceClonePage(
        onVoiceCreated: () {
          _ttsPageKey.currentState?.loadCustomVoices();
        },
      ),
      const VideoGenPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'AIGenStudio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        elevation: 0.5,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.volume_up_outlined),
            selectedIcon: Icon(Icons.volume_up),
            label: '语音合成',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: '音色克隆',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '视频创作',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '配置中心',
          ),
        ],
      ),
    );
  }
}
