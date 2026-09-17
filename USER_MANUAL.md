# Frame — MVP user manual

Frame is a local, account-free visual editor for Flutter interfaces.
It renders real Flutter widgets while you edit. You do not need to run the
screen you are designing, use an emulator, or compile each visual change.
The editor itself is a running Flutter desktop application.

## 1. Start the editor

If you received the Windows application bundle, extract the entire bundle
and launch frame.exe. Keep its DLLs and data folder beside it.
No account, server, or network connection is needed to use the editor.

To run from source, install Flutter 3.44 or newer with Dart 3.12 or newer
and the Windows Flutter build prerequisites (Visual Studio with Desktop
development with C++). In this project's directory run:

    flutter pub get
    flutter run -d windows

Dependency installation can need internet; normal editing does not.
The Help (?) button opens this manual inside the application.

## 2. Workspace

Left: screens, widget palette, reusable components, and the layer hierarchy.
Center: real Flutter preview. Right: inspector and shared color tokens.
Bottom: save confirmations, errors, and preview event messages.

Design mode selects widgets instead of activating them. Interact mode lets
you press buttons and type in inputs. Interact reports event keys in the
status bar; it never runs arbitrary developer code inside the editor.

The purple dot beside the editor name means the project has unsaved changes.
Save regularly. Opening another project or closing the window with unsaved
changes asks before discarding. Cancel and Save if you want to retain them.
There is no automatic recovery after a crash in this MVP.

## 3. Build a screen

1. Start with the supplied Settings screen or choose Add screen.
2. Drag a widget from the palette onto a Column, Row, or Container on the
   canvas. You can also drop onto a layout's entry in Layers.
3. Clicking a palette item adds it inside the selected layout, or inside
   the screen root if you selected a leaf widget.
4. Select the new widget on the canvas or in Layers.
5. Edit its inspector values and press Enter to apply each field.
6. Use the width selector to check 320, 390, 600, or 900 pixel layouts.

Column stacks children vertically. Row places children horizontally.
Container provides background, padding, corners, and a vertical child layout.
Text, Button, Input, and Spacer are leaf widgets. Spacer is a fixed-size
empty box, not Flutter's flex-based Spacer widget.

Use Child spacing on layouts. Blank width and height mean automatic sizing;
fixed sizes can overflow. Drag layer entries to another layout to reparent
them. Up and Down reorder siblings. Duplicate copies a subtree. Delete
removes a selected child; the current screen root cannot be deleted.

The canvas can be scrolled horizontally and vertically. Zoom changes its
display scale, while the width selector changes actual layout constraints.
On smaller windows scroll the workspace horizontally to reach the inspector.

If a Row's content exceeds its width, Flutter's debug build shows its normal
overflow indicator. This MVP does not automatically repair layouts. Reduce
fixed widths, shorten content, or change the layout to a Column. Release
builds do not show Flutter's debug overflow stripes.

## 4. Style elements

Colors accept #RRGGBB or a shared token reference such as @accent.
Built-in color tokens are @accent, @ink, and @surface. Change a token in
the inspector and press Enter; every reference updates immediately.
Add token creates another named shared color. Token names use letters,
digits, and underscores and must begin with a letter.

Text supports font size and text color. Buttons support background,
foreground, and radius. Layouts support background, radius, padding,
child spacing, and optional fixed dimensions. Numerical inputs accept
0 through 10000. An empty field resets that property to its default.

## 5. Create reusable components

1. Select a child widget or a subtree on a screen.
2. Choose Create component and give it a unique name.
3. The selection becomes an instance; its definition appears in Components.
4. Drag that component onto another layout to add an instance.
5. Select an instance to override its root label, colors, dimensions, or
   event key. Unchanged properties are inherited from the definition.
6. Choose Edit shared component, or use its pencil icon in the left panel.
7. Edit the definition and its children. All instances inherit those edits,
   except properties explicitly overridden on an instance.
8. Choose Back to screen when finished.

Reset instance overrides removes all local property overrides. Shared color
tokens work inside component definitions and instance overrides.
An instance is selected as a whole; edit its definition to reach its children.

MVP boundary: exposed properties are the supported root properties. Custom
parameter schemas, child-slot overrides, named variants, component deletion,
and nested component instances are not supported yet. You can duplicate a
component's contents on a screen to create a separate definition for another
style. An existing instance or the screen root cannot become a component.

## 6. Assign events and connect behavior

Select a Button and enter an action key under onPressed, for example
savePreferences. Select an Input and enter an onChanged key such as
displayNameChanged. Press Enter to apply. Keys are labels, not executable
Dart expressions; dots and other characters are permitted in keys.

Turn on Interact to confirm the key and input value in the status bar.
The same keys are used in the exported widget's typed callback maps.

Exported widgets take:

    Map<String, VoidCallback> actions
    Map<String, ValueChanged<String>> changes

Example integration in your Flutter application (check the exact exported
class name; names include an index to avoid collisions):

    Scaffold(
      body: SingleChildScrollView(
        child: DesignSettings0(
          actions: {'savePreferences': () { /* your save code */ }},
          changes: {'displayNameChanged': (value) { /* your code */ }},
        ),
      ),
    )

Keep your application state and behavior in your own Dart files. The export
contains StatelessWidget classes and never edits your behavior files.
Unassigned buttons are interactive no-ops; unassigned inputs have no handler.
Component instances inherit root event keys unless explicitly overridden.
Events inside a composite component use the shared callback maps.

## 7. Save, reopen, undo, and export

Save opens a native file picker on first use. Projects use .canvas.json
files containing screens, components, tokens, and assignments. Save as
creates a separately named project. Ctrl+S saves; Ctrl+O opens a project.
Invalid files are rejected without replacing your current project.
The temporary sibling .pending file protects an existing save from failed
writes. If a save fails, your changes remain in memory; choose Save as.

Undo and Redo toolbar buttons apply to design changes, including tokens,
components, screen creation, and imports. The history keeps the latest 80
changes in memory. Opening a project clears history. Preview interactions
and selection are not design changes and are not saved in undo history.

Export Dart writes a generated_ui.dart file wherever you choose. It contains
all screens and reusable components, with typed root styling parameters.
Instances call the generated component class rather than copy its subtree.
Style tokens are resolved to concrete colors at export time.

Import generated_ui.dart into an existing Flutter application, wrap a screen
in Scaffold/SafeArea/scrolling as appropriate, and pass your callback maps.
Exported screens are content widgets, not full applications. Preview input
values are temporary and are not exported as initial application state.
Re-export after design changes; retain behavior in separate files. Arbitrary
Dart import and round-trip source editing are not available.

## 8. Bring in a Figma design

The optional bridge is a small Figma development plugin in figma_bridge/.
Figma itself requires its normal Figma access; Frame never asks
you to sign in, receives credentials, or connects to your Figma account.

1. Open Figma desktop and its Plugins > Development tools.
2. Create a local development plugin in Figma and copy its generated ID into
   figma_bridge/manifest.json, replacing the placeholder id. Then import
   that manifest. This is Figma's plugin registration; it creates no editor
   account or connection to Frame.
3. Select one or more screen frames. Use Auto Layout whenever possible.
4. Run Frame Bridge and choose Export selection.
5. Save the resulting figma.canvas-package.json file.
6. In this editor choose Figma import and select that package with the native
   picker. Imported screens are added to your existing project.
7. Read the conversion report. Adjust layout and styling in the inspector.
8. Create editor components from imported subtrees, then assign event keys.

An example package is in examples/figma.canvas-package.json, so you can try
import without using Figma. Its matching target preview is a settings card.

The importer supports text, solid fills, corner radius, basic spacing,
and horizontal/vertical Auto Layout. Free-positioned children become a
vertical layout. Unequal padding becomes the largest edge. Components and
instances become editable layouts; their original links are not retained.
Fonts, strokes, effects, vector paths, images, mixed text styling, design
variable links, variants, resizing rules, and prototype behavior are not
preserved. The conversion report identifies simplifications it detects.
Original Figma node IDs are kept as source metadata. Reimport adds new
screens; there is no merging or bidirectional synchronization in the MVP.

The plugin makes no network requests. Exported packages contain design
structure and text, so store them with the same care as your design files.
OS-level drag-and-drop file import and a direct Send to editor connection
are deferred; use the Figma import picker in this version.

## 9. Troubleshooting and scope

- A field did not update: press Enter after editing it.
- A widget will not accept a drop: use a layout widget or its Layers entry.
- A label does not inherit edits: Reset instance overrides.
- An event does nothing: supply its exact key in the appropriate callback map.
- Opening/importing fails: read the status bar; the current project stays intact.
- Input is not editable: enable Interact.
- Nothing needs to log in: there is no editor authentication or cloud storage.

This MVP covers local layout editing, root component overrides, color tokens,
event keys, project files, Dart export, and a limited one-way Figma bridge.
It does not include arbitrary Dart execution, plugin widgets, assets, flex
layout editing, Stack/free positioning, animations, collaboration, named
component variants, custom fonts, or automatic responsive breakpoints.

## 10. Developer verification

Run `flutter test` for the model, importer, editor, and exported-widget checks.
Run `dart run tool/export_fixture.dart` before tests after changing generation.
Build a Windows bundle with `flutter build windows --release`.
Do not run flutter analyze; this project follows the supplied instruction.
