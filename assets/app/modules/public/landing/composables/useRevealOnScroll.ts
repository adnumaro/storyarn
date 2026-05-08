import { onMounted, onUnmounted, ref } from "vue";
import type { Ref } from "vue";

interface RevealOnScrollOptions {
  threshold?: number;
  rootMargin?: string;
}

interface RevealOnScrollReturn {
  elementRef: Ref<HTMLElement | null>;
  isRevealed: Ref<boolean>;
}

/**
 * Composable that triggers a reveal animation when the element enters the viewport.
 * Uses IntersectionObserver with a 15% threshold.
 */
export function useRevealOnScroll(options: RevealOnScrollOptions = {}): RevealOnScrollReturn {
  const { threshold = 0.15, rootMargin = "0px 0px -80px 0px" } = options;
  const elementRef = ref<HTMLElement | null>(null);
  const isRevealed = ref(false);
  let observer: IntersectionObserver | null = null;

  onMounted(() => {
    if (!elementRef.value) return;

    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            isRevealed.value = true;
            observer!.unobserve(entry.target);
          }
        }
      },
      { threshold, rootMargin },
    );

    observer.observe(elementRef.value);
  });

  onUnmounted(() => {
    observer?.disconnect();
  });

  return { elementRef, isRevealed };
}
