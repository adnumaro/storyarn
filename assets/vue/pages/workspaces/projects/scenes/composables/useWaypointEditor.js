import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive.js";

const WAYPOINT_RADIUS = 6;
const MIDPOINT_RADIUS = 4;
const WAYPOINT_FILL = "#ffffff";
const WAYPOINT_STROKE = "#f97316"; // orange-500
const MIDPOINT_FILL = "#fed7aa"; // orange-200
const MIDPOINT_STROKE = "#ea580c"; // orange-600

/**
 * Composable for editing connection path waypoints via draggable anchor points.
 *
 * Activated by double-clicking a connection. Shows waypoint handles (drag to reshape)
 * and midpoint handles on every segment (click to insert new waypoint).
 * Ctrl+click removes a waypoint. No minimum — all waypoints can be removed.
 *
 * Midpoints include the segments from from_pin → first waypoint and
 * last waypoint → to_pin, so new waypoints can be added anywhere on the path.
 *
 * @param {Object} opts
 * @param {import('vue').Ref<Array>} opts.connections - connection data
 * @param {import('vue').Ref<Array>} opts.pins - pin data (for endpoint positions)
 * @param {Function} opts.pixelToPercent - (pixelX, pixelY) => { x, y }
 * @param {Function} opts.percentToPixel - (pctX, pctY) => { x, y }
 * @param {import('vue').Ref<string|null>} opts.selectedType
 * @param {import('vue').Ref<number|null>} opts.selectedId
 */
export function useWaypointEditor({
	connections,
	pins,
	pixelToPercent,
	percentToPixel,
	selectedType,
	selectedId,
}) {
	const live = useLive();

	const editingConnectionId = ref(null);
	const editingWaypoints = ref([]); // [{x, y}] in percent coords

	const isEditing = computed(() => editingConnectionId.value !== null);

	// --- The connection being edited ---
	const editingConnection = computed(() => {
		if (!editingConnectionId.value) {
			return null;
		}
		return connections.value.find((c) => c.id === editingConnectionId.value);
	});

	// --- Start/stop editing ---

	function startEditing(connectionId) {
		const conn = connections.value.find((c) => c.id === connectionId);
		if (!conn) {
			return;
		}
		editingConnectionId.value = connectionId;
		editingWaypoints.value = (conn.waypoints || []).map((w) => ({
			x: w.x,
			y: w.y,
		}));
	}

	function stopEditing() {
		editingConnectionId.value = null;
		editingWaypoints.value = [];
	}

	// --- Drag waypoint ---

	function onWaypointDragMove(index, e) {
		const node = e.target;
		const pos = pixelToPercent(node.x(), node.y());
		const wps = [...editingWaypoints.value];
		wps[index] = { x: pos.x, y: pos.y };
		editingWaypoints.value = wps;
	}

	function onWaypointDragEnd() {
		persistWaypoints();
	}

	// --- Insert waypoint at midpoint click ---

	function insertWaypoint(segmentIndex, e) {
		if (e) {
			e.cancelBubble = true;
		}

		// Build the full path: [fromPin, ...waypoints, toPin] in percent coords
		const fullPath = getFullPathPercent();
		if (!fullPath) {
			return;
		}

		// segmentIndex refers to the segment between fullPath[segmentIndex] and fullPath[segmentIndex+1]
		const a = fullPath[segmentIndex];
		const b = fullPath[segmentIndex + 1];
		if (!a || !b) {
			return;
		}

		const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };

		// Convert segmentIndex to waypoint insert position
		// fullPath[0] = fromPin, fullPath[1..n] = waypoints, fullPath[n+1] = toPin
		// Waypoint insert index = segmentIndex (offset by -1 for the fromPin, but +1 cancels)
		const waypointInsertIndex = segmentIndex; // insert BEFORE waypoint at this position
		const wps = [...editingWaypoints.value];
		wps.splice(waypointInsertIndex, 0, mid);
		editingWaypoints.value = wps;
		persistWaypoints();
	}

	// --- Remove waypoint (Ctrl+click) ---

	function onWaypointClick(index, e) {
		if (e) {
			e.cancelBubble = true;
		}
		const evt = e.evt || e;
		if (evt.ctrlKey || evt.metaKey) {
			const wps = [...editingWaypoints.value];
			wps.splice(index, 1);
			editingWaypoints.value = wps;
			persistWaypoints();
		}
	}

	// --- Persist to server ---

	function persistWaypoints() {
		if (!editingConnectionId.value) {
			return;
		}
		const waypoints = editingWaypoints.value.map((w) => ({
			x: Math.round(w.x * 100) / 100,
			y: Math.round(w.y * 100) / 100,
		}));
		live.pushEvent("update_connection_waypoints", {
			id: String(editingConnectionId.value),
			waypoints,
		});
	}

	// --- Full path in percent coords (from_pin + waypoints + to_pin) ---

	function getFullPathPercent() {
		const conn = editingConnection.value;
		if (!conn) {
			return null;
		}

		const fromPin = pins.value.find((p) => p.id === conn.fromPinId);
		const toPin = pins.value.find((p) => p.id === conn.toPinId);
		if (!fromPin || !toPin) {
			return null;
		}

		return [
			{ x: fromPin.positionX, y: fromPin.positionY },
			...editingWaypoints.value,
			{ x: toPin.positionX, y: toPin.positionY },
		];
	}

	// --- Computed Konva configs for anchors ---

	const waypointEditorConfigs = computed(() => {
		if (!isEditing.value) {
			return null;
		}

		const fullPath = getFullPathPercent();
		if (!fullPath) {
			return null;
		}

		const pixelPath = fullPath.map((p) => percentToPixel(p.x, p.y));
		const wps = editingWaypoints.value;
		const pixelWps = wps.map((w) => percentToPixel(w.x, w.y));

		// Waypoint anchors (draggable)
		const waypointAnchors = pixelWps.map((p, i) => ({
			x: p.x,
			y: p.y,
			radius: WAYPOINT_RADIUS,
			fill: WAYPOINT_FILL,
			stroke: WAYPOINT_STROKE,
			strokeWidth: 2,
			index: i,
		}));

		// Midpoint anchors on every segment of the full path (including pin→wp and wp→pin)
		const midpointAnchors = [];
		for (let i = 0; i < pixelPath.length - 1; i++) {
			const a = pixelPath[i];
			const b = pixelPath[i + 1];
			midpointAnchors.push({
				x: (a.x + b.x) / 2,
				y: (a.y + b.y) / 2,
				radius: MIDPOINT_RADIUS,
				fill: MIDPOINT_FILL,
				stroke: MIDPOINT_STROKE,
				strokeWidth: 1,
				segmentIndex: i,
			});
		}

		return { waypointAnchors, midpointAnchors };
	});

	// --- Auto-exit on selection change ---

	watch([selectedType, selectedId], ([type, id]) => {
		if (!isEditing.value) {
			return;
		}
		if (type !== "connection" || id !== editingConnectionId.value) {
			stopEditing();
		}
	});

	// --- Escape to exit ---

	function onKeyDown(e) {
		if (e.key === "Escape" && isEditing.value) {
			e.preventDefault();
			stopEditing();
		}
	}

	onMounted(() => window.addEventListener("keydown", onKeyDown));
	onUnmounted(() => window.removeEventListener("keydown", onKeyDown));

	return {
		editingConnectionId,
		editingWaypoints,
		isEditing,
		startEditing,
		stopEditing,
		onWaypointDragMove,
		onWaypointDragEnd,
		onWaypointClick,
		insertWaypoint,
		waypointEditorConfigs,
	};
}
