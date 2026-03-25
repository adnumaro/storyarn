import { computed } from "vue";
import { PIN_SIZES } from "../lib/pin-icons";
import { useHiddenLayerIds } from "./useLayerVisibility";

const DEFAULT_COLOR = "#ffffff";
const DEFAULT_WIDTH = 3;
const DEFAULT_OPACITY = 1;
const ARROW_POINTER_LENGTH = 8;
const ARROW_POINTER_WIDTH = 12;
const LABEL_COLOR = "#d1d5db";
const EDGE_GAP = 4;

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
	dragOverrides,
	waypointEditOverride,
}) {
	// Pin pixel positions keyed by id — uses drag overrides for real-time connection updates
	const pinPositions = computed(() => {
		const overrides = dragOverrides?.value || {};
		const map = {};
		for (const pin of pins.value) {
			// If pin is being dragged, use the live pixel position from drag
			map[pin.id] =
				overrides[pin.id] || percentToPixel(pin.positionX, pin.positionY);
		}
		return map;
	});

	// Pin radii keyed by id — used to offset arrow endpoints to circle edge
	const pinRadii = computed(() => {
		const map = {};
		for (const pin of pins.value) {
			const dims = PIN_SIZES[pin.size || "md"] || PIN_SIZES.md;
			map[pin.id] = dims.diameter / 2;
		}
		return map;
	});

	const hiddenLayerIds = useHiddenLayerIds(layers);

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

			// Build pixel path: [from, ...waypoints, to] (center-to-center)
			// Use live-edited waypoints if this connection is being edited
			const override = waypointEditOverride?.value;
			const waypoints =
				override && override.connectionId === conn.id
					? override.waypoints
					: conn.waypoints || [];

			const rawPath = [fromPos];
			for (const wp of waypoints) {
				rawPath.push(percentToPixel(wp.x, wp.y));
			}
			rawPath.push(toPos);

			// Offset endpoints from pin center to circle edge so arrowheads are visible
			// (following Konva "Connected Objects" pattern: getConnectorPoints)
			const fromRadius = pinRadii.value[conn.fromPinId] || 0;
			const toRadius = pinRadii.value[conn.toPinId] || 0;
			const pixelPath = offsetEndpoints(rawPath, fromRadius, toRadius);

			// Flat points for Konva v-arrow
			const points = [];
			for (const p of pixelPath) {
				points.push(p.x, p.y);
			}

			const color = conn.color || DEFAULT_COLOR;
			const strokeWidth = conn.lineWidth || DEFAULT_WIDTH;

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
				fill: color,
				strokeWidth: isSelected ? Math.max(strokeWidth, 4) : strokeWidth,
				dash: DASH_PATTERNS[conn.lineStyle] || null,
				opacity: isSelected ? 1 : DEFAULT_OPACITY,
				pointerLength: ARROW_POINTER_LENGTH,
				pointerWidth: ARROW_POINTER_WIDTH,
				pointerAtBeginning: !!conn.bidirectional,
				pointerAtEnding: true,
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
 * Offset the first and last point of a path inward so they sit on the edge of
 * the pin circles instead of at their centers. This makes arrowheads visible
 * instead of being hidden behind the pin.
 * Follows the Konva "Connected Objects" demo pattern.
 */
function offsetEndpoints(path, fromRadius, toRadius) {
	if (path.length < 2) return path;

	const result = path.slice();

	// Offset start point: move along the direction toward the second point
	if (fromRadius > 0) {
		const first = path[0];
		const second = path[1];
		const dx = second.x - first.x;
		const dy = second.y - first.y;
		const dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > 0) {
			const offset = (fromRadius + EDGE_GAP) / dist;
			result[0] = { x: first.x + dx * offset, y: first.y + dy * offset };
		}
	}

	// Offset end point: move along the direction toward the second-to-last point
	if (toRadius > 0) {
		const last = path[path.length - 1];
		const prev = path[path.length - 2];
		const dx = prev.x - last.x;
		const dy = prev.y - last.y;
		const dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > 0) {
			const offset = (toRadius + EDGE_GAP) / dist;
			result[result.length - 1] = {
				x: last.x + dx * offset,
				y: last.y + dy * offset,
			};
		}
	}

	return result;
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
