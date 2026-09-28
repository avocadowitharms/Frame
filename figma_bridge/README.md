# Frame Bridge setup

Keep manifest.json, code.js, and ui.html together in this extracted folder.
Use Figma desktop to create a development plugin: Figma design > Custom UI.
Save that generated template to a SEPARATE registration folder. Open its
manifest.json in Notepad and copy the id value.

Paste that value into THIS folder's manifest.json, keeping the other fields.
Then in Figma use Plugins > Development > Import plugin from manifest and
select THIS manifest. The generated registration template is not the bridge.
If you see a TypeScript template error, you are running the template instead.
This bridge is JavaScript; there is no compile step.

Select screen frames and run Frame Bridge. Keep Preserve text appearance as
images checked for custom fonts. Export selection downloads a local version 2
JSON package. In Frame use Figma import to select that package.

Positions, layering, and original dimensions are retained. Complex artwork
and groups use images, which can be moved, resized, reused, and given events.
Image-backed text retains accessible labels; editing it changes to native
Flutter text and may require installing/bundling the original font.
Fixed layouts are not automatically responsive.

After updating code.js or ui.html, close the old plugin window and rerun it.
Re-export old version 1 packages: they lack position and image information.
No network requests or Frame accounts are used.
