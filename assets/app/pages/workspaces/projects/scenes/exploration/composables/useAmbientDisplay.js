import { onMounted, onUnmounted, ref } from "vue";

/**
 * Manages ambient flow display: speech bubbles over pins and subtitles.
 * Listens for server push_events and manages auto-dismiss timers.
 *
 * @param {Object} opts
 * @param {Function} opts.handleEvent - live.handleEvent
 */
export function useAmbientDisplay({ handleEvent }) {
  const bubble = ref(null); // { pinId, text, speaker, duration }
  const subtitle = ref(null); // { text, speaker, duration }

  let bubbleTimer = null;
  let subtitleTimer = null;

  function clearBubble() {
    if (bubbleTimer) {
      clearTimeout(bubbleTimer);
      bubbleTimer = null;
    }
    bubble.value = null;
  }

  function clearSubtitle() {
    if (subtitleTimer) {
      clearTimeout(subtitleTimer);
      subtitleTimer = null;
    }
    subtitle.value = null;
  }

  function dismissAll() {
    clearBubble();
    clearSubtitle();
  }

  onMounted(() => {
    handleEvent("show_bubble", ({ pin_id, text, speaker, duration }) => {
      clearBubble();
      bubble.value = { pinId: pin_id, text, speaker, duration };
      bubbleTimer = setTimeout(clearBubble, duration);
    });

    handleEvent("show_subtitle", ({ text, speaker, duration }) => {
      clearSubtitle();
      subtitle.value = { text, speaker, duration };
      subtitleTimer = setTimeout(clearSubtitle, duration);
    });

    handleEvent("dismiss_ambient", dismissAll);
  });

  onUnmounted(dismissAll);

  return {
    bubble,
    subtitle,
  };
}
