import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canvas_flutter/document.dart';
import 'package:canvas_flutter/figma_import.dart';
import 'package:canvas_flutter/main.dart';
import 'generated_fixture.dart';

class LocalPicker extends FileSelectorPlatform {
  final String directory;
  LocalPicker(this.directory);
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile('$directory/workspace.canvas.json');
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => FileSaveLocation('$directory/${options.suggestedName}');
}

void main() {
  test(
    'project round-trip, shared component overrides, validation, and Figma conversion',
    () {
      final doc = DesignDocument.sample();
      final original = doc.screens.first.children.last;
      doc.components['Button'] = doc.clone(original);
      final instance = DesignNode(
        'Instance',
        props: {'component': 'Button', 'text': 'Override'},
      );
      doc.screens.first.children.add(instance);
      doc.components['Button']!.props['background'] = '#112233';
      final restored = DesignDocument.decode(doc.encode());
      expect(
        restored.resolve(restored.screens.first.children.last).props['text'],
        'Override',
      );
      expect(
        restored
            .resolve(restored.screens.first.children.last)
            .props['background'],
        '#112233',
      );
      expect(restored.exportDart(), contains('DesignButton1('));
      final bad = jsonDecode(doc.encode());
      bad['screens'][0]['props']['padding'] = -1;
      expect(
        () => DesignDocument.decode(jsonEncode(bad)),
        throwsFormatException,
      );
      bad['screens'][0]['props']['padding'] = 12;
      bad['components']['Button']['children'] = [
        {
          'id': 'cycle',
          'type': 'Instance',
          'name': 'Cycle',
          'props': {'component': 'Button'},
          'children': [],
        },
      ];
      bad['components']['Button']['type'] = 'Column';
      expect(
        () => DesignDocument.decode(jsonEncode(bad)),
        throwsFormatException,
      );
      expect(() => importFigmaPackage('{}'), throwsFormatException);
      final imported = importFigmaPackage(
        File('examples/figma.canvas-package.json').readAsStringSync(),
      );
      expect(
        imported.screens.single.children.first.props['text'],
        'Workspace preferences',
      );
      expect(imported.warnings, isNotEmpty);
    },
  );

  testWidgets(
    'editor selects, edits, creates a component, previews events, and undoes',
    (tester) async {
      await tester.runAsync(() async {
        if (File('C:/Windows/Fonts/segoeui.ttf').existsSync()) {
          final font = FontLoader('Roboto')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
                ),
              ),
            );
          await font.load();
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: captureKey, child: const FrameApp()),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('PREVIEW.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(find.text('Your workspace'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.text('Save preferences')));
      await tester.pumpAndSettle();
      final label = find.widgetWithText(TextFormField, 'Label / text');
      await tester.enterText(label, 'Apply preferences');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Apply preferences'), findsWidgets);
      final create = find.text('Create component');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Reusable Button'), findsWidgets);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply preferences').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('savePreferences fired'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo design change'));
      await tester.pumpAndSettle();
      expect(find.text('Reusable Button'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final paletteText = find.widgetWithText(ListTile, 'Text').first;
      final before = find.text('New text').evaluate().length;
      await tester.dragFrom(
        tester.getCenter(paletteText),
        tester.getCenter(find.text('Your workspace')) -
            tester.getCenter(paletteText),
      );
      await tester.pumpAndSettle();
      expect(find.text('New text').evaluate().length, greaterThan(before));
      await tester.tap(find.byTooltip('User manual'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Frame is a local'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      final pickerBefore = FileSelectorPlatform.instance;
      final folder = Directory.systemTemp.createTempSync('canvas-check-');
      FileSelectorPlatform.instance = LocalPicker(folder.path);
      Future<void> ioTap(String label) async {
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
      }

      try {
        await ioTap('Save');
        final project = File('${folder.path}/workspace.canvas.json');
        expect(
          DesignDocument.decode(
            project.readAsStringSync(),
          ).screens.first.walk.any((n) => n.props['text'] == 'New text'),
          isTrue,
        );
        await ioTap('Save');
        expect(File('${project.path}.pending').existsSync(), isFalse);
        await ioTap('Open');
        expect(find.text('New text'), findsOneWidget);
        await ioTap('Export Dart');
        expect(
          File('${folder.path}/generated_ui.dart').readAsStringSync(),
          contains('class DesignSettings0'),
        );
        project.writeAsStringSync('{}');
        await ioTap('Open');
        expect(find.text('New text'), findsOneWidget);
        expect(
          find.textContaining('Current project was preserved'),
          findsOneWidget,
        );
      } finally {
        FileSelectorPlatform.instance = pickerBefore;
        folder.deleteSync(recursive: true);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exported Dart compiles and dispatches typed button and input callbacks',
    (tester) async {
      var presses = 0;
      String changed = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DesignSettings0(
                actions: {'savePreferences': () => presses++},
                changes: {'displayNameChanged': (v) => changed = v},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.enterText(find.byType(TextField), 'Ava');
      expect(presses, 1);
      expect(changed, 'Ava');
      expect(tester.takeException(), isNull);
    },
  );
}
