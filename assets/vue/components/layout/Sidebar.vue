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

import { onClickOutside } from "@vueuse/core";
import { nextTick, onMounted, ref, watch } from "vue";

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
let animationTimer = null;

function cancelPendingAnimation() {
	if (animationTimer) {
		clearTimeout(animationTimer);
		animationTimer = null;
	}
}

// Close on click outside (right sidebar only)
// Ignore clicks on floating toolbar and popover portals
onClickOutside(
	panelRef,
	() => {
		if (props.side === "right" && props.open) {
			emit("close");
		}
	},
	{ ignore: [".v2-surface-panel", "[data-radix-popper-content-wrapper]", "[data-reka-popper-content-wrapper]"] },
);

// ── Animation constants (matching v1 TreePanel hook) ──
const OPEN_DURATION = 280;
const CLOSE_DURATION = 180;
const EASING = "ease-out";

function slideOffset() {
	return props.side === "left" ? "-20px" : "20px";
}

function animateIn() {
	cancelPendingAnimation();
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

			animationTimer = setTimeout(() => {
				el.style.transition = "";
				el.style.opacity = "";
				el.style.transform = "";
				animationTimer = null;
			}, OPEN_DURATION);
		});
	});
}

function animateOut() {
	cancelPendingAnimation();
	const el = panelRef.value;
	if (!el) return;

	el.style.opacity = 1;
	el.style.transform = "translateX(0)";

	requestAnimationFrame(() => {
		el.style.transition = `transform ${CLOSE_DURATION}ms ${EASING}, opacity ${CLOSE_DURATION}ms ${EASING}`;
		el.style.opacity = 0;
		el.style.transform = `translateX(${slideOffset()})`;

		animationTimer = setTimeout(() => {
			el.style.transition = "";
			el.style.opacity = 0;
			el.style.transform = `translateX(${slideOffset()})`;
			el.style.pointerEvents = "none";
			animationTimer = null;
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
			'fixed top-19 bottom-3 left-3 right-3 flex flex-col v2-surface-panel overflow-hidden',
			side === 'right' ? 'z-[1010]' : 'z-40',
			side === 'right' ? 'right-sidebar' : 'left-sidebar',
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
		<div :class="['flex-1 overflow-y-auto py-2', side === 'right' ? 'px-5' : 'px-2']">
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
