<script setup lang="ts">
import { ref, shallowRef, onMounted, onUnmounted, computed, nextTick } from "vue";
import { TresCanvas } from "@tresjs/core";
import * as THREE from "three";
import PortalScene from "./PortalScene.vue";

const containerRef = ref<HTMLDivElement | null>(null);
const reducedMotion = ref(false);
const webglFailed = ref(false);

// Shader uniforms as a shallow ref (Three.js objects, no deep reactivity)
const uniforms = shallowRef({
  uTime: { value: 0 },
  uIntensity: { value: 1.0 },
  uScale: { value: 1.0 },
  uResolution: { value: new THREE.Vector2(1, 1) },
  uPortalCenter: { value: new THREE.Vector2(0.5, 0.5) },
  uPortalMaxWidth: { value: 1000 },
  uDpr: { value: 1 },
});

const powerPreference = computed((): WebGLPowerPreference => "high-performance");
const pixelRatio = computed(() => Math.min(window.devicePixelRatio, 2));

// Public API for scroll animation to control
function setIntensity(v: number) {
  uniforms.value.uIntensity.value = v;
}
function setScale(v: number) {
  uniforms.value.uScale.value = v;
}

defineExpose({ setIntensity, setScale });

onMounted(() => {
  reducedMotion.value = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Wait a tick to ensure parent frames are mounted
  nextTick(() => {
    updatePortalPosition();
    window.addEventListener("resize", debouncedResize);

    const frameEl = document.getElementById("portal-video-frame");
    if (frameEl && "ResizeObserver" in window) {
      resizeObserver = new ResizeObserver(updatePortalPosition);
      resizeObserver.observe(frameEl);
    }
  });
});

onUnmounted(() => {
  window.removeEventListener("resize", debouncedResize);
  resizeObserver?.disconnect();
  clearTimeout(resizeTimer);
});

let resizeObserver: ResizeObserver | null = null;
let resizeTimer: ReturnType<typeof setTimeout> | null = null;

function debouncedResize() {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(updatePortalPosition, 150);
}

function updatePortalPosition() {
  const container = containerRef.value;
  if (!container) return;

  const rect = container.getBoundingClientRect();
  const width = rect.width;
  const height = rect.height;
  if (width <= 0 || height <= 0) return;

  const u = uniforms.value;
  u.uDpr.value = pixelRatio.value;
  u.uResolution.value.set(width, height);

  const frameEl = document.getElementById("portal-video-frame");
  if (frameEl) {
    const frameRect = frameEl.getBoundingClientRect();
    const minPortalWidth = window.innerWidth < 640 ? 1240 : 1020;
    const localCenterX = frameRect.left - rect.left + frameRect.width * 0.5;
    const localCenterY = frameRect.top - rect.top + frameRect.height * 0.5;
    const portalYOffset = Math.min(frameRect.height * 0.28, window.innerWidth < 640 ? 112 : 156);
    const maxPortalWidth = Math.min(Math.max(frameRect.width * 2.05 + 900, minPortalWidth), 2220);

    u.uPortalCenter.value.set(localCenterX, height - localCenterY - portalYOffset);
    u.uPortalMaxWidth.value = maxPortalWidth;
  } else {
    u.uPortalCenter.value.set(width * 0.5, height * 0.5);
    u.uPortalMaxWidth.value = Math.min(width * 0.92, 1360);
  }
}
</script>

<template>
  <div ref="containerRef" class="absolute inset-0 w-full h-full z-0 pointer-events-none">
    <!-- WebGL fallback: CSS ring for mobile or failed WebGL -->
    <div v-if="webglFailed" class="portal-fallback" />

    <!-- TresJS Canvas -->
    <TresCanvas
      v-else
      :alpha="true"
      :antialias="false"
      :power-preference="powerPreference"
      :dpr="pixelRatio"
      clear-color="#000000"
      :clear-alpha="0"
      class="absolute inset-0 w-full h-full"
    >
      <PortalScene :uniforms="uniforms" :reduced-motion="reducedMotion" />
    </TresCanvas>
  </div>
</template>

<style scoped>
.portal-fallback {
  position: absolute;
  top: 83%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: min(72vw, 760px);
  aspect-ratio: 1;
  border-radius: 50%;
  border: 3px solid hsl(var(--primary) / 0.3);
  box-shadow:
    0 0 60px hsl(var(--primary) / 0.15),
    inset 0 0 60px hsl(var(--primary) / 0.08);
}
</style>
