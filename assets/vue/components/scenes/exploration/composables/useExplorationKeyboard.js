import { onMounted, onUnmounted } from "vue";

/**
 * Client-side keyboard shortcuts for exploration mode.
 * Complements the server-side handle_keydown for instant visual feedback.
 *
 * Server handles: Escape chain, flow continue/back, response selection.
 * This composable adds: number key visual feedback on response buttons.
 *
 * @param {Object} opts
 * @param {import('vue').Ref<boolean>} opts.flowMode
 * @param {import('vue').Ref<Object|null>} opts.activeFlowSlide
 * @param {Function} opts.pushEvent - live.pushEvent
 */
export function useExplorationKeyboard({
	flowMode,
	activeFlowSlide,
	pushEvent,
}) {
	function onKeyDown(e) {
		// Only handle flow-related keys when flow is active
		if (!flowMode.value || !activeFlowSlide.value) return;

		const slide = activeFlowSlide.value;
		const responses = (slide.responses || []).filter((r) => r.valid);

		// Number keys 1-9 → select response (instant, don't wait for server roundtrip)
		if (responses.length > 0 && /^[1-9]$/.test(e.key)) {
			const idx = parseInt(e.key) - 1;
			const resp = responses[idx];
			if (resp) {
				e.preventDefault();
				pushEvent("choose_response", { id: resp.id });
			}
		}
	}

	onMounted(() => window.addEventListener("keydown", onKeyDown));
	onUnmounted(() => window.removeEventListener("keydown", onKeyDown));
}
