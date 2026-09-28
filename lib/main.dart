import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'dart:ui' show AppExitResponse;
import 'document.dart';
import 'figma_import.dart';

void main() => runApp(const FrameApp());

class FrameApp extends StatelessWidget {
  const FrameApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Frame',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF6750A4),
      scaffoldBackgroundColor: const Color(0xFFF5F5F8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 13)),
    ),
    home: const Editor(),
  );
}

class Editor extends StatefulWidget {
  const Editor({super.key});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  late final AppLifecycleListener lifecycle;
  @override
  void initState() {
    super.initState();
    lifecycle = AppLifecycleListener(
      onExitRequested: () async => await confirmReplace()
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
  }

  @override
  void dispose() {
    lifecycle.dispose();
    super.dispose();
  }

  DesignDocument doc = DesignDocument.sample();
  String? selected, editingComponent, filePath;
  int screen = 0;
  bool interact = false, dirty = false;
  double previewWidth = 390, zoom = 1;
  String status = 'Local workspace · no account required';
  final undo = <String>[], redo = <String>[];
  final images = <String, Uint8List>{};
  Offset? dragGlobal;
  DesignNode get root => editingComponent != null
      ? doc.components[editingComponent]!
      : doc.screens[screen];
  DesignNode? get selection => selected == null ? null : doc.find(selected!);
  void message(String text) {
    if (!mounted) return;
    setState(() => status = text);
  }

  void mutate(VoidCallback action) {
    setState(() {
      undo.add(doc.encode());
      while (undo.length > 80 ||
          undo.fold<int>(0, (sum, s) => sum + s.length) > 64000000) {
        undo.removeAt(0);
      }
      redo.clear();
      action();
      dirty = true;
    });
  }

  void history(bool back) {
    final from = back ? undo : redo, to = back ? redo : undo;
    if (from.isEmpty) return;
    setState(() {
      to.add(doc.encode());
      doc = DesignDocument.decode(from.removeLast());
      screen = screen.clamp(0, doc.screens.length - 1);
      previewWidth =
          (doc.screens[screen].props['width'] as num?)?.toDouble() ?? 390;
      editingComponent = null;
      selected = null;
      dirty = true;
    });
  }

  Color color(dynamic value, String fallback) =>
      Color(int.parse(argbHex(doc.hex(value, fallback)), radix: 16));
  Widget button(String title, IconData icon, VoidCallback? action) =>
      TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 17),
        label: Text(title),
      );
  Future<String?> ask(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit transition, not while its TextField remains mounted.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  Future<bool> confirmReplace() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text(
              'Save your project before replacing it, or discard these changes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> save({bool as = false}) async {
    try {
      final path = !as && filePath != null
          ? filePath
          : (await getSaveLocation(
              suggestedName: 'workspace.canvas.json',
              acceptedTypeGroups: [
                const XTypeGroup(label: 'Canvas project', extensions: ['json']),
              ],
            ))?.path;
      if (path == null) return;
      // Write a sibling first so a failed write never destroys the previous project.
      final snapshot = doc.encode();
      if (snapshot.length > maxDocumentBytes)
        throw const FormatException(
          'Project exceeds 32 MB. Remove large artwork or split screens into separate projects.',
        );
      final temp = File('$path.pending');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(path);
      setState(() {
        filePath = path;
        dirty = doc.encode() != snapshot;
        status = 'Saved to $path';
      });
    } catch (e) {
      message('Save failed: $e. Your changes remain in memory.');
    }
  }

  Future<void> open() async {
    if (!await confirmReplace()) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Canvas project', extensions: ['json']),
        ],
      );
      if (file == null) return;
      final loaded = DesignDocument.decode(await file.readAsString());
      setState(() {
        doc = loaded;
        images.clear();
        filePath = file.path;
        screen = 0;
        previewWidth =
            (doc.screens.first.props['width'] as num?)?.toDouble() ?? 390;
        selected = null;
        editingComponent = null;
        undo.clear();
        redo.clear();
        dirty = false;
        status = 'Opened ${file.name}';
      });
    } catch (e) {
      message('Open failed: $e. Current project was preserved.');
    }
  }

  Future<void> export() async {
    try {
      final path = (await getSaveLocation(
        suggestedName: 'generated_ui.dart',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Dart source', extensions: ['dart']),
        ],
      ))?.path;
      if (path == null) return;
      if (path == filePath)
        throw const FormatException('Export cannot overwrite your project.');
      await File(path).writeAsString(doc.exportDart(), flush: true);
      message('Exported $path · implement callbacks in your own files');
    } catch (e) {
      message('Export failed: $e');
    }
  }

  Future<void> importFigma() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Figma bridge package', extensions: ['json']),
        ],
      );
      if (file == null) return;
      final imported = importFigmaPackage(await file.readAsString());
      DesignDocument.decode(
        DesignDocument(
          [...doc.screens, ...imported.screens],
          components: doc.components,
          tokens: doc.tokens,
        ).encode(),
      );
      mutate(() {
        doc.screens.addAll(imported.screens);
        screen = doc.screens.length - imported.screens.length;
        previewWidth =
            (imported.screens.first.props['width'] as num?)?.toDouble() ?? 390;
        editingComponent = null;
        selected = null;
      });
      message(
        'Imported ${imported.screens.length} screen(s). ${imported.warnings.length} conversion warning(s).',
      );
      if (imported.warnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Figma import report'),
            content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                child: Text(imported.warnings.join('\n\n')),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      message('Import failed: $e. Current project was preserved.');
    }
  }

  void insert(String payload, DesignNode target) {
    if (!isLayout(target.type)) {
      message('Drop into a Column, Row, Container, or Stack.');
      return;
    }
    if (payload.startsWith('move:')) {
      final node = doc.find(payload.substring(5));
      if (node == null ||
          node == root ||
          node.walk.any((n) => n.id == target.id)) {
        message('Cannot move a parent into itself or its descendants.');
        return;
      }
      final parent = doc.parent(node.id);
      if (parent == null) return;
      mutate(() {
        parent.children.remove(node);
        target.children.add(node);
      });
    } else {
      if (payload.startsWith('component:') && editingComponent != null) {
        message('Nested component instances are not supported in this MVP.');
        return;
      }
      final node = payload.startsWith('component:')
          ? DesignNode(
              'Instance',
              name: payload.substring(10),
              props: {'component': payload.substring(10)},
            )
          : DesignNode(
              payload,
              props: payload == 'Text'
                  ? {'text': 'New text', 'fontSize': 16}
                  : payload == 'Button'
                  ? {
                      'text': 'Button',
                      'background': '@accent',
                      'color': '#FFFFFF',
                    }
                  : payload == 'Input'
                  ? {'text': 'Enter text'}
                  : payload == 'Container'
                  ? {'padding': 16, 'background': '@surface', 'radius': 12}
                  : payload == 'Stack'
                  ? {'width': 320, 'height': 240}
                  : {},
            );
      mutate(() {
        target.children.add(node);
        selected = node.id;
      });
    }
  }

  Future<void> makeComponent() async {
    final n = selection;
    if (n == null ||
        n == root ||
        n.type == 'Instance' ||
        editingComponent != null) {
      message('Select a widget or subtree on a screen first.');
      return;
    }
    if (n.walk.any((c) => c.type == 'Instance')) {
      message('Choose a subtree without component instances.');
      return;
    }
    final name = await ask('Component name', initial: 'Reusable ${n.name}');
    if (name == null) return;
    if (doc.components.containsKey(name)) {
      message('A component with that name already exists.');
      return;
    }
    final parent = doc.parent(n.id)!;
    mutate(() {
      final definition = doc.clone(n)..name = name;
      doc.components[name] = definition;
      final instance = DesignNode(
        'Instance',
        name: name,
        props: {
          'component': name,
          if (n.props.containsKey('left')) 'left': n.props['left'],
          if (n.props.containsKey('top')) 'top': n.props['top'],
        },
      );
      parent.children[parent.children.indexOf(n)] = instance;
      selected = instance.id;
    });
  }

  Widget dragItem(
    String label,
    String data,
    IconData icon, {
    VoidCallback? onTap,
  }) => Draggable<String>(
    data: data,
    feedback: Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(label)),
    ),
    child: Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 18),
        title: Text(label),
        trailing: const Icon(Icons.drag_indicator, size: 16),
        onTap: onTap,
      ),
    ),
  );
  Widget heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.2,
      ),
    ),
  );
  Widget panel(Widget child, {double width = 250}) => Container(
    width: width,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: Color(0xFFE3E3EB))),
    ),
    child: Material(color: Colors.transparent, child: child),
  );
  Widget layer(DesignNode n, [int depth = 0]) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DragTarget<String>(
        onWillAcceptWithDetails: (_) => isLayout(n.type),
        onAcceptWithDetails: (d) => insert(d.data, n),
        builder: (ctx, candidates, _) => Container(
          color: candidates.isNotEmpty
              ? const Color(0xFFEDE5FF)
              : selected == n.id
              ? const Color(0xFFF0EBFA)
              : null,
          padding: EdgeInsets.only(left: depth * 12.0),
          child: dragItem(
            n.name,
            'move:${n.id}',
            isLayout(n.type)
                ? Icons.folder_outlined
                : n.type == 'Instance'
                ? Icons.diamond_outlined
                : Icons.widgets_outlined,
            onTap: () => setState(() => selected = n.id),
          ),
        ),
      ),
      ...n.children.map((c) => layer(c, depth + 1)),
    ],
  );
  Widget leftPanel() => panel(
    ListView(
      children: [
        heading('SCREENS'),
        for (var i = 0; i < doc.screens.length; i++)
          ListTile(
            dense: true,
            selected: editingComponent == null && screen == i,
            leading: const Icon(Icons.phone_android, size: 18),
            title: Text(doc.screens[i].name),
            onTap: () => setState(() {
              screen = i;
              previewWidth =
                  (doc.screens[i].props['width'] as num?)?.toDouble() ?? 390;
              editingComponent = null;
              selected = null;
            }),
          ),
        button('Add screen', Icons.add, () async {
          final name = await ask(
            'Screen name',
            initial: 'Screen ${doc.screens.length + 1}',
          );
          if (name != null)
            mutate(() {
              doc.screens.add(
                DesignNode(
                  'Column',
                  name: name,
                  props: {'padding': 24, 'gap': 12},
                ),
              );
              screen = doc.screens.length - 1;
              selected = null;
              editingComponent = null;
            });
        }),
        heading('WIDGETS · DRAG OR CLICK'),
        for (final kind in kinds.where((kind) => kind != 'Artwork'))
          dragItem(
            kind,
            kind,
            kind == 'Text' ? Icons.text_fields : Icons.add_box_outlined,
            onTap: () => insert(
              kind,
              isLayout(selection?.type ?? '') ? selection! : root,
            ),
          ),
        heading('COMPONENTS'),
        if (doc.components.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Select a widget, then Create component.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final name in doc.components.keys)
          Row(
            children: [
              Expanded(
                child: dragItem(
                  name,
                  'component:$name',
                  Icons.diamond_outlined,
                  onTap: () => insert(
                    'component:$name',
                    isLayout(selection?.type ?? '') ? selection! : root,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit shared component',
                icon: const Icon(Icons.edit_outlined, size: 17),
                onPressed: () => setState(() {
                  editingComponent = name;
                  selected = doc.components[name]!.id;
                }),
              ),
            ],
          ),
        heading('LAYERS'),
        layer(root),
        const SizedBox(height: 20),
      ],
    ),
  );
  Widget field(
    DesignNode n,
    String key,
    String label, {
    bool numeric = false,
    String fallback = '',
  }) {
    final resolved = doc.resolve(n);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('${n.id}:$key:${resolved.props[key]}'),
        initialValue: (resolved.props[key] ?? fallback).toString(),
        decoration: InputDecoration(
          labelText: label,
          helperText: numeric ? 'Enter applies · blank resets' : null,
        ),
        onFieldSubmitted: (v) {
          if (numeric) {
            final value = double.tryParse(v);
            if (v.isNotEmpty &&
                (value == null ||
                    !value.isFinite ||
                    value < (['left', 'top'].contains(key) ? -10000 : 0) ||
                    value > 10000)) {
              message('Use a number from 0 to 10000.');
              return;
            }
            mutate(() {
              if (resolved.type == 'Text' &&
                  ['fontSize', 'textHeight', 'letterSpacing'].contains(key))
                n.props.remove('png');
              if (v.isEmpty)
                n.props.remove(key);
              else
                n.props[key] = value;
            });
          } else {
            if (['color', 'background'].contains(key) &&
                v.isNotEmpty &&
                !(validColor(v) ||
                    v.startsWith('@') &&
                        doc.tokens.containsKey(v.substring(1)))) {
              message('Use #RRGGBB or an existing @token.');
              return;
            }
            mutate(() {
              if (resolved.type == 'Text' &&
                  ['text', 'color', 'fontFamily'].contains(key))
                n.props.remove('png');
              if (v.isEmpty)
                n.props.remove(key);
              else
                n.props[key] = v;
            });
          }
        },
      ),
    );
  }

  Widget inspector() {
    final n = selection;
    final type = n == null ? '' : doc.resolve(n).type;
    return panel(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Inspector',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          if (n == null)
            const Text(
              'Select an element on the canvas or in Layers.\n\nChanges appear immediately. Press Enter to apply a field.',
            ),
          if (n != null) ...[
            Text(
              n.type == 'Instance'
                  ? 'Component instance · overrides'
                  : editingComponent != null
                  ? 'Shared component definition'
                  : '${n.type} properties',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey('name:${n.id}:${n.name}'),
              initialValue: n.name,
              decoration: const InputDecoration(labelText: 'Layer name'),
              onFieldSubmitted: (v) {
                if (v.trim().isNotEmpty) mutate(() => n.name = v.trim());
              },
            ),
            const SizedBox(height: 12),
            if (['Text', 'Button', 'Input'].contains(type))
              field(
                n,
                'text',
                type == 'Input' ? 'Placeholder' : 'Label / text',
                fallback: type,
              ),
            if (doc.resolve(n).props['png'] != null) ...[
              Text(
                type == 'Text'
                    ? 'Figma text appearance is preserved as an image. Editing text, size, or color switches to native text; the font may differ.'
                    : 'Figma artwork image. Move, resize, reuse, or attach an event. Edit vector paths and colors in Figma.',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (type == 'Text' && n.type != 'Instance')
                button(
                  'Use native Flutter text',
                  Icons.text_fields,
                  () => mutate(() => n.props.remove('png')),
                ),
              const SizedBox(height: 12),
            ],
            if (doc.parent(n.id)?.type == 'Stack') ...[
              field(n, 'left', 'X position', numeric: true, fallback: '0'),
              field(n, 'top', 'Y position', numeric: true, fallback: '0'),
            ],
            if (type == 'Text')
              field(n, 'fontSize', 'Font size', numeric: true, fallback: '16'),
            if (type == 'Text' && n.type != 'Instance')
              field(
                n,
                'fontFamily',
                'Font family · must be installed / bundled',
              ),
            if (['Text', 'Button'].contains(type))
              field(
                n,
                'color',
                'Text color · #hex or @token',
                fallback: type == 'Button' ? '#FFFFFF' : '#20212A',
              ),
            if (!['Spacer', 'Artwork'].contains(type))
              field(
                n,
                'background',
                'Background · #hex or @token',
                fallback: type == 'Button' ? '@accent' : '',
              ),
            if (!['Spacer', 'Artwork'].contains(type))
              field(
                n,
                'radius',
                'Corner radius',
                numeric: true,
                fallback: type == 'Button' ? '12' : '0',
              ),
            if (!['Button', 'Spacer'].contains(type)) ...[
              field(n, 'padding', 'Padding', numeric: true, fallback: '0'),
              field(n, 'width', 'Width · blank = automatic', numeric: true),
              field(n, 'height', 'Height · blank = automatic', numeric: true),
            ],
            if (type == 'Spacer') ...[
              field(n, 'width', 'Width', numeric: true, fallback: '24'),
              field(n, 'height', 'Height', numeric: true, fallback: '24'),
            ],
            if (isLayout(type) && type != 'Stack')
              field(n, 'gap', 'Child spacing', numeric: true, fallback: '12'),
            if ([
              'Button',
              'Input',
              'Artwork',
              'Text',
              'Stack',
            ].contains(type)) ...[
              const Divider(),
              const Text(
                'EVENT ASSIGNMENT',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              field(
                n,
                'event',
                type == 'Input'
                    ? 'onChanged · string handler key'
                    : type == 'Button'
                    ? 'onPressed · action key'
                    : 'onTap · action key',
              ),
              const Text(
                'Export receives typed callback maps. Interact mode reports events; it does not execute arbitrary Dart.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            if (n.type == 'Instance') ...[
              button(
                'Edit shared component',
                Icons.edit,
                () => setState(() {
                  editingComponent = n.props['component'];
                  selected = doc.components[editingComponent]!.id;
                }),
              ),
              button(
                'Reset instance overrides',
                Icons.restart_alt,
                () => mutate(() {
                  n.props = {'component': n.props['component']};
                }),
              ),
            ] else
              button('Create component', Icons.diamond_outlined, makeComponent),
            if (n != root)
              Wrap(
                children: [
                  button('Duplicate', Icons.copy, () {
                    final parent = doc.parent(n.id);
                    if (parent != null)
                      mutate(() {
                        final copy = doc.clone(n);
                        parent.children.insert(
                          parent.children.indexOf(n) + 1,
                          copy,
                        );
                        selected = copy.id;
                      });
                  }),
                  button('Delete', Icons.delete_outline, () {
                    final parent = doc.parent(n.id);
                    if (parent != null)
                      mutate(() {
                        parent.children.remove(n);
                        selected = null;
                      });
                  }),
                  button('Up', Icons.arrow_upward, () => reorder(n, -1)),
                  button('Down', Icons.arrow_downward, () => reorder(n, 1)),
                ],
              ),
          ],
          const Divider(height: 32),
          const Text(
            'SHARED COLOR TOKENS',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final entry in doc.tokens.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                key: ValueKey('${entry.key}:${entry.value}'),
                initialValue: entry.value,
                decoration: InputDecoration(
                  labelText: '@${entry.key}',
                  prefixIcon: Icon(
                    Icons.circle,
                    color: color(entry.value, '#000000'),
                  ),
                ),
                onFieldSubmitted: (v) {
                  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) {
                    message('Use #RRGGBB.');
                    return;
                  }
                  mutate(() => doc.tokens[entry.key] = v);
                },
              ),
            ),
          button('Add token', Icons.add, () async {
            final name = await ask('Token name (letters, digits, underscore)');
            if (name == null) return;
            if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(name) ||
                doc.tokens.containsKey(name)) {
              message('Use a unique token name.');
              return;
            }
            mutate(() => doc.tokens[name] = '#6750A4');
          }),
        ],
      ),
      width: 300,
    );
  }

  void reorder(DesignNode n, int direction) {
    final parent = doc.parent(n.id);
    if (parent == null) return;
    final i = parent.children.indexOf(n),
        next = parent.children.indexOf(n) + direction;
    if (next < 0 || next >= parent.children.length) return;
    mutate(() {
      parent.children.removeAt(i);
      parent.children.insert(next, n);
    });
  }

  Widget render(DesignNode original, {bool selectable = true}) {
    final n = doc.resolve(original), p = doc.resolve(original).props;
    final children = n.children
        .map(
          (c) =>
              render(c, selectable: selectable && original.type != 'Instance'),
        )
        .toList();
    void event([String? value]) => message(
      '${p['event']?.toString().isNotEmpty == true ? p['event'] : '(unassigned event)'}${value != null ? ': $value' : ' fired'} · preview only',
    );
    Widget body;
    switch (n.type) {
      case 'Text':
        body = Text(
          p['text'] ?? 'Text',
          textAlign:
              {
                'left': TextAlign.left,
                'center': TextAlign.center,
                'right': TextAlign.right,
                'justify': TextAlign.justify,
              }[p['textAlign']] ??
              TextAlign.left,
          style: TextStyle(
            fontSize: (p['fontSize'] as num?)?.toDouble() ?? 16,
            color: color(p['color'], '#20212A'),
            fontFamily: p['fontFamily'],
            fontWeight: FontWeight
                .values[((p['fontWeight'] as num?)?.toInt() ?? 400) ~/ 100 - 1],
            height: (p['textHeight'] as num?)?.toDouble(),
            letterSpacing: (p['letterSpacing'] as num?)?.toDouble(),
          ),
        );
      case 'Button':
        body = ElevatedButton(
          onPressed: () => event(),
          style: ElevatedButton.styleFrom(
            backgroundColor: color(p['background'], '#6750A4'),
            foregroundColor: color(p['color'], '#FFFFFF'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                (p['radius'] as num?)?.toDouble() ?? 12,
              ),
            ),
          ),
          child: Text(p['text'] ?? 'Button'),
        );
      case 'Input':
        body = TextField(
          key: ValueKey('input:${original.id}'),
          onChanged: event,
          decoration: InputDecoration(
            hintText: p['text'] ?? 'Enter text',
            border: const OutlineInputBorder(),
          ),
        );
      case 'Spacer':
        body = SizedBox(
          height: (p['height'] as num?)?.toDouble() ?? 24,
          width: (p['width'] as num?)?.toDouble() ?? 24,
        );
      case 'Row':
        body = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: (p['gap'] as num?)?.toDouble() ?? 12,
          children: children,
        );
      case 'Artwork':
        body = const SizedBox();
      case 'Stack':
        body = SizedBox(
          width: (p['width'] as num?)?.toDouble() ?? 320,
          height: (p['height'] as num?)?.toDouble() ?? 240,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n.children.length; i++)
                Positioned(
                  left: (n.children[i].props['left'] as num?)?.toDouble() ?? 0,
                  top: (n.children[i].props['top'] as num?)?.toDouble() ?? 0,
                  child: children[i],
                ),
            ],
          ),
        );
      default:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: (p['gap'] as num?)?.toDouble() ?? 12,
          children: children,
        );
    }
    if (p['png'] != null) {
      final bytes = images.putIfAbsent(p['png'], () => pngBytes(p['png']));
      body = Image.memory(
        bytes,
        width: (p['width'] as num?)?.toDouble() ?? 24,
        height: (p['height'] as num?)?.toDouble() ?? 24,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      );
      if (n.type == 'Text') body = Semantics(label: p['text'], child: body);
    }
    if (!['Button', 'Spacer'].contains(n.type))
      body = Container(
        width: (p['width'] as num?)?.toDouble(),
        height: (p['height'] as num?)?.toDouble(),
        padding: EdgeInsets.all((p['padding'] as num?)?.toDouble() ?? 0),
        decoration: BoxDecoration(
          color: p['background'] == null
              ? Colors.transparent
              : color(p['background'], '#FFFFFF'),
          borderRadius: BorderRadius.circular(
            (p['radius'] as num?)?.toDouble() ?? 0,
          ),
        ),
        child: body,
      );
    if (p['clip'] == true)
      body = ClipRRect(
        borderRadius: BorderRadius.circular(
          (p['radius'] as num?)?.toDouble() ?? 0,
        ),
        child: body,
      );
    if (interact &&
        !['Button', 'Input'].contains(n.type) &&
        (p['event'] as String?)?.isNotEmpty == true)
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => event(),
        child: body,
      );
    if (interact || !selectable) return body;
    body = GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => selected = original.id),
      onPanStart: doc.parent(original.id)?.type != 'Stack'
          ? null
          : (d) {
              dragGlobal = d.globalPosition;
              mutate(() => selected = original.id);
            },
      onPanUpdate: doc.parent(original.id)?.type != 'Stack'
          ? null
          : (d) {
              final delta =
                  (d.globalPosition - (dragGlobal ?? d.globalPosition)) / zoom;
              dragGlobal = d.globalPosition;
              setState(() {
                original.props['left'] =
                    ((original.props['left'] as num? ?? 0) + delta.dx).clamp(
                      -10000,
                      10000,
                    );
                original.props['top'] =
                    ((original.props['top'] as num? ?? 0) + delta.dy).clamp(
                      -10000,
                      10000,
                    );
              });
            },
      onPanEnd: doc.parent(original.id)?.type != 'Stack'
          ? null
          : (_) => dragGlobal = null,
      child: AbsorbPointer(
        absorbing: !isLayout(n.type) || original.type == 'Instance',
        child: body,
      ),
    );
    body = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: selected == original.id
              ? const Color(0xFF8061CC)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: body,
    );
    if (isLayout(original.type)) {
      final content = body;
      body = DragTarget<String>(
        onAcceptWithDetails: (d) => insert(d.data, original),
        builder: (ctx, candidates, _) => Container(
          decoration: candidates.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(color: const Color(0xFF8061CC), width: 2),
                  color: const Color(0x226750A4),
                )
              : null,
          constraints: BoxConstraints(
            minHeight: p['height'] == null ? 24 : 0,
            minWidth: p['width'] == null ? 24 : 0,
          ),
          child: content,
        ),
      );
    }
    return body;
  }

  Widget canvas() => Expanded(
    child: Column(
      children: [
        Container(
          height: 54,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  editingComponent != null
                      ? 'Editing component: $editingComponent'
                      : root.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (editingComponent != null)
                button(
                  'Back to screen',
                  Icons.arrow_back,
                  () => setState(() {
                    editingComponent = null;
                    selected = null;
                  }),
                ),
              DropdownButton<double>(
                value: previewWidth,
                items:
                    {
                          ...[320.0, 390.0, 600.0, 900.0],
                          previewWidth,
                        }
                        .map(
                          (w) => DropdownMenuItem(
                            value: w,
                            child: Text('${w.toInt()} px'),
                          ),
                        )
                        .toList(),
                onChanged: (w) => setState(() => previewWidth = w!),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () =>
                    setState(() => zoom = (zoom - .1).clamp(.3, 1.5)),
                icon: const Icon(Icons.remove, size: 18),
              ),
              Text('${(zoom * 100).round()}%'),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () =>
                    setState(() => zoom = (zoom + .1).clamp(.3, 1.5)),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        interact ? 'INTERACT PREVIEW' : 'DESIGN CANVAS',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Transform.scale(
                        scale: zoom,
                        alignment: Alignment.topLeft,
                        child: Container(
                          width: previewWidth,
                          constraints: BoxConstraints(
                            minHeight: root.props['height'] == null ? 700 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: root.props.containsKey('sourceId') ? Colors.transparent : Colors.white,
                            borderRadius: BorderRadius.circular((root.props['radius'] as num?)?.toDouble() ?? 16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x15000000),
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: render(root),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> manual() async {
    final text = await DefaultAssetBundle.of(
      context,
    ).loadString('USER_MANUAL.md');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frame · User manual'),
        content: SizedBox(
          width: 760,
          height: 600,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          save(),
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): open,
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE3E3EB))),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.view_quilt_rounded,
                    color: Color(0xFF6750A4),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Frame',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  if (dirty)
                    const Text(
                      '  •',
                      style: TextStyle(color: Color(0xFF6750A4)),
                    ),
                  const SizedBox(width: 18),
                  button('Open', Icons.folder_open, open),
                  button('Save', Icons.save_outlined, () => save()),
                  button(
                    'Save as',
                    Icons.save_as_outlined,
                    () => save(as: true),
                  ),
                  button('Figma import', Icons.download_outlined, importFigma),
                  button('Export Dart', Icons.code, export),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo design change',
                    onPressed: undo.isEmpty ? null : () => history(true),
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Redo design change',
                    onPressed: redo.isEmpty ? null : () => history(false),
                    icon: const Icon(Icons.redo),
                  ),
                  const Text('Interact'),
                  Switch(
                    value: interact,
                    onChanged: (v) => setState(() {
                      interact = v;
                      selected = null;
                    }),
                  ),
                  IconButton(
                    tooltip: 'User manual',
                    onPressed: manual,
                    icon: const Icon(Icons.help_outline),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) => constraints.maxWidth < 1050
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 1200,
                          height: constraints.maxHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [leftPanel(), canvas(), inspector()],
                          ),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [leftPanel(), canvas(), inspector()],
                      ),
              ),
            ),
            Container(
              height: 30,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: const Color(0xFFEDEBF2),
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
