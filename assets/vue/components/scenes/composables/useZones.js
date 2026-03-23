import { computed } from "vue";
import { renderLockBadge } from "../lib/pin-icons";

const DEFAULT_FILL_COLOR = "#3b82f6";
const DEFAULT_BORDER_COLOR = "#1e40af";

const DASH_PATTERNS = {
	solid: null,
	dashed: [10, 6],
	dotted: [3, 6],
};

/**
 * Composable for computing zone render configs from raw zone data.
 * Handles layer filtering, vertex coordinate conversion, style mapping, and lock state.
 */
export function useZones({
	zones,
	layers,
	entityLocks,
	currentUserId,
	percentToPixel,
}) {
	const hiddenLayerIds = computed(() => {
		const set = new Set();
		for (const layer of layers.value) {
			if (!layer.visible) set.add(layer.id);
		}
		return set;
	});

	const visibleZones = computed(() =>
		zones.value.filter(
			(zone) => !(zone.layerId && hiddenLayerIds.value.has(zone.layerId)),
		),
	);

	const zoneConfigs = computed(() =>
		visibleZones.value
			.slice()
			.sort((a, b) => (a.position || 0) - (b.position || 0))
			.map((zone) => {
				const vertices = zone.vertices || [];
				const pixelCoords = vertices.map((v) => percentToPixel(v.x, v.y));

				// Flat points array for Konva v-line: [x1, y1, x2, y2, ...]
				const points = [];
				let sumX = 0;
				let sumY = 0;
				let maxX = -Infinity;
				let minY = Infinity;

				for (const p of pixelCoords) {
					points.push(p.x, p.y);
					sumX += p.x;
					sumY += p.y;
					if (p.x > maxX) maxX = p.x;
					if (p.y < minY) minY = p.y;
				}

				const count = pixelCoords.length || 1;
				const centroidX = sumX / count;
				const centroidY = sumY / count;

				const lock = entityLocks.value[String(zone.id)];
				const isLockedByOther =
					!!lock && String(lock.userId) !== String(currentUserId.value);

				return {
					id: zone.id,
					name: zone.name,
					points,
					centroidX,
					centroidY,
					fill: zone.fillColor || DEFAULT_FILL_COLOR,
					stroke: zone.borderColor || DEFAULT_BORDER_COLOR,
					strokeWidth: zone.borderWidth ?? 2,
					dash: DASH_PATTERNS[zone.borderStyle] || null,
					opacity: zone.opacity ?? 0.3,
					isLockedByOther,
					lockBadge: isLockedByOther ? renderLockBadge() : null,
					lockBadgeX: maxX - 4,
					lockBadgeY: minY - 10,
				};
			}),
	);

	return { zoneConfigs };
}
