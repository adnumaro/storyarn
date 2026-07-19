export interface ConnectionRemovalPayload extends Record<string, unknown> {
  id?: number;
  source_node_id: string | number;
  source_pin: string;
  target_node_id: string | number;
  target_pin: string;
}

interface CanvasConnectionIdentity {
  id: string;
  sourceOutput: string;
  targetInput: string;
}

export function buildConnectionRemovalPayload(
  connection: CanvasConnectionIdentity,
  sourceNodeId: string | number,
  targetNodeId: string | number,
  persistedId?: number,
): ConnectionRemovalPayload {
  return {
    ...(persistedId == null ? {} : { id: persistedId }),
    source_node_id: sourceNodeId,
    source_pin: connection.sourceOutput,
    target_node_id: targetNodeId,
    target_pin: connection.targetInput,
  };
}

export function matchesConnectionRemoval(
  connection: CanvasConnectionIdentity,
  payload: ConnectionRemovalPayload,
  persistedId?: number,
): boolean {
  if (payload.id != null) {
    return persistedId === payload.id || connection.id === `conn-${payload.id}`;
  }

  return (
    payload.source_pin !== "" &&
    payload.target_pin !== "" &&
    connection.sourceOutput === payload.source_pin &&
    connection.targetInput === payload.target_pin
  );
}
