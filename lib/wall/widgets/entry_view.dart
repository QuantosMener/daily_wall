import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom; // <-- добавлено

/// Рендер одной плитки:
/// - если текст содержит хотя бы один http(s)-URL → карточка превью:
///     • ищем среди ВСЕХ URL картинку (по расширению или HEAD: Content-Type image/*);
///     • иначе берём первый URL и тянем og:image / twitter:image;
///     • иначе берём первую <img src|srcset>;
///     • иначе — favicon (из <link rel=icon> или google s2 favicons).
/// - local:// / file:// / абсолютный путь к изображению → миниатюра (contain) + fullscreen.
/// - иначе → текст с автолинками (SelectableText.rich).
class EntryView extends StatelessWidget {
  final String body;
  const EntryView({super.key, required this.body});

  static final _urlRe = RegExp(r'https?:\/\/\S+', caseSensitive: false);
  static const _imgExts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.avif'];

  @override
  Widget build(BuildContext context) {
    final text = body.trim();

    // 1) есть URL → карточка
    final urls = _urlRe.allMatches(text).map((m) => _normalizeUrl(m.group(0)!)).toList();
    if (urls.isNotEmpty) {
      return _UrlPreviewTile(urls: urls);
    }

    // 2) локальная картинка
    if (_looksLikeLocalImage(text)) {
      return _ImageTile(ref: text);
    }

    // 3) чистый URL строкой (на всякий)
    if (_isPureUrl(text)) {
      return _UrlPreviewTile(urls: [_normalizeUrl(text)]);
    }

    // 4) обычный текст с автолинками
    return _linkifiedText(context, text);
  }

  static String _normalizeUrl(String s) =>
      s.replaceFirst(RegExp(r'[)\]\}\.\,\;\:\!\?…]+$'), '');

  static bool _isPureUrl(String s) {
    if (!s.startsWith('http://') && !s.startsWith('https://')) return false;
    final u = Uri.tryParse(s);
    return u != null && (u.scheme == 'http' || u.scheme == 'https');
  }

  static bool _looksLikeLocalImage(String s) {
    if (s.startsWith('local://') || s.startsWith('file://') || s.startsWith('/')) {
      final ext = p.extension(s).toLowerCase();
      return _imgExts.contains(ext);
    }
    return false;
  }

  Widget _linkifiedText(BuildContext context, String text) {
    final base = Theme.of(context).textTheme.titleMedium!;
    final link = base.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      final url = _normalizeUrl(m.group(0)!);
      spans.add(
        TextSpan(
          text: url,
          style: link,
          recognizer: TapGestureRecognizer()
            ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));

    return SelectableText.rich(TextSpan(children: spans));
  }
}

/// Карточка превью для набора URL.
class _UrlPreviewTile extends StatefulWidget {
  final List<String> urls;
  const _UrlPreviewTile({required this.urls});

  @override
  State<_UrlPreviewTile> createState() => _UrlPreviewTileState();
}

class _UrlPreviewTileState extends State<_UrlPreviewTile> {
  String? _title;
  String? _imageUrl;
  late final Uri _primary;

  static const _imgExts = EntryView._imgExts;

  @override
  void initState() {
    super.initState();
    _primary = Uri.parse(widget.urls.first);
    _resolvePreview();
  }

  Future<void> _resolvePreview() async {
    // 1) явная картинка по расширению
    for (final u in widget.urls) {
      final uri = Uri.parse(u);
      final ext = p.extension(uri.path).toLowerCase();
      if (_imgExts.contains(ext)) {
        setState(() {
          _imageUrl = u;
          _title = uri.host;
        });
        return;
      }
    }

    // 2) HEAD → Content-Type image/*
    for (final u in widget.urls) {
      final uri = Uri.parse(u);
      if (await _isImageByHead(uri)) {
        setState(() {
          _imageUrl = u;
          _title = uri.host;
        });
        return;
      }
    }

    // 3) метаданные страницы по первому URL
    await _fetchPageMeta(_primary);

    // 4) если ничего, то favicon как миниатюра
    if (_imageUrl == null) {
      _imageUrl = _faviconFor(_primary, _lastFetchedDoc);
      setState(() {
        _title ??= _primary.host;
      });
    }
  }

  Future<bool> _isImageByHead(Uri uri) async {
    try {
      final head = await http
          .head(uri, headers: const {'User-Agent': 'Mozilla/5.0 (Flutter)', 'Accept': 'image/*'})
          .timeout(const Duration(seconds: 6));
      final ct = head.headers['content-type']?.toLowerCase() ?? '';
      return head.statusCode >= 200 && head.statusCode < 400 && ct.startsWith('image/');
    } catch (_) {
      return false;
    }
  }

  dom.Document? _lastFetchedDoc;

  Future<void> _fetchPageMeta(Uri uri) async {
    try {
      final resp = await http
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0 (Flutter)'})
          .timeout(const Duration(seconds: 8));

      if (!(resp.statusCode >= 200 && resp.statusCode < 400)) {
        setState(() => _title = uri.host);
        return;
      }

      final doc = html_parser.parse(resp.body);
      _lastFetchedDoc = doc;

      String? title =
          doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
              doc.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
              doc.querySelector('title')?.text.trim();

      // og/twitter картинка
      String? img =
          doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
              doc.querySelector('meta[name="twitter:image"]')?.attributes['content'];

      // если нет — первая <img>
      if (img == null || img.isEmpty) {
        final imgEl = doc.querySelector('img[src], img[srcset]');
        final srcset = imgEl?.attributes['srcset'];
        if (srcset != null && srcset.isNotEmpty) {
          // берём первый URL из srcset
          final first = srcset.split(',').first.trim().split(' ').first.trim();
          img = first;
        } else {
          img = imgEl?.attributes['src'];
        }
      }

      if (img != null && img.isNotEmpty) {
        // резолв относительного пути
        final u = Uri.tryParse(img);
        if (u == null || !u.hasScheme) {
          img = uri.resolve(img).toString();
        }
      }

      setState(() {
        _title = (title != null && title.trim().isNotEmpty) ? title.trim() : uri.host;
        _imageUrl = (img != null && img.trim().isNotEmpty) ? img.trim() : null;
      });
    } catch (_) {
      setState(() => _title = uri.host);
    }
  }

  String? _faviconFor(Uri uri, dom.Document? doc) {
    // из <link rel="icon">, <link rel="shortcut icon">, <link rel="apple-touch-icon"> …
    final candidates = <String>[];
    if (doc != null) {
      for (final el in doc.querySelectorAll('link[rel*="icon"]')) {
        final href = el.attributes['href'];
        if (href != null && href.trim().isNotEmpty) candidates.add(href.trim());
      }
      for (final el in doc.querySelectorAll('link[rel*="apple-touch-icon"]')) {
        final href = el.attributes['href'];
        if (href != null && href.trim().isNotEmpty) candidates.add(href.trim());
      }
    }
    for (final h in candidates) {
      final u = Uri.tryParse(h);
      final absolute = (u == null || !u.hasScheme) ? uri.resolve(h).toString() : h;
      return absolute;
    }
    // fall back: google s2 favicons (стабильно и быстро)
    return 'https://www.google.com/s2/favicons?domain=${uri.host}&sz=64';
  }

  void _open() => launchUrl(_primary, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final title = _title ?? _primary.host;

    return InkWell(
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_imageUrl != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 160),
              child: Center(
                child: Image.network(
                  _imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.link, size: 32),
                ),
              ),
            )
          else
            Container(
              height: 80,
              alignment: Alignment.center,
              child: const Icon(Icons.link, size: 28),
            ),
          const SizedBox(height: 8),
          SelectableText(
            title,
            maxLines: 2,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatefulWidget {
  final String ref; // local://name | file://path | /absolute/path
  const _ImageTile({required this.ref});

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  File? _file;
  Object? _err;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final path = await _resolvePath(widget.ref);
      final f = File(path);
      if (await f.exists()) {
        setState(() => _file = f);
      } else {
        setState(() => _err = 'not_found');
      }
    } catch (e) {
      setState(() => _err = e);
    }
  }

  Future<String> _resolvePath(String ref) async {
    if (ref.startsWith('file://')) return ref.substring('file://'.length);
    if (ref.startsWith('/')) return ref;
    if (ref.startsWith('local://')) {
      final base = await getApplicationDocumentsDirectory();
      final name = ref.substring('local://'.length);
      return p.join(base.path, 'daily_wall', 'media', name);
    }
    throw 'unsupported';
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return Text('Image not available', style: Theme.of(context).textTheme.bodySmall);
    }
    if (_file == null) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    }

    return GestureDetector(
      onTap: () => _openFullScreen(context, _file!),
      child: Container(
        constraints: const BoxConstraints(minHeight: 120, maxHeight: 260),
        alignment: Alignment.center,
        child: Image.file(_file!, fit: BoxFit.contain),
      ),
    );
  }

  void _openFullScreen(BuildContext context, File file) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
