import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:url_launcher/url_launcher.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../app_nav_key.dart';
import '../data/wall_store.dart';
import '../data/files_store.dart';
import 'search_page.dart';
import 'widgets/note_editor.dart';

class DayWallPage extends StatefulWidget {
  const DayWallPage({super.key});

  @override
  State<DayWallPage> createState() => DayWallPageState();
}

class DayWallPageState extends State<DayWallPage> {
  DateTime _day = _truncate(DateTime.now());
  final List<WallEntry> _items = [];
  bool _loading = false;
  bool _dragging = false;

  static DateTime _truncate(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await WallStore.instance.loadDay(_day);
    setState(() {
      _items
        ..clear()
        ..addAll(list);
      _loading = false;
    });
  }

  Future<void> addBody(String body) async {
    final e = await WallStore.instance.addEntry(_day, body);
    setState(() => _items.insert(0, e));
  }

  Future<void> goToDay(DateTime day) async {
    setState(() => _day = _truncate(day));
    await _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      await goToDay(picked);
    }
  }

  Future<void> _prevDay() => goToDay(_day.subtract(const Duration(days: 1)));
  Future<void> _nextDay() => goToDay(_day.add(const Duration(days: 1)));

  // --- вставка из буфера: ТЕКСТ (без редактора) ---
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim();
    if (txt == null || txt.isEmpty) return;
    await addBody(txt);
  }

  // --- drag&drop изображений ---
  bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
  }

  Future<void> _handleDropFiles(List<dynamic> files) async {
    for (final f in files) {
      try {
        final String path = (f as dynamic).path as String;
        if (_isImagePath(path)) {
          final rel = await FilesStore.instance.copyImageFile(path);
          await addBody('local://$rel');
        } else {
          await addBody(path);
        }
      } catch (_) {}
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  // ---------- ВАЖНО: обновлённые методы создания/редактирования ----------
  Future<void> _addNote() async {
    final res = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NoteEditorDialog(title: 'Новая запись'),
    );
    if (res != null && res['delta'] != null) {
      final body = res['delta']!.trim();
      final e = await WallStore.instance.addEntry(_day, body);
      setState(() => _items.insert(0, e));
    }
  }

  Future<void> _editNote(int index) async {
    final it = _items[index];
    final res = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NoteEditorDialog(
        title: 'Редактирование',
        initialDelta: it.body, // передаём текущую Delta/текст
      ),
    );
    if (res != null && res['delta'] != null) {
      final newBody = res['delta']!.trim();
      await WallStore.instance.updateEntry(_day, it.id, newBody);
      setState(() => it.body = newBody);
    }
  }
  // -----------------------------------------------------------------------

  Future<void> _deleteItem(int index) async {
    final it = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await WallStore.instance.deleteEntry(_day, it.id);
      setState(() => _items.removeAt(index));
    }
  }

  int _crossAxisCountForWidth(double w) {
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 600) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = '${_day.year.toString().padLeft(4, '0')}-'
        '${_day.month.toString().padLeft(2, '0')}-'
        '${_day.day.toString().padLeft(2, '0')}';

    final gridOrEmpty = _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
        ? const Center(
      child: Text('Поки порожньо. Перетащите изображение или воспользуйтесь вставкой.'),
    )
        : LayoutBuilder(
      builder: (context, c) {
        final count = _crossAxisCountForWidth(c.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.25,
          ),
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final it = _items[i];
            return _Tile(
              body: it.body,
              onEdit: () => _editNote(i),
              onCopy: () => _copyToClipboard(_plainTextOf(it.body)),
              onDelete: () => _deleteItem(i),
            );
          },
        );
      },
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
          final pressed = HardwareKeyboard.instance.logicalKeysPressed;
          final isCtrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
              pressed.contains(LogicalKeyboardKey.controlRight);
          if (isCtrl) {
            final focused = FocusManager.instance.primaryFocus?.context?.widget;
            if (focused is! EditableText) {
              _pasteFromClipboard();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(dateStr),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Предыдущий день',
            onPressed: _prevDay,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Поиск',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchPage(
                      onOpenDay: (d) async { await goToDay(d); Navigator.of(context).pop(); },
                    ),
                  ),
                );

              },
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Следующий день',
              onPressed: _nextDay,
            ),
          ],
        ),
        body: Stack(
          children: [
            DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) async {
                setState(() => _dragging = false);
                await _handleDropFiles(details.files);
              },
              child: gridOrEmpty,
            ),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Отпустите, чтобы добавить изображение',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 90,
              child: FloatingActionButton(
                heroTag: 'paste_fab',
                mini: true,
                tooltip: 'Вставить из буфера',
                onPressed: _pasteFromClipboard,
                child: const Icon(Icons.paste),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'add_fab',
          onPressed: _addNote,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  String _plainTextOf(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is List && parsed.isNotEmpty) {
        final doc = quill.Document.fromJson(parsed);
        return doc.toPlainText();
      }
    } catch (_) {}
    return body;
  }
}

// ---------- Остальная часть файла (плитки/картинки) без изменений ----------
class _Tile extends StatelessWidget {
  final String body;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _Tile({
    required this.body,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });

  bool _isSingleUrl(String text) {
    final t = text.trim();
    final re = RegExp(r'^(https?:\/\/|www\.)\S+$', caseSensitive: false);
    return re.hasMatch(t);
  }

  Uri? _normalizeUrl(String text) {
    var t = text.trim();
    if (!_isSingleUrl(t)) return null;
    if (!t.toLowerCase().startsWith('http')) t = 'https://$t';
    return Uri.tryParse(t);
  }

  bool _isImageUrl(Uri uri) {
    final path = uri.path.toLowerCase();
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$').hasMatch(path)) return true;
    final fmt = uri.queryParameters['format']?.toLowerCase();
    const ok = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
    return fmt != null && ok.contains(fmt);
  }

  void _openUrl(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  void _openImageViewerFile(BuildContext ctx, String absPath) {
    showGeneralDialog(
      context: ctx,
      barrierLabel: 'image_view',
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.file(
                    File(absPath),
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, color: Colors.white70, size: 48),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                  tooltip: 'Закрыть',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openImageViewerUrl(BuildContext ctx, Uri uri) {
    showGeneralDialog(
      context: ctx,
      barrierLabel: 'image_view',
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.network(
                    uri.toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, color: Colors.white70, size: 48),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                  tooltip: 'Закрыть',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _imageThumbLocal(BuildContext context, String relName) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FutureBuilder<String>(
      future: FilesStore.instance.absolutePath(relName),
      builder: (ctx, snap) {
        final abs = snap.data;
        if (abs == null) {
          return Container(
            color: bg,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          onTap: () => _openImageViewerFile(context, abs),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: bg,
                child: Image.file(
                  File(abs),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => Container(
                    color: bg,
                    child: const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _imageThumbUrl(BuildContext context, Uri uri) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    return GestureDetector(
      onTap: () => _openImageViewerUrl(context, uri),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            color: bg,
            child: Image.network(
              uri.toString(),
              fit: BoxFit.contain,
              loadingBuilder: (c, child, ev) {
                if (ev == null) return child;
                final total = ev.expectedTotalBytes;
                final loaded = ev.cumulativeBytesLoaded;
                final val = (total != null && total > 0) ? loaded / total : null;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: bg),
                    Center(child: CircularProgressIndicator(value: val)),
                  ],
                );
              },
              errorBuilder: (c, e, s) => Container(
                color: bg,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (body.startsWith('local://')) {
      final rel = body.substring('local://'.length);
      return _card(context, content: _imageThumbLocal(context, rel));
    }

    List? delta;
    String plain = body;
    try {
      final parsed = jsonDecode(body);
      if (parsed is List && parsed.isNotEmpty) {
        delta = parsed;
        final doc = quill.Document.fromJson(parsed);
        plain = doc.toPlainText();
      }
    } catch (_) {}

    final uri = _normalizeUrl(plain);
    final isImgUrl = uri != null && _isImageUrl(uri);
    final base = Theme.of(context).textTheme.headlineSmall ?? const TextStyle(fontSize: 20);

    final Widget content = isImgUrl
        ? _imageThumbUrl(context, uri!)
        : (delta != null)
        ? SelectableText.rich(
      _spanFromDelta(delta, base),
      textAlign: TextAlign.center,
      maxLines: 12,
    )
        : SelectableText(
      plain,
      textAlign: TextAlign.center,
      maxLines: 8,
      style: base,
    );

    return _card(
      context,
      content: content,
      openUrl: (!isImgUrl && uri != null) ? () => _openUrl(uri) : null,
    );
  }

  TextSpan _spanFromDelta(List ops, TextStyle base) {
    final spans = <TextSpan>[];
    for (final op in ops.whereType<Map>()) {
      final insert = op['insert'];
      if (insert is! String) continue;
      final attrs = (op['attributes'] as Map?) ?? const {};
      var style = base;
      final size = attrs['size'];
      if (size == 'large') {
        style = style.copyWith(fontSize: (base.fontSize ?? 16) + 6, fontWeight: FontWeight.w600);
      } else if (size == 'small') {
        style = style.copyWith(fontSize: (base.fontSize ?? 16) - 2);
      }
      if (attrs['bold'] == true) style = style.copyWith(fontWeight: FontWeight.w700);
      if (attrs['italic'] == true) style = style.copyWith(fontStyle: FontStyle.italic);
      if (attrs['underline'] == true) {
        style = style.copyWith(decoration: TextDecoration.underline);
      }
      spans.add(TextSpan(text: insert, style: style));
    }
    return TextSpan(children: spans, style: base);
  }

  Widget _card(BuildContext context, {required Widget content, VoidCallback? openUrl}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(child: Center(child: content)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (openUrl != null)
                  IconButton(
                    tooltip: 'Открыть ссылку',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: openUrl,
                  ),
                IconButton(
                  tooltip: 'Редактировать',
                  icon: const Icon(Icons.edit),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Копировать',
                  icon: const Icon(Icons.copy_all),
                  onPressed: onCopy,
                ),
                IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
