import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const String appFolderName = 'AIGenStudio';

  /// 请求存储相关权限
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // 针对 Android 13+ 的多媒体权限以及 Android 10/11 的存储权限
      Map<Permission, PermissionStatus> statuses = await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();

      final storageGranted = statuses[Permission.storage]?.isGranted ?? false;
      final manageGranted = statuses[Permission.manageExternalStorage]?.isGranted ?? false;

      return storageGranted || manageGranted;
    } catch (_) {
      return false;
    }
  }

  /// 获取或创建 AIGenStudio 专用存储根目录
  /// 优先使用 /sdcard/AIGenStudio，失败时回退到外部存储私有目录
  static Future<Directory> getAppOutputDirectory({String? subFolder}) async {
    Directory targetDir;
    try {
      // 尝试在主存储根路径下创建 AIGenStudio
      final primarySdcard = Directory('/sdcard/$appFolderName');
      if (!await primarySdcard.exists()) {
        await primarySdcard.create(recursive: true);
      }
      targetDir = primarySdcard;
    } catch (_) {
      try {
        final emulated = Directory('/storage/emulated/0/$appFolderName');
        if (!await emulated.exists()) {
          await emulated.create(recursive: true);
        }
        targetDir = emulated;
      } catch (_) {
        // 回退到 path_provider 获取的外部存储路径
        final extDir = await getExternalStorageDirectory();
        final fallback = Directory('${extDir?.path ?? (await getApplicationDocumentsDirectory()).path}/$appFolderName');
        if (!await fallback.exists()) {
          await fallback.create(recursive: true);
        }
        targetDir = fallback;
      }
    }

    if (subFolder != null && subFolder.isNotEmpty) {
      final sub = Directory('${targetDir.path}/$subFolder');
      if (!await sub.exists()) {
        await sub.create(recursive: true);
      }
      return sub;
    }

    return targetDir;
  }

  /// 保存文件到专用目录
  static Future<File> saveMediaFile({
    required List<int> bytes,
    required String filename,
    required String subFolder, // 'videos', 'audios', 'clones'
  }) async {
    final dir = await getAppOutputDirectory(subFolder: subFolder);
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }
}
