/**
 * LOD (Level of Detail) controller for the flow canvas.
 *
 * Watches zoom level and switches nodes between "full" and "simplified"
 * rendering tiers. Uses a hysteresis band (0.40–0.45) to prevent rapid
 * toggling and batches DOM updates (50 nodes per rAF frame) to avoid
 * long-frame freezes on large flows.
 */

const LOD_FULL = "full";
const LOD_SIMPLIFIED = "simplified";
const ZOOM_DOWN = 0.4; // switch to simplified below this
const ZOOM_UP = 0.45; // switch to full above this
const BATCH_SIZE = 50; // nodes per rAF frame during LOD transition

export function createLodController(hook, initialLod = LOD_FULL) {
  let currentLod = initialLod;
  let rafId = null;
  let batchRafId = null;

  function computeLod(k) {
    if (currentLod === LOD_FULL && k < ZOOM_DOWN) return LOD_SIMPLIFIED;
    if (currentLod === LOD_SIMPLIFIED && k > ZOOM_UP) return LOD_FULL;
    return currentLod;
  }

  /** Apply LOD in batches of BATCH_SIZE nodes per rAF frame. */
  function applyLod(newLod) {
    if (newLod === currentLod) return;
    currentLod = newLod;
    hook.currentLod = newLod;

    // Cancel any in-flight batch from a previous transition
    if (batchRafId) cancelAnimationFrame(batchRafId);

    const views = [...hook.area.nodeViews.values()];
    let i = 0;

    function processBatch() {
      batchRafId = null;
      const end = Math.min(i + BATCH_SIZE, views.length);
      for (; i < end; i++) {
        const el = views[i].element.querySelector("storyarn-node");
        if (el) el.lod = newLod;
      }
      if (i < views.length) {
        batchRafId = requestAnimationFrame(processBatch);
      } else {
        // Re-attach lock indicators after the last batch
        // (they live on nodeView.element, outside Shadow DOM)
        hook.lockHandler?.updateLockIndicators();
      }
    }

    processBatch();
  }

  function check() {
    rafId = null;
    const k = hook.area.area.transform.k;
    applyLod(computeLod(k));
  }

  return {
    onZoom() {
      if (!rafId) rafId = requestAnimationFrame(check);
    },

    destroy() {
      if (rafId) cancelAnimationFrame(rafId);
      if (batchRafId) cancelAnimationFrame(batchRafId);
    },
  };
}
