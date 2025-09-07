import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_handler/share_handler.dart';

// Імпорт WallStore з lib/data/
import 'package:daily_wall/data/wall_store.dart';

/// Обробник Android «Поделиться»: автоматично додає записи
/// у стіну поточного дня (текст/URL та зображення).
class ShareIntake {
  ShareIntake._();

  static StreamSubscription<SharedMedia>? _sub;

  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    final handler = ShareHandlerPlatform.instance;

    // 1) Обробити холодний запуск через intent
    try {
      final initial = await handler.getInitialSharedMedia();
      if (initial != null) {
        await _process(initial);
      }
    } catch (_) {
      // ignore
    }

    // 2) Слухати шарінг, коли апка вже відкрита
    await _sub?.cancel();
    _sub = handler.sharedMediaStream.listen((media) async {
      await _process(media);
    });
  }

  static Future<void> _process(SharedMedia media) async {
    final today = DateTime.now();
    final store = WallStore.instance;

    // Текст/URL
    final text = media.content?.trim();
    if (text != null && text.isNotEmpty) {
      await store.addEntry(today, text);
    }

    // Вкладення (зображення тощо)
    final atts = media.attachments ?? const <SharedAttachment?>[];
    for (final a in atts) {
      final att = a;
      if (att == null) continue;
      final path = att.path;

      if (att.type == SharedAttachmentType.image && path != null && path.isNotEmpty) {
        // Прагнемо скопіювати в документи апки
        final savedName = await _saveSharedFile(File(path));
        if (savedName != null) {
          await store.addEntry(today, 'local://$savedName');
        } else {
          // Фоллбек: залишаємо прямий шлях (file:// або абсолютний) — EntryView вміє це показувати
          final fallback = path.startsWith('file://') ? path : 'file://$path';
          await store.addEntry(today, fallback);
        }
      } else {
        // TODO: pdf/doc/xls/txt у наступній ітерації (мініатюри/прев'ю).
      }
    }
  }

  /// Копіює файл у теку документів застосунку: daily_wall/media
  /// і повертає лише імʼя файлу. Якщо копіювання неможливе — повертає null.
  static Future<String?> _saveSharedFile(File src) async {
    try {
      if (!await src.exists()) return null;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'daily_wall', 'media'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ext = p.extension(src.path);
      final name = 'share_${DateTime.now().microsecondsSinceEpoch}$ext';
      final dst = File(p.join(dir.path, name));
      await src.copy(dst.path);
      return name;
    } catch (_) {
      return null;
    }
  }
}
