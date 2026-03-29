/**
 * LOD (Level of Detail) composable for the flow canvas.
 *
 * Watches zoom level and switches between "full" and "simplified"
 * rendering tiers. Uses a hysteresis band (0.40-0.45) to prevent rapid
 * toggling. Nodes read the LOD value reactively via inject from
 * hookProxy._flowContext.lod.
 */

const LOD_FULL = "full";
const LOD_SIMPLIFIED = "simplified";
const ZOOM_DOWN = 0.4; // switch to simplified below this
const ZOOM_UP = 0.45; // switch to full above this
const MIN_NODES_FOR_LOD = 50; // skip LOD when fewer nodes

export function lod(area, hookProxy) {
	let currentLod = LOD_FULL;
	let rafId = null;

	hookProxy._flowContext.lod = currentLod;

	function computeLod(k) {
		if (currentLod === LOD_FULL && k < ZOOM_DOWN) {
			return LOD_SIMPLIFIED;
		}
		if (currentLod === LOD_SIMPLIFIED && k > ZOOM_UP) {
			return LOD_FULL;
		}
		return currentLod;
	}

	function applyLod(newLod) {
		if (newLod === currentLod) {
			return;
		}
		currentLod = newLod;
		hookProxy._flowContext.lod = newLod;
	}

	function check() {
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

	function onZoom() {
		if (!rafId) {
			rafId = requestAnimationFrame(check);
		}
	}

	function destroy() {
		if (rafId) {
			cancelAnimationFrame(rafId);
		}
	}

	return { currentLod, onZoom, destroy };
}
