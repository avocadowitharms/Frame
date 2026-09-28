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
Stack preserves overlapping layers at fixed X/Y positions. Drag its children
on the canvas to move them, or edit X position and Y position in the inspector.
One canvas drag is one undo step. A new Stack starts at 320 by 240 pixels.
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

Colors accept #RRGGBB, #AARRGGBB (with alpha), or a token such as @accent.
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
The separate Frame Bridge download contains manifest.json, code.js, ui.html,
and a setup README. Extract all its files into one folder, for example
C:\Users\YOUR_NAME\Documents\FrameBridge. Do not move only the manifest.
Source checkout users find the same files under their Frame folder's
figma_bridge subfolder. On this development machine that is:
C:\Users\Ava\Documents\GitHub\frame\figma_bridge\manifest.json
Figma itself requires its normal Figma access; Frame never asks
you to sign in, receives credentials, or connects to your Figma account.

1. Open Figma desktop and choose Plugins > Development > New plugin.
2. Name it Frame Bridge. Choose Figma design, then Custom UI.
3. Save Figma's generated template in a DIFFERENT folder, for example
   Documents\FrameBridgeRegistration. Do not overwrite the bridge download.
4. In that registration folder, open manifest.json in Notepad. Copy only
   the quoted value beside "id".
5. Open manifest.json in the extracted FrameBridge folder (or the source
   checkout's figma_bridge folder). Replace its id value with the copied
   value and save. Keep main set to code.js and ui set to ui.html.
6. In Figma choose Plugins > Development > Import plugin from manifest.
   Select the BRIDGE folder's manifest, not the registration template's file.
7. Select one or more screen frames, then run Frame Bridge.
8. Leave Preserve text appearance as images checked for matching custom-font
   text. Turn it off for native Flutter Text widgets, which need matching
   fonts installed in Frame and bundled with your application.
9. Choose Export selection.
10. Save the resulting figma.canvas-package.json file.
11. In this editor choose Figma import and select that package with the native
   picker. Imported screens are added to your existing project.
12. Read the conversion report. Adjust positions and dimensions in the inspector.
13. Create editor components from imported subtrees, then assign event keys.

An example package is in examples/figma.canvas-package.json, so you can try
import without using Figma. Its matching target preview is a settings card.

Version 2 packages preserve original dimensions, positions, layer order,
transparent groups, frame clipping, and rounded corners. Frame imports
containers as sized Stack widgets; Auto Layout is captured at its current
positions too, rather than guessing responsive Flutter constraints.
Artwork, vectors, image fills, and complex effects are embedded as PNGs.
Complex groups (including cards with shadows) become a single image.
They are movable, resizable, reusable layers; their vector paths / child
elements cannot be edited inside Frame. Attach onTap action keys to images
to make them interactive in the exported Dart.

Preserved text is an image-backed Text layer with its original content kept
for accessibility. Editing its text, font size, font family, or text color
removes the snapshot and switches to native Text. Use native Flutter text
does the same explicitly. Its appearance can then differ if the font is
unavailable. Images are embedded in project JSON and exported Dart, so you
do not have to copy assets separately. Large screens can increase file sizes.
Individual PNGs are limited to 16 megapixels; projects and imports to 32 MB.

Layouts have fixed positions and do not automatically reflow when resized.
Component links, variable bindings, named variants, resizing rules, and
prototype behavior are not retained. The report states which layers use
image fallbacks. Exported Dart uses Stack/Positioned and Image.memory for
those layers, rather than claiming they are editable Flutter vectors.

Old version 1 free-positioned packages lack coordinates and artwork; Frame
rejects them with a re-export instruction. Update the bridge, close its old
plugin window, run it again, and export a new package. Existing project files
still open, but missing details cannot be recovered from an old import.
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
- Figma says a TypeScript template needs compiling: you ran the generated
  registration template. Import the bridge folder's manifest and run that
  plugin instead. Frame Bridge is plain JavaScript and needs no compilation.

This MVP covers local layout editing, root component overrides, color tokens,
event keys, project files, Dart export, and a limited one-way Figma bridge.
It does not include arbitrary Dart execution, plugin widgets, a vector-path
editor, flex layout editing, animations, collaboration, named component
variants, font-file embedding, or automatic responsive breakpoints.

## 10. Developer verification

Run `flutter test` for the model, importer, editor, and exported-widget checks.
Run `node tool/check_figma_bridge.cjs`, then `dart run tool/export_fixture.dart`
before tests after changing generation or import. The Node check runs the
actual bridge with a small mock Figma host; live Figma export is a separate
manual verification step.
Build a Windows bundle with `flutter build windows --release`.
Do not run flutter analyze; this project follows the supplied instruction.
