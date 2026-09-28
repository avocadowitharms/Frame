import 'dart:convert';
import 'dart:typed_data';

const maxDocumentBytes = 32000000;
String argbHex(String hex) =>
    hex.length == 7 ? 'FF${hex.substring(1)}' : hex.substring(1);
bool validColor(String hex) =>
    RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex);
Uint8List pngBytes(String value) {
  if (value.length > 12000000)
    throw const FormatException('An image exceeds 12 MB encoded.');
  final bytes = base64Decode(value);
  if (bytes.length < 33 ||
      !const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ].asMap().entries.every((e) => bytes[e.key] == e.value) ||
      ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR')
    throw const FormatException('Expected a PNG image.');
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(16), height = header.getUint32(20);
  if (width == 0 ||
      height == 0 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 16000000)
    throw const FormatException('PNG exceeds the 16 megapixel image limit.');
  return bytes;
}

const kinds = [
  'Column',
  'Row',
  'Container',
  'Text',
  'Button',
  'Input',
  'Spacer',
  'Stack',
  'Artwork',
];
bool isLayout(String type) =>
    ['Column', 'Row', 'Container', 'Stack'].contains(type);
int _lastId = 0;
String uid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _lastId = now > _lastId ? now : _lastId + 1;
  return _lastId.toString();
}

String literal(String value) =>
    "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
String className(String name) =>
    'Design${name.replaceAll(RegExp('[^a-zA-Z0-9]'), '')}';

class DesignNode {
  String id, type, name;
  Map<String, dynamic> props;
  List<DesignNode> children;
  DesignNode(
    this.type, {
    String? id,
    String? name,
    Map<String, dynamic>? props,
    List<DesignNode>? children,
  }) : id = id ?? uid(),
       name = name ?? type,
       props = props ?? {},
       children = children ?? [];
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'props': props,
    'children': children.map((n) => n.toJson()).toList(),
  };
  factory DesignNode.fromJson(Map<String, dynamic> json, [int depth = 0]) {
    if (depth > 40 ||
        json['id'] is! String ||
        json['name'] is! String ||
        json['type'] is! String ||
        json['props'] is! Map ||
        json['children'] is! List)
      throw const FormatException('Invalid node or nesting exceeds 40 levels.');
    final node = DesignNode(
      json['type'],
      id: json['id'],
      name: json['name'],
      props: Map<String, dynamic>.from(json['props']),
      children: (json['children'] as List)
          .map(
            (n) => DesignNode.fromJson(Map<String, dynamic>.from(n), depth + 1),
          )
          .toList(),
    );
    if (!kinds.contains(node.type) && node.type != 'Instance')
      throw FormatException('Unsupported widget: ${node.type}');
    if (!isLayout(node.type) && node.children.isNotEmpty)
      throw const FormatException('Leaf widgets cannot contain children.');
    for (final key in [
      'padding',
      'gap',
      'radius',
      'fontSize',
      'height',
      'width',
      'textHeight',
    ]) {
      final v = node.props[key];
      if (v != null && (v is! num || !v.isFinite || v < 0 || v > 10000))
        throw FormatException('Invalid $key');
    }
    for (final key in ['left', 'top', 'letterSpacing']) {
      final v = node.props[key];
      if (v != null && (v is! num || !v.isFinite || v.abs() > 10000))
        throw FormatException('Invalid $key');
    }
    if (node.props['clip'] != null && node.props['clip'] is! bool)
      throw const FormatException('Invalid clipping.');
    if (node.props['textAlign'] != null &&
        ![
          'left',
          'center',
          'right',
          'justify',
        ].contains(node.props['textAlign']))
      throw const FormatException('Invalid text alignment.');
    if (node.props['fontWeight'] != null &&
        ![
          100,
          200,
          300,
          400,
          500,
          600,
          700,
          800,
          900,
        ].contains(node.props['fontWeight']))
      throw const FormatException('Invalid font weight.');
    if (node.props['png'] != null) {
      if (node.props['png'] is! String)
        throw const FormatException('Invalid image.');
      pngBytes(node.props['png']);
    }
    return node;
  }
  Iterable<DesignNode> get walk sync* {
    yield this;
    for (final child in children) {
      yield* child.walk;
    }
  }
}

class DesignDocument {
  List<DesignNode> screens;
  Map<String, DesignNode> components;
  Map<String, String> tokens;
  DesignDocument(
    this.screens, {
    Map<String, DesignNode>? components,
    Map<String, String>? tokens,
  }) : components = components ?? {},
       tokens =
           tokens ??
           {'accent': '#6750A4', 'ink': '#20212A', 'surface': '#F2F0F7'};
  factory DesignDocument.sample() => DesignDocument([
    DesignNode(
      'Column',
      name: 'Settings',
      props: {'padding': 24, 'gap': 18},
      children: [
        DesignNode(
          'Text',
          props: {'text': 'Your workspace', 'fontSize': 28, 'color': '@ink'},
        ),
        DesignNode(
          'Text',
          props: {
            'text': 'Make it feel like you.',
            'fontSize': 16,
            'color': '@ink',
          },
        ),
        DesignNode(
          'Container',
          props: {
            'padding': 16,
            'radius': 16,
            'background': '@surface',
            'gap': 12,
          },
          children: [
            DesignNode('Text', props: {'text': 'Display name'}),
            DesignNode(
              'Input',
              props: {'text': 'Enter a name', 'event': 'displayNameChanged'},
            ),
          ],
        ),
        DesignNode(
          'Button',
          props: {
            'text': 'Save preferences',
            'background': '@accent',
            'color': '#FFFFFF',
            'event': 'savePreferences',
          },
        ),
      ],
    ),
  ]);
  Map<String, dynamic> toJson() => {
    'format': 'canvas-flutter',
    'version': 1,
    'screens': screens.map((n) => n.toJson()).toList(),
    'components': components.map((k, v) => MapEntry(k, v.toJson())),
    'tokens': tokens,
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory DesignDocument.decode(String source) {
    if (source.length > maxDocumentBytes)
      throw const FormatException('Project is larger than 32 MB.');
    final j = jsonDecode(source);
    if (j is! Map || j['format'] != 'canvas-flutter' || j['version'] != 1)
      throw const FormatException('Expected a Frame version 1 project.');
    final d = DesignDocument(
      (j['screens'] as List)
          .map((n) => DesignNode.fromJson(Map<String, dynamic>.from(n)))
          .toList(),
      components: (j['components'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          DesignNode.fromJson(Map<String, dynamic>.from(v)),
        ),
      ),
      tokens: Map<String, String>.from(j['tokens']),
    );
    if (d.screens.isEmpty)
      throw const FormatException('A project needs a screen.');
    final ids = <String>{};
    for (final root in [...d.screens, ...d.components.values]) {
      for (final n in root.walk) {
        if (!ids.add(n.id)) throw const FormatException('Duplicate node IDs.');
        if (n.type == 'Instance' &&
            !d.components.containsKey(n.props['component']))
          throw const FormatException('Missing component.');
        for (final key in ['color', 'background']) {
          final v = n.props[key];
          if (v != null &&
              (v is! String ||
                  !(validColor(v) ||
                      v.startsWith('@') &&
                          d.tokens.containsKey(v.substring(1)))))
            throw FormatException('Invalid $key');
        }
        for (final key in ['text', 'event', 'component', 'fontFamily']) {
          if (n.props[key] != null && n.props[key] is! String)
            throw FormatException('Invalid $key');
        }
      }
    }
    for (final value in d.tokens.values) {
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value))
        throw const FormatException('Invalid token color.');
    }
    void visit(String key, Set<String> trail) {
      if (trail.contains(key))
        throw const FormatException('Circular component reference.');
      for (final n in d.components[key]!.walk.where(
        (n) => n.type == 'Instance',
      )) {
        visit(n.props['component'], {...trail, key});
      }
    }

    for (final key in d.components.keys) {
      visit(key, {});
    }
    return d;
  }
  DesignNode? find(String id) {
    for (final root in [...screens, ...components.values]) {
      for (final n in root.walk) {
        if (n.id == id) return n;
      }
    }
    return null;
  }

  DesignNode? parent(String id) {
    for (final root in [...screens, ...components.values]) {
      for (final n in root.walk) {
        if (n.children.any((c) => c.id == id)) return n;
      }
    }
    return null;
  }

  DesignNode clone(DesignNode n) => DesignNode(
    n.type,
    name: n.name,
    props: Map.of(n.props),
    children: n.children.map(clone).toList(),
  );
  DesignNode resolve(DesignNode n) {
    if (n.type != 'Instance') return n;
    final base = components[n.props['component']]!;
    final props = {...base.props, ...n.props};
    if (base.type == 'Text' &&
        [
          'text',
          'fontSize',
          'color',
          'fontFamily',
        ].any((key) => n.props.containsKey(key)))
      props.remove('png');
    return DesignNode(
      base.type,
      id: n.id,
      name: n.name,
      props: props,
      children: base.children,
    );
  }

  String hex(dynamic value, String fallback) {
    final s = value?.toString() ?? fallback;
    return s.startsWith('@') ? tokens[s.substring(1)] ?? fallback : s;
  }

  String exportedName(DesignNode root) =>
      '${className(root.name)}${[...screens, ...components.values].indexOf(root)}';
  String exportDart() {
    final out = StringBuffer(
      "// Generated by Frame. Keep behavior in separate files.\nimport 'dart:convert';\nimport 'package:flutter/material.dart';\n\n",
    );
    for (final root in [...screens, ...components.values]) {
      // ponytail: stable numbered classes avoid name collisions; named public APIs can replace this when component parameter schemas expand.
      final name = exportedName(root);
      out.writeln(
        'class $name extends StatelessWidget {\n  final Map<String, VoidCallback> actions;\n  final Map<String, ValueChanged<String>> changes;\n  final String? label, eventKey;\n  final Color? background, foreground;\n  final double? radius, fontSize, padding, gap, width, height;\n  const $name({super.key, this.actions = const {}, this.changes = const {}, this.label, this.eventKey, this.background, this.foreground, this.radius, this.fontSize, this.padding, this.gap, this.width, this.height});\n  @override\n  Widget build(BuildContext context) => ${dartNode(root, root: true)};\n}\n',
      );
    }
    return out.toString();
  }

  String dartNode(DesignNode original, {bool root = false}) {
    if (original.type == 'Instance') {
      final p = original.props;
      final args = <String>['actions: actions', 'changes: changes'];
      for (final entry in {'text': 'label', 'event': 'eventKey'}.entries) {
        if (p[entry.key] != null)
          args.add('${entry.value}: ${literal(p[entry.key])}');
      }
      for (final entry in {
        'background': 'background',
        'color': 'foreground',
      }.entries) {
        if (p[entry.key] != null)
          args.add(
            '${entry.value}: Color(0x${argbHex(hex(p[entry.key], '#FFFFFF'))})',
          );
      }
      for (final key in [
        'radius',
        'fontSize',
        'padding',
        'gap',
        'width',
        'height',
      ]) {
        if (p[key] != null) args.add('$key: ${p[key]}');
      }
      return '${exportedName(components[p['component']]!)}(${args.join(', ')})';
    }
    final n = resolve(original);
    final p = n.props;
    String color(dynamic v, String fallback, String parameter) => root
        ? v == null && parameter == 'background'
              ? '(background ?? Colors.transparent)'
              : '($parameter ?? Color(0x${argbHex(hex(v, fallback))}))'
        : v == null && parameter == 'background'
        ? 'Colors.transparent'
        : 'Color(0x${argbHex(hex(v, fallback))})';
    String number(String key, num fallback) =>
        root ? '($key ?? ${p[key] ?? fallback})' : '${p[key] ?? fallback}';
    final text = root
        ? '(label ?? ${literal(p['text'] ?? n.type)})'
        : literal(p['text'] ?? n.type);
    final event = root
        ? '(eventKey ?? ${literal(p['event'] ?? '')})'
        : literal(p['event'] ?? '');
    final children = n.children
        .map(
          (c) => n.type == 'Stack'
              ? 'Positioned(left: ${c.props['left'] ?? 0}, top: ${c.props['top'] ?? 0}, child: ${dartNode(c)})'
              : dartNode(c),
        )
        .join(',');
    String body;
    switch (n.type) {
      case 'Text':
        body =
            'Text($text, textAlign: TextAlign.${p['textAlign'] ?? 'left'}, style: TextStyle(fontSize: ${number('fontSize', 16)}, fontFamily: ${p['fontFamily'] == null ? 'null' : literal(p['fontFamily'])}, fontWeight: FontWeight.w${p['fontWeight'] ?? 400}, height: ${p['textHeight'] ?? 'null'}, letterSpacing: ${p['letterSpacing'] ?? 0}, color: ${color(p['color'], '#20212A', 'foreground')}))';
      case 'Artwork':
        body = 'const SizedBox()';
      case 'Stack':
        body =
            'SizedBox(width: ${number('width', 320)}, height: ${number('height', 240)}, child: Stack(clipBehavior: Clip.none, children: [$children]))';
      case 'Button':
        body =
            'ElevatedButton(onPressed: actions[$event] ?? () {}, style: ElevatedButton.styleFrom(backgroundColor: ${color(p['background'], '#6750A4', 'background')}, foregroundColor: ${color(p['color'], '#FFFFFF', 'foreground')}, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(${number('radius', 12)}))), child: Text($text))';
      case 'Input':
        body =
            'TextField(onChanged: changes[$event], decoration: InputDecoration(hintText: $text, border: const OutlineInputBorder()))';
      case 'Spacer':
        body =
            'SizedBox(height: ${number('height', 24)}, width: ${number('width', 24)})';
      case 'Row':
        body =
            'Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: ${number('gap', 12)}, children: [$children])';
      default:
        body =
            'Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: ${number('gap', 12)}, children: [$children])';
    }
    if (p['png'] != null) {
      final image =
          'Image.memory(base64Decode(${literal(p['png'])}), width: ${p['width'] ?? 24}, height: ${p['height'] ?? 24}, fit: BoxFit.fill, filterQuality: FilterQuality.high)';
      if (n.type == 'Text') {
        final native = body;
        body = 'Semantics(label: $text, child: $image)';
        if (root)
          body =
              '(label == null && foreground == null && fontSize == null ? $body : $native)';
      } else
        body = image;
    }
    if (n.type != 'Button' && n.type != 'Spacer')
      body =
          'Container(${root ? "width: width ?? ${p['width'] ?? 'null'}, height: height ?? ${p['height'] ?? 'null'}," : "${p['width'] != null ? "width: ${p['width']}," : ""}${p['height'] != null ? "height: ${p['height']}," : ""}"}padding: EdgeInsets.all(${number('padding', 0)}), decoration: BoxDecoration(color: ${color(p['background'], '#FFFFFF', 'background')}, borderRadius: BorderRadius.circular(${number('radius', 0)})), child: $body)';
    if (p['clip'] == true)
      body =
          'ClipRRect(borderRadius: BorderRadius.circular(${number('radius', 0)}), child: $body)';
    if (!['Button', 'Input'].contains(n.type) &&
        (root || (p['event'] as String?)?.isNotEmpty == true))
      body =
          'GestureDetector(behavior: HitTestBehavior.opaque, onTap: actions[$event], child: $body)';
    return body;
  }
}
