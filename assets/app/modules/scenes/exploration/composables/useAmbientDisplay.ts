import { onMounted, onUnmounted, ref } from "vue";

export interface BubbleData {
  pinId: number | string;
  text: string;
  speaker: string;
  duration: number;
}

export interface SubtitleData {
  text: string;
  speaker: string;
  duration: number;
}

interface ShowBubblePayload {
  pin_id: number | string;
  text: string;
  speaker: string;
  duration: number;
}

interface ShowSubtitlePayload {
  text: string;
  speaker: string;
  duration: number;
}

type HandleEventFn = (event: string, callback: (payload: Record<string, unknown>) => void) => void;

interface UseAmbientDisplayOpts {
  handleEvent: HandleEventFn;
}

/**
 * Manages ambient flow display: speech bubbles over pins and subtitles.
 * Listens for server push_events and manages auto-dismiss timers.
 */
export function useAmbientDisplay({ handleEvent }: UseAmbientDisplayOpts) {
  const bubble = ref<BubbleData | null>(null);
  const subtitle = ref<SubtitleData | null>(null);

  let bubbleTimer: ReturnType<typeof setTimeout> | null = null;
  let subtitleTimer: ReturnType<typeof setTimeout> | null = null;

  function clearBubble(): void {
    if (bubbleTimer) {
      clearTimeout(bubbleTimer);
      bubbleTimer = null;
    }
    bubble.value = null;
  }

  function clearSubtitle(): void {
    if (subtitleTimer) {
      clearTimeout(subtitleTimer);
      subtitleTimer = null;
    }
    subtitle.value = null;
  }

  function dismissAll(): void {
    clearBubble();
    clearSubtitle();
  }

  onMounted(() => {
    handleEvent("show_bubble", (payload) => {
      const { pin_id, text, speaker, duration } = payload as unknown as ShowBubblePayload;
      clearBubble();
      bubble.value = { pinId: pin_id, text, speaker, duration };
      bubbleTimer = setTimeout(clearBubble, duration);
    });

    handleEvent("show_subtitle", (payload) => {
      const { text, speaker, duration } = payload as unknown as ShowSubtitlePayload;
      clearSubtitle();
      subtitle.value = { text, speaker, duration };
      subtitleTimer = setTimeout(clearSubtitle, duration);
    });

    handleEvent("dismiss_ambient", () => dismissAll());
  });

  onUnmounted(dismissAll);

  return {
    bubble,
    subtitle,
  };
}
