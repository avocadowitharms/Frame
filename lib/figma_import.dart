import 'dart:convert';
import 'document.dart';

class FigmaImport {
  final List<DesignNode> screens;
  final List<String> warnings;
  FigmaImport(this.screens, this.warnings);
}

FigmaImport importFigmaPackage(String source) {
  if (source.length > maxDocumentBytes)
    throw const FormatException('Import exceeds 32 MB.');
  final json = jsonDecode(source);
  if (json is! Map ||
      json['format'] != 'canvas-figma' ||
      ![1, 2].contains(json['version']) ||
      json['nodes'] is! List ||
      (json['nodes'] as List).isEmpty)
    throw const FormatException(
      'Use the included Figma bridge plugin to export a package.',
    );
  if (json['version'] == 2) return importPositionedFigma(json);
  if ((json['nodes'] as List).any(
    (n) =>
        n is Map &&
        n['children'] is List &&
        (n['children'] as List).isNotEmpty &&
        !['HORIZONTAL', 'VERTICAL'].contains(n['layoutMode']),
  ))
    throw const FormatException(
      'This old bridge package has no layer positions or artwork. Re-export your screen with the updated Frame Bridge (version 2).',
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

FigmaImport importPositionedFigma(Map json) {
  final warnings = <String>[];
  int count = 0, artwork = 0, textImages = 0;
  String? fill(dynamic fills) {
    if (fills is! List || fills.isEmpty) return null;
    final visible = fills
        .where((f) => f is Map && f['visible'] != false)
        .toList();
    if (visible.isEmpty) return null;
    final f = visible.last as Map;
    if (visible.length != 1 || f['type'] != 'SOLID' || f['color'] is! Map)
      throw const FormatException(
        'Complex fills must be exported as artwork by Frame Bridge.',
      );
    final c = f['color'] as Map;
    final opacity = f['opacity'] ?? 1;
    if (opacity is! num || !opacity.isFinite || opacity < 0 || opacity > 1)
      throw const FormatException('Invalid fill opacity.');
    final channels = <num>[opacity];
    for (final key in ['r', 'g', 'b']) {
      final value = c[key];
      if (value is! num || !value.isFinite || value < 0 || value > 1)
        throw const FormatException('Invalid Figma color.');
      channels.add(value);
    }
    return '#${channels.map((v) => (v * 255).round().toRadixString(16).padLeft(2, '0')).join()}';
  }

  DesignNode convert(dynamic value, int depth) {
    if (value is! Map || depth > 30 || ++count > 3000)
      throw const FormatException(
        'Invalid node, or import exceeds 3000 nodes / 30 levels.',
      );
    final j = value;
    final name = j['name'] is String ? j['name'] as String : 'Imported';
    final props = <String, dynamic>{'sourceId': j['id']?.toString() ?? ''};
    for (final entry in {
      'x': 'left',
      'y': 'top',
      'width': 'width',
      'height': 'height',
    }.entries) {
      final v = j[entry.key];
      if (v is! num ||
          !v.isFinite ||
          v.abs() > 10000 ||
          ['width', 'height'].contains(entry.key) && v <= 0)
        throw FormatException(
          '$name: invalid ${entry.key}. Re-export this frame.',
        );
      props[entry.value] = v;
    }
    if (j['type'] == 'TEXT') {
      if (j['characters'] is! String)
        throw const FormatException('Invalid text.');
      props['text'] = j['characters'];
      props['fontSize'] = j['fontSize'] is num ? j['fontSize'] : 16;
      if (j['fontName'] is Map && j['fontName']['family'] is String)
        props['fontFamily'] = j['fontName']['family'];
      if ([
        100,
        200,
        300,
        400,
        500,
        600,
        700,
        800,
        900,
      ].contains(j['fontWeight']))
        props['fontWeight'] = j['fontWeight'];
      props['textAlign'] =
          {
            'LEFT': 'left',
            'CENTER': 'center',
            'RIGHT': 'right',
            'JUSTIFIED': 'justify',
          }[j['textAlignHorizontal']] ??
          'left';
      if (j['lineHeight'] is Map && j['lineHeight']['value'] is num) {
        final line = j['lineHeight'];
        if (line['unit'] == 'PERCENT')
          props['textHeight'] = line['value'] / 100;
        else if (line['unit'] == 'PIXELS' && props['fontSize'] > 0)
          props['textHeight'] = line['value'] / props['fontSize'];
      }
      if (j['letterSpacing'] is Map && j['letterSpacing']['value'] is num) {
        final spacing = j['letterSpacing'];
        props['letterSpacing'] = spacing['unit'] == 'PERCENT'
            ? spacing['value'] * props['fontSize'] / 100
            : spacing['value'];
      }
      // Mixed / complex text paints are retained in the snapshot; native text uses the default ink when they cannot be represented.
      try {
        props['color'] = fill(j['fills']) ?? '#20212A';
      } on FormatException {
        if (j['png'] == null) rethrow;
      }
      if (j['png'] != null) {
        props['png'] = j['png'];
        textImages++;
      } else
        warnings.add(
          '$name: native text requires the original font installed in Frame and bundled in your exported app; rendering may differ.',
        );
      return DesignNode('Text', name: name, props: props);
    }
    if (j['png'] != null) {
      props['png'] = j['png'];
      artwork++;
      return DesignNode('Artwork', name: name, props: props);
    }
    if (![
      'FRAME',
      'GROUP',
      'COMPONENT',
      'INSTANCE',
      'COMPONENT_SET',
    ].contains(j['type']))
      throw FormatException(
        '$name: artwork image is missing. Re-export using the updated bridge.',
      );
    final background = fill(j['fills']);
    if (background != null) props['background'] = background;
    if (j['cornerRadius'] is num) props['radius'] = j['cornerRadius'];
    props['clip'] = j['clipsContent'] == true;
    if (j['type'] == 'COMPONENT' ||
        j['type'] == 'INSTANCE' ||
        j['type'] == 'COMPONENT_SET')
      warnings.add(
        '$name: component links are not retained. Create a Frame component after import.',
      );
    if (j['children'] != null && j['children'] is! List)
      throw const FormatException('Invalid children.');
    return DesignNode(
      'Stack',
      name: name,
      props: props,
      children: (j['children'] as List? ?? [])
          .map((c) => convert(c, depth + 1))
          .toList(),
    );
  }

  final screens = (json['nodes'] as List).map((j) => convert(j, 0)).toList();
  DesignDocument.decode(DesignDocument(screens).encode());
  if (artwork > 0)
    warnings.add(
      '$artwork layer(s) preserve artwork as embedded PNG images. Complex groups are a single selectable image, not editable vector paths.',
    );
  if (textImages > 0)
    warnings.add(
      '$textImages text layer(s) preserve font appearance as images. Text content is retained for accessibility. Editing text or typography switches that layer to native Flutter text.',
    );
  warnings.add(
    'Imported layout uses fixed positions and original dimensions. It is not automatically responsive; resizing the canvas does not reflow it.',
  );
  return FigmaImport(screens, warnings);
}
