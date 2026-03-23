import { computed } from "vue";
import {
	DEFAULT_PIN_COLOR,
	PIN_SIZES,
	renderInitialsCanvas,
	renderLockBadge,
	renderPinIcon,
} from "../lib/pin-icons";
import { useImageLoader } from "./useImageLoader";

/**
 * Composable for computing pin render configs from raw pin data.
 * Handles layer filtering, coordinate conversion, image resolution, and lock state.
 *
 * @param {Object} opts
 * @param {import('vue').Ref<Array>} opts.pins
 * @param {import('vue').Ref<Array>} opts.layers
 * @param {import('vue').Ref<Object>} opts.entityLocks
 * @param {import('vue').Ref<number|string>} opts.currentUserId
 * @param {Function} opts.percentToPixel - (pctX, pctY) => { x, y }
 */
export function usePins({
	pins,
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

	const visiblePins = computed(() =>
		pins.value.filter((pin) => {
			// hidden field is for exploration mode, not editor — don't filter by it
			if (pin.layerId && hiddenLayerIds.value.has(pin.layerId)) return false;
			return true;
		}),
	);

	// Collect URLs for pins that need async image loading
	const pinImageUrls = computed(() => {
		const map = new Map();
		for (const pin of visiblePins.value) {
			const url = pin.iconAssetUrl || pin.sheetAvatarUrl || null;
			if (url) map.set(pin.id, url);
		}
		return map;
	});

	const { images: loadedImages } = useImageLoader(pinImageUrls);

	const pinConfigs = computed(() =>
		visiblePins.value
			.slice()
			.sort((a, b) => (a.position || 0) - (b.position || 0))
			.map((pin) => {
				const pos = percentToPixel(pin.positionX, pin.positionY);
				const sizeKey = pin.size || "md";
				const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;
				const color = pin.color || DEFAULT_PIN_COLOR;
				const opacity = pin.opacity ?? 1;
				const radius = dims.diameter / 2;

				// Lock state
				const lock = entityLocks.value[String(pin.id)];
				const isLockedByOther =
					!!lock && String(lock.userId) !== String(currentUserId.value);

				// Determine render mode: image > initials > icon
				const loadedImg = loadedImages.value[pin.id] || null;
				let image = null;
				let iconCanvas = null;
				let initialsCanvas = null;

				if (loadedImg) {
					image = loadedImg;
				} else if (pin.sheetId && !pin.sheetAvatarUrl) {
					const initials = (pin.label || "?").slice(0, 2).toUpperCase();
					initialsCanvas = renderInitialsCanvas(
						initials,
						color,
						sizeKey,
						opacity,
					);
				} else {
					iconCanvas = renderPinIcon(pin.pinType, color, sizeKey, opacity);
				}

				return {
					id: pin.id,
					x: pos.x,
					y: pos.y,
					radius,
					diameter: dims.diameter,
					color,
					opacity,
					image,
					iconCanvas,
					initialsCanvas,
					label: pin.label,
					isLockedByOther,
					lockBadge: isLockedByOther ? renderLockBadge() : null,
				};
			}),
	);

	return { pinConfigs };
}
