import 'dart:io';
import '../lib/document.dart';

void main() {
  final doc = DesignDocument.sample();
  final button = doc.screens.first.children.removeLast();
  doc.components['Primary button'] = doc.clone(button)..name = 'Primary button';
  doc.screens.first.children.add(
    DesignNode(
      'Instance',
      props: {
        'component': 'Primary button',
        'text': "Save \$ 'quoted' \\ name",
        'event': 'savePreferences',
        'background': '#112233',
        'radius': 8,
      },
    ),
  );
  doc.screens.first.children.add(
    DesignNode(
      'Row',
      children: [
        DesignNode('Text', props: {'text': 'Ready'}),
        DesignNode('Spacer'),
      ],
    ),
  );
  File('test/generated_fixture.dart').writeAsStringSync(doc.exportDart());
  File('examples/settings.canvas.json').writeAsStringSync(doc.encode());
}
