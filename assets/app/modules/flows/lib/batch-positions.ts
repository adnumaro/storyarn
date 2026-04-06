/**
 * Builds a positions array from a Map of reteNodeId -> {x, y} for batch position updates.
 * Converts Rete IDs ("node-123") to server IDs (123).
 */

export interface Position {
  x: number;
  y: number;
}

export interface BatchPosition {
  id: number;
  position_x: number;
  position_y: number;
}

export function buildBatchPositions(positionsMap: Map<string, Position>): BatchPosition[] {
  const result: BatchPosition[] = [];
  for (const [reteNodeId, pos] of positionsMap) {
    const serverId = reteNodeId.replace("node-", "");
    const id = Number.parseInt(serverId, 10);
    if (Number.isNaN(id)) {
      continue;
    }
    result.push({ id, position_x: pos.x, position_y: pos.y });
  }
  return result;
}
