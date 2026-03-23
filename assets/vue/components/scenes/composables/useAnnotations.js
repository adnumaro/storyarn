import { computed } from "vue";
import { renderLockBadge } from "../lib/pin-icons";

const FOLD_SIZE = 12;
const DEFAULT_COLOR = "#fbbf24";
const BG_OPACITY = 0.75;
const TEXT_COLOR = "#111827";

const ANNOTATION_SIZES = {
	sm: {
		width: 140,
		minHeight: 100,
		fontSize: 11,
		padLeft: 6,
		padRight: 18,
		padTop: 2,
		padBottom: 2,
	},
	md: {
		width: 200,
		minHeight: 150,
		fontSize: 14,
		padLeft: 8,
		padRight: 20,
		padTop: 4,
		padBottom: 4,
	},
	lg: {
		width: 260,
		minHeight: 190,
		fontSize: 16,
		padLeft: 10,
		padRight: 22,
		padTop: 5,
		padBottom: 5,
	},
};

/**
 * Composable for computing annotation render configs.
 * Annotations are sticky-note shapes with a folded corner.
 */
export function useAnnotations({
	annotations,
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

	const visibleAnnotations = computed(() =>
		annotations.value.filter(
			(ann) => !(ann.layerId && hiddenLayerIds.value.has(ann.layerId)),
		),
	);

	const annotationConfigs = computed(() =>
		visibleAnnotations.value
			.slice()
			.sort((a, b) => (a.position || 0) - (b.position || 0))
			.map((ann) => {
				const pos = percentToPixel(ann.positionX, ann.positionY);
				const sizeKey = ANNOTATION_SIZES[ann.fontSize] ? ann.fontSize : "md";
				const dims = ANNOTATION_SIZES[sizeKey];
				const color = ann.color || DEFAULT_COLOR;

				const w = dims.width;
				const h = dims.minHeight;
				const f = FOLD_SIZE;

				// Body polygon: rectangle with top-right corner clipped
				// (0,0) -> (W-F,0) -> (W,F) -> (W,H) -> (0,H)
				const bodyPoints = [0, 0, w - f, 0, w, f, w, h, 0, h];

				// Fold triangle: the darker corner piece
				// (W-F,0) -> (W,F) -> (W-F,F)
				const foldPoints = [w - f, 0, w, f, w - f, f];

				const lock = entityLocks.value[String(ann.id)];
				const isLockedByOther =
					!!lock && String(lock.userId) !== String(currentUserId.value);

				return {
					id: ann.id,
					x: pos.x,
					y: pos.y,
					text: ann.text || "",
					color,
					bgOpacity: BG_OPACITY,
					width: w,
					height: h,
					fontSize: dims.fontSize,
					padLeft: dims.padLeft,
					padRight: dims.padRight,
					padTop: dims.padTop,
					bodyPoints,
					foldPoints,
					textWidth: w - dims.padLeft - dims.padRight,
					isLockedByOther,
					lockBadge: isLockedByOther ? renderLockBadge() : null,
				};
			}),
	);

	return { annotationConfigs };
}
