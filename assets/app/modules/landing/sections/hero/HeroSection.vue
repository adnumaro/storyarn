<script setup lang="ts">
import { Play, X } from "lucide-vue-next";
import { ref, onMounted, onUnmounted } from "vue";
import { gsap } from "gsap";
import PortalRing from "./PortalRing.vue";

const portalRef = ref<InstanceType<typeof PortalRing> | null>(null);
const portalFrameRef = ref<HTMLDivElement | null>(null);
const videoRef = ref<HTMLVideoElement | null>(null);
const fullscreenRef = ref<HTMLDivElement | null>(null);
const triggerRef = ref<HTMLButtonElement | null>(null);

let currentTimeline: gsap.core.Timeline | null = null;
let isTransitioning = false;
let isFullscreenNative = false;

function setVideoMask(video: HTMLVideoElement, solidPct: number, fadePct: number) {
  const mask = `radial-gradient(circle at 50% 50%, black ${solidPct}%, transparent ${fadePct}%)`;
  video.style.maskImage = mask;
  video.style.webkitMaskImage = mask;
}

function clearVideoMask(video: HTMLVideoElement) {
  video.style.maskImage = "";
  video.style.webkitMaskImage = "";
}

function resolvedBoxShadow(boxShadow: string) {
  if (!boxShadow || boxShadow === "none" || boxShadow === "")
    return "0 40px 120px rgba(0, 0, 0, 0.46)";
  return boxShadow;
}

function openFullscreen() {
  if (isTransitioning || isFullscreenNative) return;
  const video = videoRef.value;
  const frame = portalFrameRef.value;
  const fullscreen = fullscreenRef.value;
  const heroContent = document.getElementById("hero-content-inner");
  const portalBadge = document.querySelector(".portal-badge") as HTMLElement | null;

  if (!video || !frame || !fullscreen || !triggerRef.value) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduced) {
    fullscreen.appendChild(video);
    triggerRef.value.classList.add("is-active");
    fullscreen.classList.add("is-active");
    fullscreen.style.opacity = "1";
    fullscreen.style.pointerEvents = "auto";
    video.muted = false;
    video.volume = 1;
    video.currentTime = 0;
    isFullscreenNative = true;
    return;
  }

  isTransitioning = true;
  if (currentTimeline) currentTimeline.kill();

  gsap.killTweensOf([heroContent, frame, portalBadge, video, fullscreen]);

  // Fade out hero content
  if (heroContent) {
    gsap.to(heroContent, { opacity: 0, y: -48, duration: 0.5, ease: "power2.in" });
  }

  try {
    video.muted = false;
    video.volume = 0;
    video.currentTime = 0;
  } catch (e) {}

  const videoRect = frame.getBoundingClientRect();
  const frameStyle = window.getComputedStyle(frame);
  const startRadius = frameStyle.borderRadius;
  const startShadow = resolvedBoxShadow(frameStyle.boxShadow);
  const fullscreenShadow = "0 40px 120px rgba(0, 0, 0, 0.46)";
  const topbar = document.querySelector("header") as HTMLElement | null;

  const targetW = Math.min(window.innerWidth * 0.92, 1400);
  const targetH = targetW * (9 / 16);
  const targetX = (window.innerWidth - targetW) / 2;
  const targetY = (window.innerHeight - targetH) / 2;

  fullscreen.appendChild(video);
  triggerRef.value.classList.add("is-active");

  // Set fly styles
  video.style.position = "fixed";
  video.style.top = `${videoRect.top}px`;
  video.style.left = `${videoRect.left}px`;
  video.style.width = `${videoRect.width}px`;
  video.style.height = `${videoRect.height}px`;
  video.style.transform = "none";
  video.style.zIndex = "99999";
  video.style.pointerEvents = "auto";
  video.style.objectFit = "cover";
  video.style.borderRadius = startRadius;
  video.style.boxShadow = startShadow;
  video.style.opacity = "0.7";
  video.style.filter = "saturate(0.84) brightness(0.72) contrast(1.08)";
  setVideoMask(video, 5, 55);

  const maskProxy = { solid: 5, fade: 55 };
  const proxy = { scale: 1, intensity: 1, vol: 0 };

  currentTimeline = gsap.timeline({
    onComplete() {
      video.style.cssText = "";
      video.style.width = "100%";
      video.style.height = "100%";
      video.style.objectFit = "contain";
      video.style.opacity = "";
      video.style.filter = "";
      fullscreen.appendChild(video);
      clearVideoMask(video);
      try {
        video.volume = 1;
      } catch (e) {}
      currentTimeline = null;
      isTransitioning = false;
      isFullscreenNative = true;
      fullscreen.classList.add("is-active");
      fullscreen.style.pointerEvents = "auto";
    },
  });

  // Allow the WebGL scale to handle the immersion without aggressive blackout

  if (topbar) {
    currentTimeline.to(topbar, { opacity: 0, y: -40, duration: 0.8, ease: "power3.inOut" }, 0);
  }

  currentTimeline.to(
    video,
    {
      top: targetY,
      left: targetX,
      width: targetW,
      height: targetH,
      borderRadius: 12,
      boxShadow: fullscreenShadow,
      opacity: 1,
      filter: "saturate(1) brightness(1) contrast(1)",
      duration: 1.22,
      ease: "power3.in",
    },
    0,
  );

  currentTimeline.to(
    maskProxy,
    {
      solid: 100,
      fade: 100,
      duration: 1.0,
      ease: "power2.in",
      onUpdate: () => setVideoMask(video, maskProxy.solid, maskProxy.fade),
    },
    0,
  );

  currentTimeline.to(frame, { opacity: 0, duration: 0.52, ease: "power2.inOut" }, 0.22);

  if (portalBadge) {
    currentTimeline.to(portalBadge, { opacity: 0, duration: 0.34, ease: "power2.inOut" }, 0.16);
  }

  currentTimeline.to(
    proxy,
    {
      scale: 10,
      intensity: 3,
      vol: 1,
      duration: 1.4,
      ease: "power3.in",
      onUpdate() {
        portalRef.value?.setScale(proxy.scale);
        portalRef.value?.setIntensity(proxy.intensity);
        try {
          video.volume = proxy.vol;
        } catch (e) {}
      },
    },
    0,
  );
}

function closeFullscreen() {
  if (isTransitioning || !isFullscreenNative) return;
  const video = videoRef.value;
  const frame = portalFrameRef.value;
  const fullscreen = fullscreenRef.value;
  const heroContent = document.getElementById("hero-content-inner");
  const portalBadge = document.querySelector(".portal-badge") as HTMLElement | null;

  if (!video || !frame || !fullscreen || !triggerRef.value) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduced) {
    fullscreen.classList.remove("is-active");
    fullscreen.style.opacity = "0";
    fullscreen.style.pointerEvents = "none";
    frame.appendChild(video);
    video.muted = true;
    clearVideoMask(video);
    triggerRef.value.classList.remove("is-active");
    isFullscreenNative = false;
    const topbar = document.querySelector("header") as HTMLElement | null;
    if (topbar) {
      topbar.style.opacity = "";
    }
    return;
  }

  isTransitioning = true;
  if (currentTimeline) currentTimeline.kill();

  const volProxy = { vol: video.volume || 1 };
  gsap.to(volProxy, {
    vol: 0,
    duration: 0.4,
    onUpdate: () => {
      try {
        video.volume = volProxy.vol;
      } catch (e) {}
    },
    onComplete: () => {
      video.muted = true;
    },
  });

  const videoRect = video.getBoundingClientRect();
  const targetRect = frame.getBoundingClientRect();
  const frameStyle = window.getComputedStyle(frame);
  const targetRadius = frameStyle.borderRadius;
  const targetShadow = resolvedBoxShadow(frameStyle.boxShadow);

  fullscreen.classList.remove("is-active");
  fullscreen.style.pointerEvents = "none";
  triggerRef.value.classList.add("is-active");

  video.style.position = "fixed";
  video.style.top = `${videoRect.top}px`;
  video.style.left = `${videoRect.left}px`;
  video.style.width = `${videoRect.width}px`;
  video.style.height = `${videoRect.height}px`;
  video.style.objectFit = "cover";
  video.style.opacity = "1";
  video.style.filter = "saturate(1) brightness(1) contrast(1)";
  document.body.appendChild(video);
  clearVideoMask(video);

  const maskProxy = { solid: 100, fade: 100 };
  const zoomProxy = { scale: 10, intensity: 3 };

  const topbar = document.querySelector("header") as HTMLElement | null;

  currentTimeline = gsap.timeline({
    onComplete() {
      video.style.cssText = "";
      video.style.position = "absolute";
      video.style.inset = "0";
      video.style.width = "100%";
      video.style.height = "100%";
      video.style.objectFit = "cover";
      clearVideoMask(video);
      frame.appendChild(video);
      triggerRef.value?.classList.remove("is-active");
      frame.style.opacity = "";
      if (portalBadge) portalBadge.style.opacity = "";
      if (topbar) {
        topbar.style.opacity = "";
      }
      currentTimeline = null;
      isTransitioning = false;
      isFullscreenNative = false;
    },
  });

  currentTimeline.to(
    video,
    {
      top: targetRect.top,
      left: targetRect.left,
      width: targetRect.width,
      height: targetRect.height,
      borderRadius: targetRadius,
      boxShadow: targetShadow,
      opacity: 0.7,
      filter: "saturate(0.84) brightness(0.72) contrast(1.08)",
      duration: 0.72,
      ease: "power2.out",
    },
    0,
  );

  if (topbar) {
    currentTimeline.to(topbar, { opacity: 1, y: 0, duration: 0.72, ease: "power2.out" }, 0);
  }

  currentTimeline.to(
    maskProxy,
    {
      solid: 5,
      fade: 55,
      duration: 0.58,
      ease: "power2.out",
      onUpdate: () => setVideoMask(video, maskProxy.solid, maskProxy.fade),
    },
    0.08,
  );

  currentTimeline.to(frame, { opacity: 1, duration: 0.18, ease: "power2.inOut" }, 0.56);

  if (portalBadge) {
    currentTimeline.to(portalBadge, { opacity: 1, duration: 0.18, ease: "power2.inOut" }, 0.62);
  }

  currentTimeline.to(
    zoomProxy,
    {
      scale: 1,
      intensity: 1,
      duration: 0.6,
      ease: "power2.out",
      onUpdate() {
        portalRef.value?.setScale(zoomProxy.scale);
        portalRef.value?.setIntensity(zoomProxy.intensity);
      },
    },
    0,
  );

  if (heroContent) {
    gsap.to(heroContent, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out", delay: 0.2 });
  }
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === "Escape" && isFullscreenNative) closeFullscreen();
}

onMounted(() => {
  document.addEventListener("keydown", onKeydown);
});

onUnmounted(() => {
  document.removeEventListener("keydown", onKeydown);
  if (currentTimeline) currentTimeline.kill();
});
</script>

<template>
  <section
    id="hero-section"
    class="hero-section relative isolate min-h-svh overflow-hidden"
    tabindex="-1"
  >
    <!-- Portal energy ring (WebGL) -->
    <PortalRing ref="portalRef" />

    <!-- Radial glow backdrop -->
    <div class="hero-backdrop" aria-hidden="true" />

    <!-- Video portal trigger -->
    <button
      ref="triggerRef"
      id="portal-trigger"
      class="portal-trigger"
      type="button"
      :aria-label="$t('landing.hero.video_demo_sr')"
      @click="openFullscreen"
    >
      <span class="portal-badge">
        <Play class="size-4" />
        <span>{{ $t("landing.hero.video_demo_badge") }}</span>
      </span>

      <div ref="portalFrameRef" id="portal-video-frame" class="portal-video-frame">
        <video
          ref="videoRef"
          id="portal-video"
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
      id="hero-content"
      class="pointer-events-none relative z-10 mx-auto flex min-h-svh w-full max-w-295 flex-col items-center justify-center px-6 pb-20 pt-28 text-center sm:px-8 sm:pb-24 sm:pt-32 lg:pt-40"
      style="transform: translateY(-16%)"
    >
      <div id="hero-content-inner" class="pointer-events-auto">
        <!-- Eyebrow badge -->
        <div
          class="inline-flex items-center gap-1.5 rounded-full border border-primary/20 bg-primary/10 px-3 py-1.5 text-[0.65rem] uppercase tracking-widest text-primary sm:gap-2.5 sm:px-4 sm:py-2.5 sm:text-xs"
        >
          <span
            class="size-2 animate-pulse rounded-full bg-primary shadow-[0_0_20px_var(--color-primary)] sm:size-2.5"
          />
          {{ $t("landing.common.badge") }}
        </div>

        <div class="mt-5 sm:mt-7">
          <h1
            class="text-[clamp(2.6rem,7.2vw,5.8rem)] font-bold leading-[0.88] tracking-[-0.07em] text-foreground"
          >
            {{ $t("landing.hero.title_part1") }}
            <span class="mt-1.5 block text-[1em] brand-logotype">
              {{ $t("landing.hero.title_part2") }}
            </span>
          </h1>
        </div>

        <p
          class="hidden sm:block mx-auto mt-6 max-w-184 text-sm leading-relaxed text-white/90 sm:text-lg text-balance"
        >
          {{ $t("landing.hero.description") }}
        </p>

        <div class="mt-8 flex flex-wrap justify-center gap-3 sm:gap-3.5">
          <!-- Shadcn Styled Buttons with Staging Glow -->
          <a
            href="#discover"
            class="inline-flex items-center justify-center rounded-md px-5 py-2.5 text-sm sm:px-6 sm:py-3 sm:text-[0.95rem] md:px-8 md:py-3.5 md:text-base font-bold text-teal-950 transition-all hover:scale-105"
            style="
              background: linear-gradient(135deg, oklch(78% 0.14 185), oklch(68% 0.12 210));
              box-shadow:
                0 0 20px rgba(34, 211, 238, 0.4),
                inset 0 1px 0 rgba(255, 255, 255, 0.3);
            "
          >
            {{ $t("landing.hero.cta_explore") }}
          </a>
          <a
            href="#workflow"
            class="inline-flex items-center justify-center rounded-md border border-white/10 px-5 py-2.5 text-sm sm:px-6 sm:py-3 sm:text-[0.95rem] md:px-8 md:py-3.5 md:text-base font-medium text-foreground transition-colors hover:bg-white/5"
            style="backdrop-filter: blur(8px)"
          >
            {{ $t("landing.hero.cta_workflow") }}
          </a>
        </div>
      </div>
    </div>

    <!-- Fullscreen video overlay (Root level for GSAP to manipulate) -->
    <div
      ref="fullscreenRef"
      id="portal-fullscreen"
      class="portal-fullscreen"
      @click.self="closeFullscreen"
    >
      <button
        class="absolute right-6 top-6 z-10 flex size-11 items-center justify-center rounded-full border border-border/30 bg-muted/30 text-foreground transition-colors hover:bg-muted/50"
        :aria-label="$t('landing.hero.video_close_sr')"
        @click="closeFullscreen"
      >
        <X class="size-5" />
      </button>
    </div>
  </section>
</template>

<style scoped>
@import url("https://fonts.googleapis.com/css2?family=Sonsie+One&display=swap");

.hero-section {
  background:
    radial-gradient(circle at 50% 18%, var(--primary), transparent 28%),
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
  background: radial-gradient(
    circle at 50% 72%,
    rgba(34, 211, 238, 0.38) 0%,
    rgba(17, 132, 164, 0.24) 24%,
    rgba(7, 13, 19, 0.9) 62%,
    rgba(4, 8, 14, 1) 100%
  );
}

.brand-logotype {
  font-family: "Sonsie One", var(--font-display, cursive);
  font-weight: 400;
  letter-spacing: 0.05em;
  background: linear-gradient(
    90deg,
    oklch(78% 0.14 185) 0%,
    oklch(68% 0.12 210) 35%,
    currentColor 55%
  );
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.hero-backdrop {
  position: absolute;
  inset: -8% -12% -16%;
  z-index: 0;
}

.portal-trigger {
  width: min(100vw, 950px);
  height: clamp(650px, 65vh, 950px);
  position: absolute;
  left: 50%;
  top: 86%;
  transform: translate(-50%, -50%);
  border: 0;
  padding: 0;
  background: transparent;
  cursor: pointer;
  display: block;
  pointer-events: auto;
  z-index: 5;
  transition:
    transform 0.4s cubic-bezier(0.2, 0.8, 0.2, 1),
    filter 0.4s cubic-bezier(0.2, 0.8, 0.2, 1);
}

.portal-fullscreen {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.5s ease;
}

.portal-fullscreen.is-active {
  opacity: 1;
  pointer-events: auto;
  background: rgba(0, 0, 0, 0.94);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
}

.portal-trigger.is-active {
  pointer-events: none;
}

@media (hover: hover) {
  .portal-trigger:not(.is-active):hover {
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
  isolation: isolate;
  filter: saturate(0.84) brightness(0.72) contrast(1.08);
  mask-image: radial-gradient(circle at 50% 50%, black 5%, rgba(0, 0, 0, 0.98) 6%, transparent 55%);
  -webkit-mask-image: radial-gradient(
    circle at 50% 50%,
    black 5%,
    rgba(0, 0, 0, 0.98) 6%,
    transparent 55%
  );
  opacity: 0.7;
}

.portal-video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  z-index: 0;
  pointer-events: none;
}

@media (max-width: 640px) {
  .portal-badge {
    padding: 0.5rem 0.78rem;
    font-size: 0.76rem;
  }
}
</style>
