import { ref } from "vue";
import { useLive } from "@/vue/composables/useLive.js";

/**
 * Composable for inline text editing of annotations via an HTML textarea overlay.
 * Konva canvas has no native text editing, so we overlay a textarea positioned
 * exactly on top of the annotation text.
 *
 * Uses optimistic local text overrides to avoid flash when the textarea closes
 * (old text briefly visible before server responds with new text).
 */
export function useAnnotationEditing({ containerRef, stageConfig }) {
	const live = useLive();
	const editingAnnotationId = ref(null);
	// Optimistic text overrides: { [annotationId]: "new text" }
	const textOverrides = ref({});

	/**
	 * Start inline text editing by overlaying a textarea.
	 * @param {Object} annConfig - The annotation config from useAnnotations
	 */
	function startEditing(annConfig) {
		if (
			!annConfig ||
			annConfig.locked ||
			editingAnnotationId.value === annConfig.id
		) {
			return;
		}

		editingAnnotationId.value = annConfig.id;

		const scale = stageConfig.scaleX;
		const screenX = (annConfig.x + annConfig.padLeft) * scale + stageConfig.x;
		const screenY = (annConfig.y + annConfig.padTop) * scale + stageConfig.y;
		const screenW = annConfig.textWidth * scale;
		const screenH = (annConfig.height - annConfig.padTop - 4) * scale;
		const fontSize = annConfig.fontSize * scale;

		const textarea = document.createElement("textarea");
		textarea.value = annConfig.text || "";
		textarea.style.cssText = `
			position: absolute;
			left: ${screenX}px;
			top: ${screenY}px;
			width: ${screenW}px;
			min-height: ${screenH}px;
			font-size: ${fontSize}px;
			font-weight: 600;
			font-family: system-ui, sans-serif;
			line-height: 1.3;
			color: #111827;
			background: transparent;
			border: none;
			outline: none;
			resize: none;
			overflow: hidden;
			padding: 0;
			margin: 0;
			z-index: 1100;
		`;

		containerRef.value.appendChild(textarea);
		textarea.focus();
		textarea.select();

		const annId = annConfig.id;

		const finishEditing = () => {
			const newText = textarea.value;
			const originalText = annConfig.text || "";
			// Set optimistic override BEFORE removing textarea so v-text shows new text immediately
			textOverrides.value = { ...textOverrides.value, [annId]: newText };
			textarea.remove();
			editingAnnotationId.value = null;
			live.pushEvent(
				"update_annotation",
				{ id: String(annId), field: "text", value: newText },
				(reply) => {
					// Clear override on success (server prop will match)
					// Revert on error so UI stays in sync with DB
					if (reply?.error) {
						textOverrides.value = {
							...textOverrides.value,
							[annId]: originalText,
						};
					} else {
						clearOverride(annId);
					}
				},
			);
		};

		const onBlur = () => finishEditing();

		const onKeyDown = (e) => {
			if (e.key === "Enter" && !e.shiftKey) {
				e.preventDefault();
				textarea.removeEventListener("blur", onBlur);
				finishEditing();
			}
			if (e.key === "Escape") {
				textarea.removeEventListener("blur", onBlur);
				textarea.remove();
				editingAnnotationId.value = null;
			}
		};

		textarea.addEventListener("blur", onBlur);
		textarea.addEventListener("keydown", onKeyDown);
	}

	function isEditingAnnotation(id) {
		return editingAnnotationId.value === id;
	}

	function getDisplayText(id, originalText) {
		const override = textOverrides.value[id];
		if (override !== undefined) {
			return override;
		}
		return originalText;
	}

	// Clear override once the server-pushed prop matches (no longer needed)
	function clearOverride(id) {
		if (textOverrides.value[id] !== undefined) {
			const next = { ...textOverrides.value };
			delete next[id];
			textOverrides.value = next;
		}
	}

	return {
		editingAnnotationId,
		startEditing,
		isEditingAnnotation,
		getDisplayText,
		clearOverride,
	};
}
