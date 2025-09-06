import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Диалог создания/редактирования записи.
/// При закрытии возвращает: {'delta': '<json delta>'}
class NoteEditorDialog extends StatefulWidget {
  const NoteEditorDialog({
    super.key,
    this.initialDelta,
    this.title,
  });

  final String? initialDelta; // JSON Delta или обычный текст
  final String? title;

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final quill.QuillController _controller;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  // Состояния для собственной панели форматирования
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  String _size = 'normal';   // 'small' | 'normal' | 'large'
  String _align = 'center';  // 'left'  | 'center' | 'right'

  @override
  void initState() {
    super.initState();

    final doc = _buildInitialDoc(widget.initialDelta);

    // v11: контроллер через basic + config, после чего задаём документ
    _controller = quill.QuillController.basic(
      config: const quill.QuillControllerConfig(),
    );
    _controller.document = doc;

    // По умолчанию выравнивание по центру, если документ пуст
    if (_controller.document.toPlainText().trim().isEmpty) {
      _controller.formatSelection(_alignAttr('center'));
    }

    _controller.addListener(_syncToolbarFromSelection);

    // Дадим фокус редактору после отрисовки — покажет каретку и позволит ввод
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_syncToolbarFromSelection);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  quill.Document _buildInitialDoc(String? deltaOrText) {
    if (deltaOrText == null || deltaOrText.trim().isEmpty) {
      return quill.Document()..insert(0, '');
    }
    try {
      final parsed = jsonDecode(deltaOrText);
      if (parsed is List && parsed.isNotEmpty) {
        return quill.Document.fromJson(parsed);
      }
    } catch (_) {}
    return quill.Document()..insert(0, deltaOrText);
  }

  // Универсальные атрибуты
  quill.Attribute<String?> _sizeAttr(String? v) =>
      quill.Attribute<String?>('size', quill.AttributeScope.inline, v);
  quill.Attribute<String?> _alignAttr(String v) =>
      quill.Attribute<String?>('align', quill.AttributeScope.block, v);

  void _syncToolbarFromSelection() {
    final s = _controller.getSelectionStyle();
    final bold = s.attributes.containsKey(quill.Attribute.bold.key);
    final italic = s.attributes.containsKey(quill.Attribute.italic.key);
    final underline = s.attributes.containsKey(quill.Attribute.underline.key);
    final sizeVal = s.attributes[quill.Attribute.size.key]?.value;
    final alignVal = (s.attributes['align']?.value as String?) ?? _align;

    setState(() {
      _isBold = bold;
      _isItalic = italic;
      _isUnderline = underline;
      _size = (sizeVal == 'large')
          ? 'large'
          : (sizeVal == 'small')
          ? 'small'
          : 'normal';
      _align = (alignVal == 'left' || alignVal == 'right' || alignVal == 'center')
          ? alignVal
          : 'center';
    });
  }

  void _toggleInline(quill.Attribute attr) {
    final has = _controller.getSelectionStyle().attributes.containsKey(attr.key);
    _controller.formatSelection(has ? quill.Attribute.clone(attr, null) : attr);
  }

  void _setSize(String v) {
    if (v == 'normal') {
      _controller.formatSelection(quill.Attribute.clone(_sizeAttr(null), null));
    } else {
      _controller.formatSelection(_sizeAttr(v)); // 'small' | 'large'
    }
  }

  void _setAlign(String v) {
    _controller.formatSelection(_alignAttr(v)); // 'left' | 'center' | 'right'
  }

  void _insertNewline() {
    final sel = _controller.selection;
    final base = sel.baseOffset;
    final extent = sel.extentOffset;
    final hasSelection = base >= 0 && extent >= 0 && base != extent;

    final index = (base >= 0) ? base : _controller.document.length;
    final length = hasSelection ? (extent - base).abs() : 0;

    _controller.replaceText(
      index,
      length,
      '\n',
      TextSelection.collapsed(offset: index + 1),
    );
  }

  void _submit() {
    final text = _controller.document.toPlainText().trim();
    if (text.isEmpty) return;
    final delta = _controller.document.toDelta().toJson();
    Navigator.of(context).pop({'delta': jsonEncode(delta)});
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    final titleText = widget.title ?? 'Новая запись';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 580),
        child: Column(
          children: [
            // Шапка
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(titleText, style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Мини-тулбар по ТЗ
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  // Выравнивание
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left',   icon: Icon(Icons.format_align_left)),
                      ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center)),
                      ButtonSegment(value: 'right',  icon: Icon(Icons.format_align_right)),
                    ],
                    selected: {_align},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setState(() => _align = v);
                      _setAlign(v);
                    },
                  ),
                  // Размер шрифта
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'large',  label: Text('Заголовок')),
                      ButtonSegment(value: 'normal', label: Text('Обычный')),
                      ButtonSegment(value: 'small',  label: Text('Примечание')),
                    ],
                    selected: {_size},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setState(() => _size = v);
                      _setSize(v);
                    },
                  ),
                  // B / I / U
                  ToggleButtons(
                    isSelected: [_isBold, _isItalic, _isUnderline],
                    onPressed: (i) {
                      switch (i) {
                        case 0: _toggleInline(quill.Attribute.bold); break;
                        case 1: _toggleInline(quill.Attribute.italic); break;
                        case 2: _toggleInline(quill.Attribute.underline); break;
                      }
                    },
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.format_bold)),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.format_italic)),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.format_underline)),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Редактор + горячие клавиши (Enter = создать, Alt+Enter = перенос)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter): _EnterIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter): _EnterIntent(),
                    SingleActivator(LogicalKeyboardKey.enter, alt: true): _AltEnterIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter, alt: true): _AltEnterIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _EnterIntent: CallbackAction<_EnterIntent>(onInvoke: (e) {
                        _submit(); // не даём Quill вставить перенос
                        return null;
                      }),
                      _AltEnterIntent: CallbackAction<_AltEnterIntent>(onInvoke: (e) {
                        _insertNewline(); // вручную вставляем \n
                        return null;
                      }),
                    },
                    child: quill.QuillEditor(
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: const quill.QuillEditorConfig(
                        placeholder: 'Введите текст…',
                        padding: EdgeInsets.zero,
                        // readOnly=false по умолчанию в v11
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Подвал
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Text(
                    'Enter — создать,  Alt+Enter — новая строка',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Отмена'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check),
                    label: const Text('Добавить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Интенты для Shortcuts/Actions
class _EnterIntent extends Intent {
  const _EnterIntent();
}
class _AltEnterIntent extends Intent {
  const _AltEnterIntent();
}
