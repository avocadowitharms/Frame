figma.showUI(__html__, { width: 380, height: 280 });
function nodeData(node) {
  const result = { id: node.id, name: node.name, type: node.type, visible: node.visible };
  for (const key of ['width', 'height', 'layoutMode', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'itemSpacing', 'cornerRadius', 'characters', 'fontSize', 'fills', 'effects', 'strokes']) {
    const value = node[key];
    if (value !== undefined && typeof value !== 'symbol') result[key] = value;
  }
  if ('children' in node) result.children = node.children.map(nodeData);
  return result;
}
figma.ui.onmessage = message => {
  if (message.type !== 'export') return;
  const selection = figma.currentPage.selection;
  if (!selection.length) { figma.ui.postMessage({ error: 'Select one or more frames first.' }); return; }
  try {
    const data = { format: 'canvas-figma', version: 1, nodes: selection.map(nodeData) };
    figma.ui.postMessage({ data: JSON.stringify(data, null, 2) });
  } catch (error) { figma.ui.postMessage({ error: String(error) }); }
};
