import type { SequenceVisualLayerRecord } from "./types";

export function sequenceLayerKey(layer: SequenceVisualLayerRecord): string {
  return String(layer.key ?? layer.layer_key ?? layer.id);
}

/** The resolver supplies the effective order, including inherited order changes. */
export function compareSequenceLayers(
  a: SequenceVisualLayerRecord,
  b: SequenceVisualLayerRecord,
): number {
  const aStack = stackIndex(a);
  const bStack = stackIndex(b);
  if (aStack != null && bStack != null && aStack !== bStack) return aStack - bStack;
  const depth = layerDepth(a) - layerDepth(b);
  if (depth !== 0) return depth;
  const zIndex = layerZIndex(a) - layerZIndex(b);
  return zIndex || sequenceLayerKey(a).localeCompare(sequenceLayerKey(b));
}

function stackIndex(layer: SequenceVisualLayerRecord) {
  return layer.stackIndex ?? layer.stack_index;
}
function layerDepth(layer: SequenceVisualLayerRecord) {
  return layer.sequenceDepth ?? layer.sequence_depth ?? 0;
}
function layerZIndex(layer: SequenceVisualLayerRecord) {
  return layer.zIndex ?? layer.z_index ?? 0;
}
