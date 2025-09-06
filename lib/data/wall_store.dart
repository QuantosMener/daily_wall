import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WallEntry {
  int id;
  DateTime day; // только дата (без времени)
  String body;  // текст или JSON Delta от редактора, либо 'local://<fileName>' или URL

  WallEntry({required this.id, required this.day, required this.body});

  Map<String, dynamic> toJson() => {
    'id': id,
    'day': _fmtDay(day),
    'body': body,
  };

  static WallEntry fromJson(Map<String, dynamic> m) => WallEntry(
    id: m['id'] as int,
    day: _parseDay(m['day'] as String),
    body: (m['body'] as String?) ?? '',
  );

  static String _fmtDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _parseDay(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }
}

class WallStore {
  WallStore._();
  static final WallStore instance = WallStore._();

  Future<Directory> _daysDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'daily_wall', 'days'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileForDay(DateTime day) async {
    final d = DateTime(day.year, day.month, day.day);
    final dir = await _daysDir();
    final name =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';
    return File(p.join(dir.path, name));
  }

  Future<List<WallEntry>> loadDay(DateTime day) async {
    final f = await _fileForDay(day);
    if (!await f.exists()) return [];
    final txt = await f.readAsString();
    if (txt.trim().isEmpty) return [];
    final decoded = jsonDecode(txt);
    if (decoded is! Map) return [];
    final list = (decoded['entries'] as List? ?? []);
    final res = list
        .whereType<Map>()
        .map((m) => WallEntry.fromJson(m.cast<String, dynamic>()))
        .toList();
    res.sort((a, b) => b.id.compareTo(a.id));
    return res;
  }

  Future<void> _writeDay(DateTime day, List<WallEntry> list) async {
    final f = await _fileForDay(day);
    final jsonMap = {'entries': list.map((e) => e.toJson()).toList()};
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonMap));
  }

  Future<WallEntry> addEntry(DateTime day, String body) async {
    final list = await loadDay(day);
    final id = DateTime.now().microsecondsSinceEpoch;
    final entry = WallEntry(id: id, day: DateTime(day.year, day.month, day.day), body: body);
    list.insert(0, entry);
    await _writeDay(day, list);
    return entry;
  }

  Future<void> updateEntry(DateTime day, int id, String body) async {
    final list = await loadDay(day);
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      list[i].body = body;
      await _writeDay(day, list);
    }
  }

  Future<void> deleteEntry(DateTime day, int id) async {
    final list = await loadDay(day);
    list.removeWhere((e) => e.id == id);
    await _writeDay(day, list);
  }

  /// Простой полнотекстовый поиск по всем дням.
  Future<List<WallEntry>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final dir = await _daysDir();
    final res = <WallEntry>[];
    if (await dir.exists()) {
      final files = await dir.list().where((e) => e is File && e.path.endsWith('.json')).toList();
      for (final ent in files) {
        final f = ent as File;
        try {
          final txt = await f.readAsString();
          final decoded = jsonDecode(txt);
          final list = (decoded['entries'] as List? ?? []);
          for (final m in list.whereType<Map>()) {
            final e = WallEntry.fromJson(m.cast<String, dynamic>());
            if (e.body.toLowerCase().contains(q)) {
              res.add(e);
            }
          }
        } catch (_) {}
      }
    }
    // свежие сверху
    res.sort((a, b) => b.id.compareTo(a.id));
    return res;
  }
}
