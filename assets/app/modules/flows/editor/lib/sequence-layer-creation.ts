/** New images keep their natural aspect within the 16:9 composition frame. */
export function newSequenceLayerGeometry(
  kind: string,
  ratio: number,
  position?: { x: number; y: number },
) {
  if (kind === "backdrop" || kind === "overlay") {
    return {
      slot: "full",
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      anchor_x: 0,
      anchor_y: 0,
      fit: "cover",
    };
  }
  const character = kind === "character";
  const height = character ? 0.85 : 0.4;
  const anchorY = character ? 1 : 0.5;
  return {
    slot: "custom",
    x: position?.x ?? 0.5,
    y: position?.y ?? anchorY,
    width: Math.max(0.0001, Math.min(20, (height * ratio * 9) / 16)),
    height,
    anchor_x: 0.5,
    anchor_y: anchorY,
    fit: "contain",
  };
}
