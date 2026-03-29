import { onMounted, onUnmounted, ref } from "vue";

/**
 * Composable that triggers a reveal animation when the element enters the viewport.
 * Uses IntersectionObserver with a 15% threshold.
 */
export function useRevealOnScroll(options = {}) {
	const { threshold = 0.15, rootMargin = "0px 0px -80px 0px" } = options;
	const elementRef = ref(null);
	const isRevealed = ref(false);
	let observer = null;

	onMounted(() => {
		if (!elementRef.value) return;

		observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) {
						isRevealed.value = true;
						observer.unobserve(entry.target);
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
