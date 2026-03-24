import { computed, onMounted, onUnmounted, ref } from "vue";
import { useLive } from "@/vue/composables/useLive";

const SOURCE_HIGHLIGHT_COLOR = "#6366f1";
const TARGET_HIGHLIGHT_COLOR = "#22c55e";
const PREVIEW_STROKE = "#6366f1";

/**
 * Composable for drawing connections between pins.
 *
 * State machine: idle → source_selected → (click target pin) → create_connection.
 * While source is selected, a dashed preview line follows the cursor.
 * Escape or empty canvas click cancels.
 */
export function useConnectionDrawing({
	stageRef,
	stageConfig,
	percentToPixel,
	activeTool,
	editMode,
	canEdit,
	pins,
}) {
	const live = useLive();

	const sourcePinId = ref(null);
	const cursorPos = ref(null);
	const hoveredPinId = ref(null);

	const isDrawingConnection = computed(
		() => activeTool.value === "connector" && sourcePinId.value !== null,
	);

	/**
	 * Handle click on a pin while connector tool is active.
	 * Returns true if handled.
	 */
	function handlePinClickForConnection(pinId, e) {
		if (activeTool.value !== "connector") return false;
		if (!editMode.value || !canEdit.value) return false;
		if (e) e.cancelBubble = true;

		if (sourcePinId.value === null) {
			// First click: select source
			sourcePinId.value = pinId;
			return true;
		}

		// Second click: select target
		if (pinId === sourcePinId.value) return true; // can't connect to self

		live.pushEvent("create_connection", {
			from_pin_id: String(sourcePinId.value),
			to_pin_id: String(pinId),
		});

		sourcePinId.value = null;
		cursorPos.value = null;
		hoveredPinId.value = null;
		return true;
	}

	/**
	 * Handle stage click while drawing — cancels on empty canvas.
	 * Returns true if handled (consumed the click).
	 */
	function handleStageClickForConnection(e) {
		if (activeTool.value !== "connector") return false;
		if (!sourcePinId.value) return false;

		// Click on empty canvas = cancel
		const stage = e.target.getStage();
		if (e.target === stage) {
			cancel();
			return true;
		}
		return false;
	}

	function cancel() {
		sourcePinId.value = null;
		cursorPos.value = null;
		hoveredPinId.value = null;
	}

	// Track cursor + hovered pin via proximity (avoids per-pin mouseenter/mouseleave events)
	const PIN_HOVER_THRESHOLD = 25;

	function onMouseMove() {
		if (!isDrawingConnection.value) return;
		const stage = stageRef.value?.getStage?.();
		if (!stage) return;
		const pointer = stage.getPointerPosition();
		if (!pointer) return;
		const worldX = (pointer.x - stageConfig.x) / stageConfig.scaleX;
		const worldY = (pointer.y - stageConfig.y) / stageConfig.scaleY;
		cursorPos.value = { x: worldX, y: worldY };

		// Find closest pin to cursor for target highlight
		let closest = null;
		let closestDist = PIN_HOVER_THRESHOLD;
		for (const pin of pins.value) {
			if (pin.id === sourcePinId.value) continue;
			const p = percentToPixel(pin.positionX, pin.positionY);
			const dx = worldX - p.x;
			const dy = worldY - p.y;
			const dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < closestDist) {
				closest = pin.id;
				closestDist = dist;
			}
		}
		hoveredPinId.value = closest;
	}

	// Escape cancels
	function onKeyDown(e) {
		if (e.key === "Escape" && isDrawingConnection.value) {
			e.preventDefault();
			cancel();
		}
	}

	onMounted(() => window.addEventListener("keydown", onKeyDown));
	onUnmounted(() => window.removeEventListener("keydown", onKeyDown));

	// Preview line from source pin center to cursor
	const previewLine = computed(() => {
		if (!isDrawingConnection.value || !cursorPos.value) return null;
		const sourcePin = pins.value.find((p) => p.id === sourcePinId.value);
		if (!sourcePin) return null;
		const from = percentToPixel(sourcePin.positionX, sourcePin.positionY);
		return [from.x, from.y, cursorPos.value.x, cursorPos.value.y];
	});

	return {
		sourcePinId,
		hoveredPinId,
		isDrawingConnection,
		handlePinClickForConnection,
		handleStageClickForConnection,
		onMouseMove,
		previewLine,
		SOURCE_HIGHLIGHT_COLOR,
		TARGET_HIGHLIGHT_COLOR,
		PREVIEW_STROKE,
	};
}
