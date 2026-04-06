import { onMounted, onUnmounted, type Ref } from "vue";

interface FlowResponse {
  id: number | string;
  valid: boolean;
}

interface FlowSlide {
  responses: FlowResponse[] | null;
}

interface UseExplorationKeyboardOpts {
  flowMode: Ref<boolean>;
  activeFlowSlide: Ref<FlowSlide | null>;
  pushEvent: (event: string, payload: { id: number | string }) => void;
}

/**
 * Client-side keyboard shortcuts for exploration mode.
 * Complements the server-side handle_keydown for instant visual feedback.
 *
 * Server handles: Escape chain, flow continue/back, response selection.
 * This composable adds: number key visual feedback on response buttons.
 */
export function useExplorationKeyboard({ flowMode, activeFlowSlide, pushEvent }: UseExplorationKeyboardOpts) {
  function onKeyDown(e: KeyboardEvent): void {
    // Only handle flow-related keys when flow is active
    if (!flowMode.value || !activeFlowSlide.value) {
      return;
    }

    const slide = activeFlowSlide.value;
    const responses = (slide.responses || []).filter((r) => r.valid);

    // Number keys 1-9 -> select response (instant, don't wait for server roundtrip)
    if (responses.length > 0 && /^[1-9]$/.test(e.key)) {
      const idx = parseInt(e.key, 10) - 1;
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
