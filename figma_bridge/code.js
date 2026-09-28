figma.showUI(__html__, { width: 400, height: 350 });
const containers = ['FRAME', 'GROUP', 'COMPONENT', 'INSTANCE', 'COMPONENT_SET'];
// ponytail: complex artwork and font appearances use 2x PNG layers; add native vector/font support when editing their internals is required.
function needsSnapshot(node) {
  const visible = values => Array.isArray(values) && values.some(v => v.visible !== false);
  const transform = node.absoluteTransform;
  return !containers.includes(node.type) || node.opacity !== undefined && node.opacity !== 1 ||
    node.blendMode && !['NORMAL', 'PASS_THROUGH'].includes(node.blendMode) ||
    visible(node.effects) || visible(node.strokes) ||
    Array.isArray(node.fills) && (node.fills.filter(f => f.visible !== false).length > 1 || node.fills.some(f => f.visible !== false && f.type !== 'SOLID')) ||
    transform && (Math.abs(transform[0][0] - 1) > .00001 || Math.abs(transform[1][1] - 1) > .00001 || Math.abs(transform[0][1]) > .00001 || Math.abs(transform[1][0]) > .00001) ||
    'children' in node && node.children.some(c => c.isMask) ||
    ['topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius'].some(k => typeof node[k] === 'number' && node[k] !== node.cornerRadius);
}
async function snapshot(node, useAbsoluteBounds) {
  const bounds = useAbsoluteBounds ? node.absoluteBoundingBox : node.absoluteRenderBounds || node.absoluteBoundingBox;
  if (!bounds || Math.ceil(bounds.width * 2) > 8192 || Math.ceil(bounds.height * 2) > 8192 || Math.ceil(bounds.width * 2) * Math.ceil(bounds.height * 2) > 16000000) throw new Error(`${node.name}: artwork exceeds the 16 megapixel limit at 2x. Export a smaller layer.`);
  const bytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 2 }, useAbsoluteBounds, contentsOnly: true, colorProfile: 'SRGB' });
  return figma.base64Encode(bytes);
}
async function nodeData(node, parentBounds, context, depth = 0) {
  if (depth > 30 || ++context.count > 3000) throw new Error('Export exceeds 3000 nodes or 30 levels. Select a smaller frame.');
  const textSnapshot = node.type === 'TEXT' && context.preserveText;
  const raster = needsSnapshot(node) && (node.type !== 'TEXT' || context.preserveText);
  const bounds = raster && !textSnapshot ? node.absoluteRenderBounds || node.absoluteBoundingBox : node.absoluteBoundingBox;
  if (!bounds) return null;
  if (![bounds.x, bounds.y, bounds.width, bounds.height].every(Number.isFinite)) throw new Error(`${node.name}: invalid bounds.`);
  if (bounds.width <= 0 || bounds.height <= 0) return null;
  const result = { id: node.id, name: node.name, type: node.type, x: parentBounds ? bounds.x - parentBounds.x : 0, y: parentBounds ? bounds.y - parentBounds.y : 0, width: bounds.width, height: bounds.height };
  for (const key of ['layoutMode', 'cornerRadius', 'clipsContent', 'characters', 'fontSize', 'fontName', 'fontWeight', 'lineHeight', 'letterSpacing', 'textAlignHorizontal', 'fills']) {
    const value = node[key]; if (value !== undefined && typeof value !== 'symbol') result[key] = value;
  }
  if (raster) { result.png = await snapshot(node, textSnapshot); result.rasterized = true; }
  else if ('children' in node) {
    result.children = [];
    for (const child of node.children) if (child.visible !== false) { const data = await nodeData(child, bounds, context, depth + 1); if (data) result.children.push(data); }
  }
  return result;
}
let exporting = false;
figma.ui.onmessage = async message => {
  if (message.type !== 'export' || exporting) return;
  const selection = [...figma.currentPage.selection];
  if (!selection.length) { figma.ui.postMessage({ error: 'Select one or more screen frames first.' }); return; }
  exporting = true; figma.ui.postMessage({ busy: true });
  try {
    const context = { count: 0, preserveText: message.preserveText !== false };
    const nodes = [];
    for (const node of selection) { const data = await nodeData(node, null, context); if (data) nodes.push(data); }
    if (!nodes.length) throw new Error('Selection has no visible artwork.');
    const data = JSON.stringify({ format: 'canvas-figma', version: 2, nodes }, null, 2);
    if (data.length > 32000000) throw new Error('Package exceeds 32 MB. Export fewer frames.');
    figma.ui.postMessage({ data });
  } catch (error) { figma.ui.postMessage({ error: String(error) }); }
  finally { exporting = false; figma.ui.postMessage({ busy: false }); }
};
