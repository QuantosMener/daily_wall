import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FilesStore {
  FilesStore._();
  static final FilesStore instance = FilesStore._();

  Directory? _mediaDir;

  Future<Directory> _ensureMediaDir() async {
    if (_mediaDir != null) return _mediaDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'daily_wall', 'media'));
    await dir.create(recursive: true);
    _mediaDir = dir;
    return dir;
  }

  /// Сохраняет байты картинки. Возвращает относительное имя файла (например, `img_1694000000000.png`).
  Future<String> saveImageBytes(Uint8List bytes, {String ext = 'png'}) async {
    final dir = await _ensureMediaDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeExt = ext.replaceAll('.', '');
    final name = 'img_$ts.$safeExt';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return name;
  }

  /// Копирует локальный файл в медиа-папку. Возвращает относительное имя файла.
  Future<String> copyImageFile(String srcPath) async {
    final dir = await _ensureMediaDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(srcPath); // c точкой
    final name = 'img_$ts$ext';
    final dst = File(p.join(dir.path, name));
    await File(srcPath).copy(dst.path);
    return name;
  }

  /// Абсолютный путь по относительному имени (что мы храним в базе).
  Future<String> absolutePath(String relName) async {
    final dir = await _ensureMediaDir();
    return p.join(dir.path, relName);
  }
}
