<script setup>
import { ref } from "vue";
import { Play, X } from "lucide-vue-next";
import PortalRing from "./PortalRing.vue";

const props = defineProps({
	translations: { type: Object, required: true },
});

const portalRef = ref(null);
const portalFrameRef = ref(null);
const videoRef = ref(null);
const isFullscreen = ref(false);

function openFullscreen() {
	isFullscreen.value = true;
	const video = videoRef.value;
	if (video) {
		video.muted = false;
		video.currentTime = 0;
		video.play();
	}
	// Animate portal shader zoom
	portalRef.value?.setScale(12);
	portalRef.value?.setIntensity(3);
}

function closeFullscreen() {
	isFullscreen.value = false;
	const video = videoRef.value;
	if (video) {
		video.muted = true;
	}
	portalRef.value?.setScale(1);
	portalRef.value?.setIntensity(1);
}

function onKeydown(e) {
	if (e.key === "Escape" && isFullscreen.value) {
		closeFullscreen();
	}
}
</script>

<template>
	<section
		id="hero-section"
		class="hero-section relative isolate min-h-svh overflow-hidden"
		@keydown="onKeydown"
		tabindex="-1"
	>
		<!-- Portal energy ring (WebGL) -->
		<PortalRing ref="portalRef" :portal-frame-ref="portalFrameRef" />

		<!-- Radial glow backdrop -->
		<div class="hero-backdrop" aria-hidden="true" />

		<!-- Video portal trigger -->
		<button
			class="portal-trigger"
			type="button"
			:aria-label="translations.watch_demo"
			@click="openFullscreen"
		>
			<span class="portal-badge">
				<Play class="size-4" />
				<span>{{ translations.watch_demo }}</span>
			</span>

      <div ref="portalFrameRef" class="portal-video-frame">
				<video
					ref="videoRef"
					class="portal-video"
					autoplay
					muted
					loop
					playsinline
					:src="'/videos/demo.mp4'"
				/>
			</div>
		</button>

		<!-- Hero content -->
		<div
			class="pointer-events-none relative z-10 mx-auto flex min-h-svh w-full max-w-[1180px] flex-col items-center justify-center px-6 pb-20 pt-28 text-center sm:px-8 sm:pb-24 sm:pt-32 lg:pt-40"
			style="transform: translateY(-10%)"
		>
			<div class="pointer-events-auto">
				<!-- Eyebrow badge -->
				<div
					class="inline-flex items-center gap-2 rounded-full border border-primary/20 bg-primary/10 px-3 py-1.5 text-[0.65rem] uppercase tracking-widest text-primary sm:gap-2.5 sm:px-4 sm:py-2.5 sm:text-xs"
				>
					<span class="size-2 animate-pulse rounded-full bg-primary shadow-[0_0_20px_var(--color-primary)] sm:size-2.5" />
					{{ translations.private_beta }}
				</div>

				<div class="mt-5 sm:mt-7">
					<h1
						class="text-[clamp(2.6rem,7.2vw,5.8rem)] font-bold leading-[0.88] tracking-[-0.07em] text-foreground"
					>
						{{ translations.hero_title_1 }}
						<span class="mt-1.5 block text-[1em]" style="font-family: var(--font-brand, inherit)">
							{{ translations.hero_title_2 }}
						</span>
					</h1>
				</div>

				<p
					class="mx-auto mt-6 max-w-184 text-sm leading-relaxed text-muted-foreground sm:text-lg"
				>
					{{ translations.hero_subtitle }}
				</p>

				<div class="mt-8 flex flex-wrap justify-center gap-3.5">
					<a
						href="#discover"
						class="inline-flex items-center justify-center rounded-md bg-primary px-6 py-3 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
					>
						{{ translations.explore_storyarn }}
					</a>
					<a
						href="#workflow"
						class="inline-flex items-center justify-center rounded-md border border-border px-6 py-3 text-sm text-foreground transition-colors hover:bg-accent"
					>
						{{ translations.see_workflow }}
					</a>
				</div>
			</div>
		</div>

		<!-- Fullscreen video overlay -->
		<Teleport to="body">
			<div
				v-if="isFullscreen"
				class="fixed inset-0 z-100 flex items-center justify-center bg-background/94 backdrop-blur-sm"
				@click.self="closeFullscreen"
			>
				<button
					class="absolute right-6 top-6 z-10 flex size-11 items-center justify-center rounded-full border border-border/30 bg-muted/30 text-foreground transition-colors hover:bg-muted/50"
					:aria-label="translations.close_video"
					@click="closeFullscreen"
				>
					<X class="size-5" />
				</button>
				<video
					class="max-h-[85vh] w-[92vw] max-w-350 rounded-xl object-contain"
					autoplay
					controls
					:src="'/videos/demo.mp4'"
				/>
			</div>
		</Teleport>
	</section>
</template>

<style scoped>
.hero-section {
	background:
		radial-gradient(circle at 50% 18%, hsl(var(--primary) / 0.44), transparent 28%),
		linear-gradient(
			180deg,
			hsl(var(--primary) / 0.18) 0%,
			hsl(var(--primary) / 0.41) 46%,
			hsl(var(--primary) / 0.65) 100%
		);
}

.hero-section::before {
	content: "";
	position: absolute;
	inset: 0;
	z-index: 1;
	pointer-events: none;
	background:
		linear-gradient(
			180deg,
			hsl(var(--background) / 0.18) 0%,
			hsl(var(--background) / 0.04) 28%,
			transparent 48%,
			hsl(var(--background) / 0.18) 72%,
			hsl(var(--background) / 0.82) 100%
		),
		radial-gradient(circle at 50% 86%, hsl(var(--primary) / 0.12), transparent 30%);
}

.hero-backdrop {
	position: absolute;
	inset: -8% -12% -16%;
	z-index: 0;
	background:
		radial-gradient(circle at 50% 72%, hsl(var(--primary) / 0.14), transparent 14%),
		radial-gradient(circle at 50% 84%, hsl(174 60% 30% / 0.34), transparent 34%),
		radial-gradient(circle at 50% 100%, hsl(var(--background) / 0.96), transparent 56%);
	filter: blur(18px);
}

.portal-trigger {
	--portal-frame-width: min(72vw, 900px);
	position: absolute;
	left: 50%;
	top: 83%;
	width: var(--portal-frame-width);
	aspect-ratio: 16 / 9;
	transform: translate(-50%, -50%);
	border: 0;
	padding: 0;
	background: transparent;
	cursor: pointer;
	display: block;
	pointer-events: auto;
	z-index: 5;
	transition:
		transform 220ms cubic-bezier(0.22, 1, 0.36, 1),
		filter 220ms ease;
}

@media (hover: hover) {
	.portal-trigger:hover {
		transform: translate(-50%, -50%) scale(1.015);
		filter: brightness(1.04);
	}
}

.portal-badge {
	position: absolute;
	left: 50%;
	top: 50%;
	transform: translate(-50%, -50%);
	z-index: 3;
	display: inline-flex;
	align-items: center;
	gap: 0.5rem;
	padding: 0.6rem 0.9rem;
	border-radius: 999px;
	border: 1px solid hsl(var(--primary) / 0.22);
	background: hsl(var(--background) / 0.46);
	color: hsl(var(--foreground) / 0.92);
	font-size: 0.84rem;
	font-weight: 600;
	letter-spacing: -0.02em;
	backdrop-filter: blur(12px);
	box-shadow: 0 12px 30px hsl(var(--background) / 0.28);
}

.portal-video-frame {
	position: relative;
	width: 100%;
	height: 100%;
	overflow: hidden;
	border-radius: 30%;
	isolation: isolate;
	box-shadow:
		0 0 90px hsl(var(--primary) / 0.1),
		0 48px 120px hsl(var(--background) / 0.5);
}

.portal-video {
	position: absolute;
	inset: 0;
	width: 100%;
	height: 100%;
	object-fit: cover;
	z-index: 0;
	pointer-events: none;
	opacity: 0.94;
	filter: saturate(0.84) brightness(0.72) contrast(1.08);
	mask-image: radial-gradient(
		circle at 50% 50%,
		black 20%,
		rgba(0, 0, 0, 0.98) 26%,
		transparent 47%
	);
}

@media (max-width: 1024px) {
	.portal-trigger {
		--portal-frame-width: min(86vw, 760px);
		top: 85%;
	}
}

@media (max-width: 640px) {
	.portal-trigger {
		--portal-frame-width: min(108vw, 620px);
		top: 88%;
	}

	.portal-badge {
		top: 16%;
		padding: 0.5rem 0.78rem;
		font-size: 0.76rem;
	}
}
</style>
