/**
 * LOD (Level of Detail) composable for the flow canvas.
 *
 * Watches zoom level and switches between "full" and "simplified"
 * rendering tiers. Uses a hysteresis band (0.40-0.45) to prevent rapid
 * toggling. Nodes read the LOD value reactively via inject from
 * hookProxy._flowContext.lod.
 */

import type { AreaPlugin } from "rete-area-plugin";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";
import type { HookProxy } from "./editorHandlers";

export type LodLevel = "full" | "simplified";

export interface LodController {
  currentLod: LodLevel;
  onZoom(): void;
  destroy(): void;
}

const LOD_FULL: LodLevel = "full";
const LOD_SIMPLIFIED: LodLevel = "simplified";
const ZOOM_DOWN = 0.4; // switch to simplified below this
const ZOOM_UP = 0.45; // switch to full above this
const MIN_NODES_FOR_LOD = 50; // skip LOD when fewer nodes

export function lod(area: AreaPlugin<FlowSchemes, FlowAreaExtra>, hookProxy: HookProxy): LodController {
  let currentLod: LodLevel = LOD_FULL;
  let rafId: number | null = null;

  hookProxy._flowContext.lod = currentLod;

  function computeLod(k: number): LodLevel {
    if (currentLod === LOD_FULL && k < ZOOM_DOWN) {
      return LOD_SIMPLIFIED;
    }
    if (currentLod === LOD_SIMPLIFIED && k > ZOOM_UP) {
      return LOD_FULL;
    }
    return currentLod;
  }

  function applyLod(newLod: LodLevel): void {
    if (newLod === currentLod) {
      return;
    }
    currentLod = newLod;
    hookProxy._flowContext.lod = newLod;
  }

  function check(): void {
    rafId = null;
    const nodeCount = area.nodeViews.size;
    if (nodeCount < MIN_NODES_FOR_LOD) {
      if (currentLod !== LOD_FULL) {
        applyLod(LOD_FULL);
      }
      return;
    }
    const k = area.area.transform.k;
    applyLod(computeLod(k));
  }

  function onZoom(): void {
    if (!rafId) {
      rafId = requestAnimationFrame(check);
    }
  }

  function destroy(): void {
    if (rafId) {
      cancelAnimationFrame(rafId);
    }
  }

  return { currentLod, onZoom, destroy };
}
