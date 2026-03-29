import { computed, onMounted, onUnmounted, reactive, ref, watch } from "vue";

const MIN_SCALE = 0.125;
const MAX_SCALE = 32;
const GRID_DIVISIONS = 10;
const FIT_PADDING = 0.95;

/**
 * Composable managing the Konva stage lifecycle: sizing, background, grid,
 * pan/zoom, cursor style, and coordinate conversion.
 */
export function useKonvaStage({
	containerRef,
	sceneData,
	activeTool,
	editMode: _editMode,
}) {
	const stageRef = ref(null);
	const bgImage = ref(null);

	const stageConfig = reactive({
		width: 800,
		height: 600,
		draggable: false,
		scaleX: 1,
		scaleY: 1,
		x: 0,
		y: 0,
	});

	// ---------- Container sizing ----------

	let resizeObserver = null;

	onMounted(() => {
		if (!containerRef.value) {
			return;
		}
		const rect = containerRef.value.getBoundingClientRect();
		stageConfig.width = rect.width;
		stageConfig.height = rect.height;

		resizeObserver = new ResizeObserver((entries) => {
			for (const entry of entries) {
				stageConfig.width = entry.contentRect.width;
				stageConfig.height = entry.contentRect.height;
			}
		});
		resizeObserver.observe(containerRef.value);
	});

	onUnmounted(() => {
		resizeObserver?.disconnect();
	});

	// ---------- Background image ----------

	function loadImage(url) {
		if (!url) {
			bgImage.value = null;
			return;
		}
		const img = new Image();
		img.onload = () => {
			bgImage.value = img;
		};
		img.onerror = () => {
			bgImage.value = null;
		};
		img.crossOrigin = "anonymous";
		img.src = url;
	}

	// Watch for background URL changes
	watch(
		() => sceneData.value?.backgroundUrl,
		(url) => loadImage(url),
		{ immediate: true },
	);

	const backgroundConfig = computed(() => {
		const img = bgImage.value;
		if (!img) {
			return null;
		}

		const imgW = img.naturalWidth || img.width;
		const imgH = img.naturalHeight || img.height;
		if (!imgW || !imgH) {
			return null;
		}

		const scaleX = stageConfig.width / imgW;
		const scaleY = stageConfig.height / imgH;
		const scale = Math.min(scaleX, scaleY) * FIT_PADDING;

		const w = imgW * scale;
		const h = imgH * scale;

		return {
			image: img,
			x: (stageConfig.width - w) / 2,
			y: (stageConfig.height - h) / 2,
			width: w,
			height: h,
		};
	});

	// ---------- Grid placeholder ----------

	function getThemeColor(cssVar, fallback) {
		if (typeof document === "undefined") {
			return fallback;
		}
		const raw = getComputedStyle(document.documentElement)
			.getPropertyValue(cssVar)
			.trim();
		return raw || fallback;
	}

	const gridRectConfig = computed(() => {
		const w = stageConfig.width * FIT_PADDING;
		const h = stageConfig.height * FIT_PADDING;
		return {
			x: (stageConfig.width - w) / 2,
			y: (stageConfig.height - h) / 2,
			width: w,
			height: h,
			fill: "transparent",
			stroke: getThemeColor("--color-border", "#374151"),
			strokeWidth: 1,
		};
	});

	const gridLines = computed(() => {
		const rect = gridRectConfig.value;
		const lines = [];
		const color = getThemeColor("--color-border", "#374151");

		// Horizontal lines
		for (let i = 1; i < GRID_DIVISIONS; i++) {
			const y = rect.y + (rect.height / GRID_DIVISIONS) * i;
			lines.push({
				points: [rect.x, y, rect.x + rect.width, y],
				stroke: color,
				strokeWidth: 0.5,
				opacity: 0.5,
			});
		}

		// Vertical lines
		for (let i = 1; i < GRID_DIVISIONS; i++) {
			const x = rect.x + (rect.width / GRID_DIVISIONS) * i;
			lines.push({
				points: [x, rect.y, x, rect.y + rect.height],
				stroke: color,
				strokeWidth: 0.5,
				opacity: 0.5,
			});
		}

		return lines;
	});

	// ---------- Pan ----------

	watch(
		activeTool,
		(tool) => {
			stageConfig.draggable = tool === "pan";
		},
		{ immediate: true },
	);

	// ---------- Wheel zoom ----------

	function handleWheel(e) {
		const evt = e.evt;
		evt.preventDefault();

		const stage = stageRef.value?.getStage();
		if (!stage) {
			return;
		}

		const oldScale = stageConfig.scaleX;
		const pointer = stage.getPointerPosition();
		if (!pointer) {
			return;
		}

		const direction = evt.deltaY > 0 ? -1 : 1;
		const factor = 1.1;
		let newScale = direction > 0 ? oldScale * factor : oldScale / factor;
		newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, newScale));

		const mousePointTo = {
			x: (pointer.x - stageConfig.x) / oldScale,
			y: (pointer.y - stageConfig.y) / oldScale,
		};

		stageConfig.scaleX = newScale;
		stageConfig.scaleY = newScale;
		stageConfig.x = pointer.x - mousePointTo.x * newScale;
		stageConfig.y = pointer.y - mousePointTo.y * newScale;
	}

	// ---------- Fit to view ----------

	function fitToView() {
		stageConfig.scaleX = 1;
		stageConfig.scaleY = 1;
		stageConfig.x = 0;
		stageConfig.y = 0;
	}

	// ---------- Cursor ----------

	const creationTools = new Set(["pin", "zone", "connection", "annotation"]);

	const cursorStyle = computed(() => {
		const tool = activeTool.value;
		if (tool === "pan") {
			return "grab";
		}
		if (creationTools.has(tool)) {
			return "crosshair";
		}
		return "default";
	});

	// ---------- Coordinate conversion ----------

	const canvasBounds = computed(() => {
		const bg = backgroundConfig.value;
		if (bg) {
			return { w: bg.width, h: bg.height, ox: bg.x, oy: bg.y };
		}
		const grid = gridRectConfig.value;
		return { w: grid.width, h: grid.height, ox: grid.x, oy: grid.y };
	});

	function percentToPixel(pctX, pctY) {
		const { w, h, ox, oy } = canvasBounds.value;
		return { x: ox + (pctX / 100) * w, y: oy + (pctY / 100) * h };
	}

	function pixelToPercent(pixelX, pixelY) {
		const { w, h, ox, oy } = canvasBounds.value;
		return { x: ((pixelX - ox) / w) * 100, y: ((pixelY - oy) / h) * 100 };
	}

	function stagePointerToWorld(stage) {
		const pointer = stage.getPointerPosition();
		if (!pointer) {
			return null;
		}
		return {
			x: (pointer.x - stageConfig.x) / stageConfig.scaleX,
			y: (pointer.y - stageConfig.y) / stageConfig.scaleY,
		};
	}

	return {
		stageConfig,
		stageRef,
		backgroundConfig,
		gridRectConfig,
		gridLines,
		cursorStyle,
		handleWheel,
		fitToView,
		canvasBounds,
		percentToPixel,
		pixelToPercent,
		stagePointerToWorld,
	};
}
