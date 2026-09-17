import 'dart:convert';
import 'document.dart';

class FigmaImport {
  final List<DesignNode> screens;
  final List<String> warnings;
  FigmaImport(this.screens, this.warnings);
}

FigmaImport importFigmaPackage(String source) {
  if (source.length > 5000000)
    throw const FormatException('Import exceeds 5 MB.');
  final json = jsonDecode(source);
  if (json is! Map ||
      json['format'] != 'canvas-figma' ||
      json['version'] != 1 ||
      json['nodes'] is! List ||
      (json['nodes'] as List).isEmpty)
    throw const FormatException(
      'Use the included Figma bridge plugin to export a package.',
    );
  final warnings = <String>[];
  String? fill(dynamic fills) {
    if (fills is! List) return null;
    for (final f in fills) {
      if (f is Map &&
          f['type'] == 'SOLID' &&
          f['visible'] != false &&
          f['color'] is Map) {
        final c = f['color'] as Map;
        if (f['opacity'] != null && f['opacity'] != 1)
          warnings.add('A translucent fill was imported as opaque.');
        return '#${['r', 'g', 'b'].map((k) {
          final value = c[k];
          if (value is! num || !value.isFinite || value < 0 || value > 1) throw const FormatException('Invalid Figma color.');
          return (value * 255).round().toRadixString(16).padLeft(2, '0');
        }).join()}';
      }
    }
    if (fills.isNotEmpty)
      warnings.add(
        'A non-solid fill was omitted; choose a solid fill in the inspector.',
      );
    return null;
  }

  int count = 0;
  DesignNode convert(Map j, int depth) {
    if (depth > 30 || ++count > 3000)
      throw const FormatException('Import exceeds 3000 nodes or 30 levels.');
    final name = j['name'] is String ? j['name'] as String : 'Imported';
    final type = j['type'];
    if (j['effects'] is List && (j['effects'] as List).isNotEmpty)
      warnings.add('$name: effects were omitted.');
    if (j['strokes'] is List && (j['strokes'] as List).isNotEmpty)
      warnings.add('$name: strokes were omitted.');
    final p = <String, dynamic>{'sourceId': j['id']?.toString() ?? ''};
    void number(String target, dynamic value) {
      if (value is num && value.isFinite && value >= 0 && value <= 10000)
        p[target] = value;
    }

    if (type == 'TEXT') {
      if (j['characters'] is! String)
        throw const FormatException('Invalid text.');
      p['text'] = j['characters'];
      number('fontSize', j['fontSize']);
      p['color'] = fill(j['fills']) ?? '#20212A';
      warnings.add(
        '$name: font family, weight, and line-height use editor defaults.',
      );
      return DesignNode('Text', name: name, props: p);
    }
    p['background'] = fill(j['fills']) ?? '#FFFFFF';
    number('radius', j['cornerRadius']);
    final padding = [
      j['paddingTop'],
      j['paddingRight'],
      j['paddingBottom'],
      j['paddingLeft'],
    ].whereType<num>().toList();
    if (padding.isNotEmpty) {
      number('padding', padding.reduce((a, b) => a > b ? a : b));
      if (padding.toSet().length > 1)
        warnings.add('$name: unequal padding simplified to the largest edge.');
    }
    number('gap', j['itemSpacing']);
    final children = j['children'];
    if (children != null && children is! List)
      throw const FormatException('Invalid Figma children.');
    final hasChildren = children is List && children.isNotEmpty;
    if (hasChildren &&
        j['layoutMode'] != 'HORIZONTAL' &&
        j['layoutMode'] != 'VERTICAL')
      warnings.add(
        '$name: free positioning converted to a vertical layout. Use Auto Layout in Figma for predictable results.',
      );
    if (type == 'COMPONENT' || type == 'INSTANCE' || type == 'COMPONENT_SET')
      warnings.add(
        '$name: imported as editable layout; Figma component links and variants are not retained in this MVP.',
      );
    if (![
      'FRAME',
      'GROUP',
      'COMPONENT',
      'INSTANCE',
      'COMPONENT_SET',
      'RECTANGLE',
    ].contains(type))
      warnings.add('$name: $type simplified to a container.');
    if (!hasChildren) {
      number('width', j['width']);
      number('height', j['height']);
    }
    return DesignNode(
      j['layoutMode'] == 'HORIZONTAL' ? 'Row' : 'Container',
      name: name,
      props: p,
      children: children is List
          ? children
                .where((c) => c is Map && c['visible'] != false)
                .map((c) => convert(c as Map, depth + 1))
                .toList()
          : [],
    );
  }

  final screens = (json['nodes'] as List).map((j) {
    if (j is! Map) throw const FormatException('Invalid Figma node.');
    return convert(j, 0);
  }).toList();
  // Validate the converted document before handing anything to the current workspace.
  DesignDocument.decode(DesignDocument(screens).encode());
  return FigmaImport(screens, warnings.toSet().toList());
}
