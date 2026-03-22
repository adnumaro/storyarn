<script setup>
/**
 * Shared sidebar panel — floating surface panel with JS-driven animation.
 *
 * Used by TreePanel (left) and FormulaPanel (right).
 * Mirrors the v1 hook animation: slide + fade, 280ms in / 180ms out.
 *
 * Desktop (≥ md): fixed w-64, positioned left-3 or right-3, JS animation.
 * Mobile (< md): full-width overlay (left-3 right-3), above toolbars,
 *   CSS transition for slide in/out.
 *
 * Props:
 *   side: "left" | "right"
 *   open: boolean
 *
 * Slots:
 *   header — rendered inside the header bar
 *   default — scrollable content area
 *   footer — optional footer bar with border-top
 */
import { ref, watch, nextTick, onMounted } from "vue";
import { onClickOutside } from "@vueuse/core";

const props = defineProps({
	side: {
		type: String,
		default: "left",
		validator: (v) => ["left", "right"].includes(v),
	},
	open: { type: Boolean, default: false },
});

const emit = defineEmits(["close"]);

const panelRef = ref(null);

// Close on click outside (right sidebar only)
onClickOutside(panelRef, () => {
	if (props.side === "right" && props.open) {
		emit("close");
	}
});

// ── Animation constants (matching v1 TreePanel hook) ──
const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const EASING = "ease-out";

function slideOffset() {
	return props.side === "left" ? "-20px" : "20px";
}

function animateIn() {
	const el = panelRef.value;
	if (!el) return;

	el.style.opacity = 0;
	el.style.transform = `translateX(${slideOffset()})`;
	el.style.transition = "";
	el.style.pointerEvents = "auto";

	requestAnimationFrame(() => {
		requestAnimationFrame(() => {
			el.style.transition = `transform ${OPEN_DURATION}ms ${EASING}, opacity ${OPEN_DURATION}ms ${EASING}`;
			el.style.opacity = 1;
			el.style.transform = "translateX(0)";

			setTimeout(() => {
				el.style.transition = "";
				el.style.opacity = "";
				el.style.transform = "";
			}, OPEN_DURATION);
		});
	});
}

function animateOut() {
	const el = panelRef.value;
	if (!el) return;

	el.style.opacity = 1;
	el.style.transform = "translateX(0)";

	requestAnimationFrame(() => {
		el.style.transition = `transform ${CLOSE_DURATION}ms ${EASING}, opacity ${CLOSE_DURATION}ms ${EASING}`;
		el.style.opacity = 0;
		el.style.transform = `translateX(${slideOffset()})`;

		setTimeout(() => {
			el.style.transition = "";
			el.style.opacity = 0;
			el.style.transform = `translateX(${slideOffset()})`;
			el.style.pointerEvents = "none";
		}, CLOSE_DURATION);
	});
}

// Set initial state on mount
onMounted(() => {
	const el = panelRef.value;
	if (!el) return;

	if (props.open) {
		el.style.opacity = 1;
		el.style.pointerEvents = "auto";
	} else {
		el.style.opacity = 0;
		el.style.transform = `translateX(${slideOffset()})`;
		el.style.pointerEvents = "none";
	}
});

// Animate on open/close changes
watch(
	() => props.open,
	(nowOpen, wasOpen) => {
		if (nowOpen === wasOpen) return;
		nextTick(() => {
			nowOpen ? animateIn() : animateOut();
		});
	},
);

</script>

<template>
	<div
		ref="panelRef"
		:class="[
			'fixed top-19 bottom-3 left-3 right-3 z-40 flex flex-col v2-surface-panel overflow-hidden',
			// Desktop: fixed width, side-positioned
			'md:w-64',
			side === 'right' ? 'md:left-auto md:!right-3' : '',
		]"
	>
		<!-- Header -->
		<div
			v-if="$slots.header"
			class="border-b border-border shrink-0"
		>
			<slot name="header" />
		</div>

		<!-- Scrollable content -->
		<div class="flex-1 overflow-y-auto p-2">
			<slot />
		</div>

		<!-- Footer (desktop only) -->
		<div
			v-if="$slots.footer"
			class="hidden md:flex items-center justify-end gap-1 px-2 py-1.5 border-t border-border"
		>
			<slot name="footer" />
		</div>
	</div>
</template>
