import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../data/wall_store.dart';
import 'search_page.dart';
import 'widgets/entry_view.dart';

class DayWallPage extends StatefulWidget {
  const DayWallPage({super.key});

  @override
  State<DayWallPage> createState() => _DayWallPageState();
}

class _DayWallPageState extends State<DayWallPage> {
  DateTime _day = _strip(DateTime.now());
  List<WallEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  static DateTime _strip(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _loadDay() async {
    setState(() => _loading = true);
    final items = await WallStore.instance.loadDay(_day);
    if (!mounted) return;
    setState(() {
      _entries = items;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null && picked != _day) {
      setState(() => _day = _strip(picked));
      await _loadDay();
    }
  }

  void _prev() {
    setState(() => _day = _strip(_day.subtract(const Duration(days: 1))));
    _loadDay();
  }

  void _next() {
    setState(() => _day = _strip(_day.add(const Duration(days: 1))));
    _loadDay();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    await WallStore.instance.addEntry(_day, text);
    await _loadDay();
  }

  Future<void> _onAdd() async {
    if (!mounted) return;
    // Заглушка: реальный note_editor подключим отдельно.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Открытие редактора будет подключено отдельно')),
    );
  }

  Future<void> _onEdit(WallEntry e) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Редактор будет подключён (только по кнопке)')),
    );
  }

  Future<void> _onCopy(WallEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано')),
    );
  }

  Future<void> _onDelete(WallEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    ) ??
        false;
    if (!ok) return;

    var deleted = false;
    try {
      final s = WallStore.instance as dynamic;
      final id = (e as dynamic).id;
      try { await s.deleteEntry(id); deleted = true; } catch (_) {}
      if (!deleted) { try { await s.removeEntry(id); deleted = true; } catch (_) {} }
      if (!deleted) { try { await s.remove(id); deleted = true; } catch (_) {} }
      if (!deleted) { try { await s.removeById(id); deleted = true; } catch (_) {} }
      if (!deleted) { try { await s.delete(id); deleted = true; } catch (_) {} }
    } catch (_) { deleted = false; }

    if (!mounted) return;

    if (deleted) {
      await _loadDay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Удалено')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Удаление не поддержано текущим WallStore')),
      );
    }
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final title = GestureDetector(
      onTap: _pickDate, // календарь по нажатию на дату
      child: Text(_fmt(_day), style: Theme.of(context).textTheme.titleLarge),
    );

    return Scaffold(
      appBar: AppBar(
        title: Center(child: title), // дата по центру
        leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prev), // ◀
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(
                    onOpenDay: (DateTime d) async {
                      setState(() => _day = _strip(d));
                      await _loadDay();
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _next), // ▶
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
        child: Text(
          'Поки порожньо. Перетягніть зображення або скористайтеся вставкою з буфера.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      )
          : LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          int cross = 2;
          if (w < 500) {
            cross = 1;
          } else if (w > 900) {
            cross = 3;
          }

          return MasonryGridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: cross,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            itemCount: _entries.length,
            itemBuilder: (context, i) {
              final e = _entries[i];
              return _Tile(
                body: e.body,
                onEdit: () => _onEdit(e),
                onCopy: () => _onCopy(e),
                onDelete: () => _onDelete(e),
              );
            },
          );
        },
      ),

      // ДВА МАЛЕНЬКИХ FAB (вертикально), SafeArea — чтобы не упираться в жестовую панель
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SafeArea(
        minimum: const EdgeInsets.only(bottom: 10, right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'paste',
              onPressed: _pasteFromClipboard,
              tooltip: 'Вставить из буфера',
              child: const Icon(Icons.content_paste),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'add',
              onPressed: _onAdd,
              tooltip: 'Новая запись',
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка: содержимое (~H2) + три ИКОНКИ ВЕРТИКАЛЬНО справа.
/// Панель действий больше НЕ растягивается по высоте — переполнение исключено.
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

  // размеры панели действий
  static const double _railWidth = 44.0;
  static const double _iconSize = 18.0;
  static const double _btnSize = 32.0; // ровно 32х32
  static const double _spacing = 4.0;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Stack(
        children: [
          // Контент с отступом справа под колонку иконок
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, _railWidth, 12),
            child: EntryView(body: body),
          ),

          // Вертикальная колонка иконок, не растягивается по высоте карточки
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniAction(Icons.edit, onEdit),
                  SizedBox(height: _spacing),
                  _miniAction(Icons.delete_outline, onDelete),
                  SizedBox(height: _spacing),
                  _miniAction(Icons.copy, onCopy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(IconData icon, VoidCallback onTap) {
    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        radius: _btnSize / 2 + 2,
        child: SizedBox(
          width: _btnSize,
          height: _btnSize,
          child: Center(child: Icon(icon, size: _iconSize)),
        ),
      ),
    );
  }
}
