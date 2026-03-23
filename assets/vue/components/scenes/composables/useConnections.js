import { computed } from "vue";

const DEFAULT_COLOR = "#ffffff";
const DEFAULT_WIDTH = 3;
const DEFAULT_OPACITY = 1;
const ARROW_SIZE = 16;
const ARROW_ANGLE = Math.PI / 6; // 30 degrees half-angle
const LABEL_COLOR = "#d1d5db";

const DASH_PATTERNS = {
	solid: null,
	dashed: [10, 6],
	dotted: [3, 6],
};

/**
 * Composable for computing connection render configs.
 * Handles pin position lookup, waypoint conversion, arrowheads, and label placement.
 */
export function useConnections({
	connections,
	pins,
	layers,
	percentToPixel,
	selectedType,
	selectedId,
	isSelectMode,
}) {
	// Pin pixel positions keyed by id
	const pinPositions = computed(() => {
		const map = {};
		for (const pin of pins.value) {
			map[pin.id] = percentToPixel(pin.positionX, pin.positionY);
		}
		return map;
	});

	// Hidden layer IDs
	const hiddenLayerIds = computed(() => {
		const set = new Set();
		for (const layer of layers.value) {
			if (!layer.visible) set.add(layer.id);
		}
		return set;
	});

	// Pin visibility by id (true if pin's layer is visible or pin has no layer)
	const pinVisible = computed(() => {
		const vis = {};
		for (const pin of pins.value) {
			vis[pin.id] = !pin.layerId || !hiddenLayerIds.value.has(pin.layerId);
		}
		return vis;
	});

	const connectionConfigs = computed(() => {
		const result = [];

		for (const conn of connections.value) {
			const fromPos = pinPositions.value[conn.fromPinId];
			const toPos = pinPositions.value[conn.toPinId];
			if (!fromPos || !toPos) continue;

			// Hide if both endpoint pins are on hidden layers
			const fromVis = pinVisible.value[conn.fromPinId] !== false;
			const toVis = pinVisible.value[conn.toPinId] !== false;
			if (!fromVis && !toVis) continue;

			// Build points: [from, ...waypoints, to]
			const pixelPath = [fromPos];
			const waypoints = conn.waypoints || [];
			for (const wp of waypoints) {
				pixelPath.push(percentToPixel(wp.x, wp.y));
			}
			pixelPath.push(toPos);

			// Flat points for Konva v-line
			const points = [];
			for (const p of pixelPath) {
				points.push(p.x, p.y);
			}

			const color = conn.color || DEFAULT_COLOR;
			const strokeWidth = conn.lineWidth || DEFAULT_WIDTH;

			// Forward arrow (into toPin)
			const lastSeg =
				pixelPath.length >= 2
					? {
							fromX: pixelPath[pixelPath.length - 2].x,
							fromY: pixelPath[pixelPath.length - 2].y,
							toX: toPos.x,
							toY: toPos.y,
						}
					: null;
			const forwardArrow = lastSeg
				? computeArrowHead(
						lastSeg.toX,
						lastSeg.toY,
						lastSeg.fromX,
						lastSeg.fromY,
					)
				: null;

			// Reverse arrow (into fromPin, only if bidirectional)
			let reverseArrow = null;
			if (conn.bidirectional && pixelPath.length >= 2) {
				reverseArrow = computeArrowHead(
					fromPos.x,
					fromPos.y,
					pixelPath[1].x,
					pixelPath[1].y,
				);
			}

			// Label at path midpoint
			let labelConfig = null;
			if (conn.showLabel !== false && conn.label) {
				const mid = pathMidpointAndAngle(pixelPath);
				if (mid) {
					labelConfig = {
						text: conn.label,
						x: mid.x,
						y: mid.y,
						offsetX: 60,
						offsetY: 10,
						rotation: mid.angle,
						fill: LABEL_COLOR,
						fontSize: 13,
						fontStyle: "600",
						align: "center",
						width: 120,
						shadowColor: "black",
						shadowBlur: 3,
						shadowOpacity: 0.8,
						listening: false,
					};
				}
			}

			const isSelected =
				selectedType?.value === "connection" && selectedId?.value === conn.id;

			result.push({
				id: conn.id,
				points,
				stroke: color,
				strokeWidth: isSelected ? Math.max(strokeWidth, 4) : strokeWidth,
				dash: DASH_PATTERNS[conn.lineStyle] || null,
				opacity: isSelected ? 1 : DEFAULT_OPACITY,
				forwardArrow,
				reverseArrow,
				arrowFill: color,
				labelConfig,
				isSelected,
				listening: isSelectMode?.value ?? false,
				hitStrokeWidth: 20,
			});
		}

		return result;
	});

	return { connectionConfigs };
}

// --- Geometry helpers ---

/**
 * Compute arrowhead triangle points (flat array for Konva v-line closed).
 * Tip is offset back from (tipX, tipY) along the approach direction so it
 * sits at the pin edge rather than behind the pin icon.
 */
const ARROW_OFFSET = 18;

function computeArrowHead(tipX, tipY, fromX, fromY) {
	const dx = tipX - fromX;
	const dy = tipY - fromY;
	const len = Math.sqrt(dx * dx + dy * dy);
	if (len < 1) return null;

	// Unit vector from approach to tip
	const ux = dx / len;
	const uy = dy / len;

	// Offset tip back along approach direction
	const tx = tipX - ux * ARROW_OFFSET;
	const ty = tipY - uy * ARROW_OFFSET;

	const angle = Math.atan2(dy, dx);
	const left = angle + Math.PI - ARROW_ANGLE;
	const right = angle + Math.PI + ARROW_ANGLE;

	return [
		tx,
		ty,
		tx + ARROW_SIZE * Math.cos(left),
		ty + ARROW_SIZE * Math.sin(left),
		tx + ARROW_SIZE * Math.cos(right),
		ty + ARROW_SIZE * Math.sin(right),
	];
}

/**
 * Find the midpoint of a pixel path and the readable angle of the segment there.
 * Returns { x, y, angle } where angle is in degrees, normalized to -90..+90.
 */
function pathMidpointAndAngle(pixelPath) {
	if (pixelPath.length < 2) return null;

	// Cumulative segment lengths
	const segLens = [];
	let total = 0;
	for (let i = 1; i < pixelPath.length; i++) {
		const dx = pixelPath[i].x - pixelPath[i - 1].x;
		const dy = pixelPath[i].y - pixelPath[i - 1].y;
		const d = Math.sqrt(dx * dx + dy * dy);
		segLens.push(d);
		total += d;
	}

	if (total === 0) return { x: pixelPath[0].x, y: pixelPath[0].y, angle: 0 };

	// Walk to halfway
	let remaining = total / 2;
	let segIdx = 0;
	for (; segIdx < segLens.length - 1; segIdx++) {
		if (remaining <= segLens[segIdx]) break;
		remaining -= segLens[segIdx];
	}

	const ratio = segLens[segIdx] > 0 ? remaining / segLens[segIdx] : 0;
	const x =
		pixelPath[segIdx].x +
		(pixelPath[segIdx + 1].x - pixelPath[segIdx].x) * ratio;
	const y =
		pixelPath[segIdx].y +
		(pixelPath[segIdx + 1].y - pixelPath[segIdx].y) * ratio;

	// Angle in screen space
	const dx = pixelPath[segIdx + 1].x - pixelPath[segIdx].x;
	const dy = pixelPath[segIdx + 1].y - pixelPath[segIdx].y;
	let angle = (Math.atan2(dy, dx) * 180) / Math.PI;

	// Normalize so text is never upside-down
	if (angle > 90) angle -= 180;
	if (angle < -90) angle += 180;

	return { x, y, angle: Math.round(angle * 10) / 10 };
}
