import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../data/wall_store.dart';

class SearchPage extends StatefulWidget {
  final Future<void> Function(DateTime day) onOpenDay;
  const SearchPage({super.key, required this.onOpenDay});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  List<WallEntry> _results = const [];
  bool _loading = false;

  Timer? _debounce;
  int _issued = 0;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _plainFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        final buf = StringBuffer();
        for (final op in decoded) {
          if (op is Map && op['insert'] is String) buf.write(op['insert']);
        }
        return buf.toString();
      }
    } catch (_) {}
    return body;
  }

  Future<void> _run([String? q]) async {
    final query = (q ?? _c.text).trim();
    _lastQuery = query;

    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }

    final ticket = ++_issued;
    setState(() => _loading = true);

    final list = await WallStore.instance.search(query);
    if (!mounted || ticket != _issued) return;

    setState(() {
      _results = list;
      _loading = false;
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(v));
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Подсветка вхождений без унаследованных украшений.
  InlineSpan _highlightSpan(BuildContext context, String source, String query) {
    final theme = Theme.of(context);
    final base = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(decoration: TextDecoration.none, fontStyle: FontStyle.normal, fontWeight: FontWeight.normal);
    final normal = base;
    final hl = base.copyWith(
      backgroundColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    );

    if (query.isEmpty) return TextSpan(text: source, style: normal);

    final lower = source.toLowerCase();
    final q = query.toLowerCase();

    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: source.substring(start), style: normal));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: source.substring(start, idx), style: normal));
      }
      spans.add(TextSpan(text: source.substring(idx, idx + q.length), style: hl));
      start = idx + q.length;
    }
    return TextSpan(children: spans, style: normal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _c,
              focusNode: _focus,
              decoration: InputDecoration(
                hintText: 'Что ищем...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _run,
                  tooltip: 'Поиск',
                ),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? const Center(child: Text('Ничего не найдено'))
                  : ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = _results[i];
                  final day = e.day;
                  final date = _fmtDate(day);

                  final plain = _plainFromBody(e.body);
                  final oneLine = plain.replaceAll('\n', ' ');
                  final preview = oneLine.length > 200 ? '${oneLine.substring(0, 200)}…' : oneLine;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    title: Text(date, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: RichText(
                      textAlign: TextAlign.left,
                      text: _highlightSpan(context, preview, _lastQuery),
                    ),
                    onTap: () async => widget.onOpenDay(day),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
