/** Shared types for the exploration module */

export interface Vertex {
  x: number;
  y: number;
}

export interface ExplorationPin {
  id: number | string;
  positionX: number;
  positionY: number;
  isPlayable: boolean;
  isLeader: boolean;
  visibility: string;
}

export interface ExplorationZone {
  id: number | string;
  actionType?: string | null;
  isWalkable: boolean;
  vertices: Vertex[] | null;
  visibility: string;
}

export interface PixelPoint {
  x: number;
  y: number;
}

export interface PartyPosition {
  id: number | string;
  x: number;
  y: number;
}
