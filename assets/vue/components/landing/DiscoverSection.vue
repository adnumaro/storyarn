<script setup>
import { ref, computed, onMounted, onUnmounted, defineAsyncComponent } from "vue";
import { useRevealOnScroll } from "./composables/useRevealOnScroll";

const DiscoverMonitor = defineAsyncComponent(() => import("./DiscoverMonitor.vue"));

const props = defineProps({
	translations: { type: Object, required: true },
});

const activeTab = ref(0);
const sectionRef = ref(null);
const { elementRef: revealRef, isRevealed } = useRevealOnScroll({ threshold: 0.1 });

const TOTAL_STEPS = 3;
let scrollLocked = false;

const features = computed(() => [
	{
		id: "sheets",
		label: props.translations.discover_sheets,
		title: props.translations.discover_sheets_title,
		desc: props.translations.discover_sheets_desc,
		items: props.translations.discover_sheets_items,
		textPosition: "left",
	},
	{
		id: "flows",
		label: props.translations.discover_flows,
		title: props.translations.discover_flows_title,
		desc: props.translations.discover_flows_desc,
		items: props.translations.discover_flows_items,
		textPosition: "right",
	},
	{
		id: "scenes",
		label: props.translations.discover_scenes,
		title: props.translations.discover_scenes_title,
		desc: props.translations.discover_scenes_desc,
		items: props.translations.discover_scenes_items,
		textPosition: "center",
	},
]);

function onScroll() {
	if (scrollLocked) return;

	const section = sectionRef.value;
	if (!section) return;

	const rect = section.getBoundingClientRect();
	const scrolled = -rect.top;
	const scrollableHeight = section.offsetHeight - window.innerHeight;

	if (scrolled <= 0 || scrollableHeight <= 0) {
		activeTab.value = 0;
		return;
	}

	if (scrolled >= scrollableHeight) {
		activeTab.value = TOTAL_STEPS - 1;
		return;
	}

	const progress = scrolled / scrollableHeight;
	activeTab.value = Math.min(Math.floor(progress * TOTAL_STEPS), TOTAL_STEPS - 1);
}

function scrollToTab(index) {
	const section = sectionRef.value;
	if (!section) return;

	activeTab.value = index;
	scrollLocked = true;

	const scrollableHeight = section.offsetHeight - window.innerHeight;
	// Scroll to the center of this step's zone so onScroll agrees when lock releases
	const targetProgress = (index + 0.5) / TOTAL_STEPS;
	const targetScroll = section.offsetTop + targetProgress * scrollableHeight;

	window.scrollTo({ top: targetScroll, behavior: "smooth" });

	setTimeout(() => {
		scrollLocked = false;
	}, 900);
}

onMounted(() => {
	window.addEventListener("scroll", onScroll, { passive: true });
	onScroll();
});

onUnmounted(() => {
	window.removeEventListener("scroll", onScroll);
});
</script>

<template>
	<section
		id="discover"
		ref="sectionRef"
		class="discover-section relative"
	>
		<div ref="revealRef" class="discover-sticky">
			<!-- 3D Monitor canvas backdrop -->
			<div class="discover-canvas-wrap">
				<DiscoverMonitor :active-step="activeTab" :is-visible="isRevealed" />
			</div>

			<!-- Content stage -->
			<div
				class="discover-stage"
				:class="{ 'is-entered': isRevealed }"
			>
				<!-- Text overlays -->
				<div
					v-for="(feature, i) in features"
					:key="feature.id"
					class="discover-text"
					:class="[
						`discover-text--${feature.textPosition}`,
						{ 'is-active': activeTab === i },
					]"
				>
					<span class="text-xs font-bold uppercase tracking-widest text-primary">
						{{ feature.label }}
					</span>
					<h3
						class="mt-2 text-[clamp(1.8rem,2.4vw,2.6rem)] font-bold leading-[0.98] tracking-[-0.04em] text-foreground"
					>
						{{ feature.title }}
					</h3>
					<p class="mt-3 max-w-[34rem] leading-relaxed text-muted-foreground/60">
						{{ feature.desc }}
					</p>
					<ul class="mt-4 grid gap-2.5">
						<li
							v-for="(item, j) in feature.items"
							:key="j"
							class="relative pl-4 leading-relaxed text-foreground/70"
						>
							<span
								class="absolute left-0 top-[0.7em] size-2 rounded-full bg-primary shadow-[0_0_16px_hsl(var(--primary)/0.36)]"
							/>
							{{ item }}
						</li>
					</ul>
				</div>

				<!-- Tab buttons (bottom) -->
				<div class="discover-indicators">
					<button
						v-for="(feature, i) in features"
						:key="feature.id"
						type="button"
						class="discover-tab"
						:class="{ 'is-active': activeTab === i }"
						@click="scrollToTab(i)"
					>
						{{ feature.label }}
					</button>
				</div>
			</div>
		</div>
	</section>
</template>

<style scoped>
.discover-section {
	/* 3 steps × 100svh each = total scrollable area */
	height: 300svh;
	background:
		radial-gradient(circle at 50% -15%, rgb(0 0 0 / 28%), transparent 24%),
		linear-gradient(
			180deg,
			hsl(var(--background)) 0%,
			hsl(var(--background)) 54%,
			hsl(var(--background)) 100%
		);
}

.discover-sticky {
	position: sticky;
	top: 0;
	height: 100svh;
	overflow: hidden;
}

.discover-canvas-wrap {
	position: absolute;
	inset: 0;
	z-index: 0;
	pointer-events: none;
}

.discover-canvas-wrap::after {
	content: "";
	position: absolute;
	inset: 0;
	z-index: 1;
	pointer-events: none;
	background: linear-gradient(
		to top,
		hsl(var(--background)) 10%,
		hsl(var(--background)) 20%,
		hsl(var(--background) / 0.85) 30%,
		hsl(var(--background) / 0.4) 40%,
		transparent 60%
	);
}

/* Stage fills the sticky container */
.discover-stage {
	position: absolute;
	inset: 0;
	z-index: 10;
	opacity: 0;
	transition:
		opacity 0.8s cubic-bezier(0.22, 1, 0.36, 1) 0.35s;
}

.discover-stage.is-entered {
	opacity: 1;
}

/* Text overlays */
.discover-text {
	position: absolute;
	z-index: 1;
	top: 50%;
	transform: translateY(-50%) translateX(0);
	max-width: 480px;
	display: grid;
	gap: 4px;
	opacity: 0;
	pointer-events: none;
	transition:
		opacity 420ms cubic-bezier(0.22, 1, 0.36, 1),
		transform 520ms cubic-bezier(0.22, 1, 0.36, 1);
}

.discover-text.is-active {
	opacity: 1;
	pointer-events: auto;
}

/* Position variants */
.discover-text--left {
	left: max(5%, calc((100% - 1280px) / 2));
	transform: translateY(-50%) translateX(-20px);
}
.discover-text--left.is-active {
	transform: translateY(-50%) translateX(0);
}

.discover-text--right {
	right: max(5%, calc((100% - 1280px) / 2));
	transform: translateY(-50%) translateX(20px);
}
.discover-text--right.is-active {
	transform: translateY(-50%) translateX(0);
}

.discover-text--center {
	top: auto;
	bottom: 12%;
	left: 50%;
	transform: translateX(-50%) translateY(20px);
	text-align: center;
	max-width: 600px;
}
.discover-text--center.is-active {
	transform: translateX(-50%) translateY(0);
}

/* Tab indicators — bottom center */
.discover-indicators {
	position: absolute;
	bottom: 5%;
	left: 50%;
	transform: translateX(-50%);
	z-index: 2;
	display: flex;
	gap: 10px;
}

.discover-tab {
	padding: 10px 14px;
	border-radius: 999px;
	border: 1px solid hsl(var(--foreground) / 0.1);
	background: hsl(var(--foreground) / 0.03);
	backdrop-filter: blur(12px);
	color: hsl(var(--foreground));
	opacity: 0.7;
	font-size: 0.88rem;
	font-weight: 700;
	letter-spacing: -0.02em;
	cursor: pointer;
	transition:
		background 180ms ease,
		border-color 180ms ease,
		opacity 180ms ease,
		transform 180ms ease;
}

.discover-tab:hover {
	transform: translateY(-1px);
	opacity: 0.9;
}

.discover-tab.is-active {
	opacity: 1;
	background: hsl(var(--primary));
	color: hsl(var(--primary-foreground));
	border-color: transparent;
}
</style>
