<script setup>
import { ref, shallowRef, onMounted, onUnmounted, computed } from "vue";
import { TresCanvas, useLoop } from "@tresjs/core";
import * as THREE from "three";
import { vertexShader, fragmentShader } from "./shaders/portalShader";

const props = defineProps({
  /** Reference element for portal center positioning */
  portalFrameRef: { type: Object, default: null },
});

const containerRef = ref(null);
const isMobile = ref(false);
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

const powerPreference = computed(() => (isMobile.value ? "low-power" : "high-performance"));
const pixelRatio = computed(() => (isMobile.value ? 1 : Math.min(window.devicePixelRatio, 2)));

// Public API for scroll animation to control
function setIntensity(v) {
  uniforms.value.uIntensity.value = v;
}
function setScale(v) {
  uniforms.value.uScale.value = v;
}

defineExpose({ setIntensity, setScale });

onMounted(() => {
  isMobile.value = /Android|iPhone|iPad/i.test(navigator.userAgent) || window.innerWidth < 768;
  reducedMotion.value = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Mobile: skip WebGL entirely
  if (isMobile.value) {
    webglFailed.value = true;
    return;
  }

  updatePortalPosition();
  window.addEventListener("resize", debouncedResize);

  if (containerRef.value && "ResizeObserver" in window) {
    resizeObserver = new ResizeObserver(updatePortalPosition);
    resizeObserver.observe(containerRef.value);
  }
});

onUnmounted(() => {
  window.removeEventListener("resize", debouncedResize);
  resizeObserver?.disconnect();
  clearTimeout(resizeTimer);
});

let resizeObserver = null;
let resizeTimer = null;

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

  const frameEl = props.portalFrameRef;
  if (frameEl) {
    const frameRect = frameEl.getBoundingClientRect();
    const minPortalWidth = window.innerWidth < 640 ? 1240 : 1020;
    const localCenterX = frameRect.left - rect.left + frameRect.width * 0.5;
    const localCenterY = frameRect.top - rect.top + frameRect.height * 0.5;
    const portalYOffset = Math.min(frameRect.height * 0.28, window.innerWidth < 640 ? 112 : 156);
    const maxPortalWidth = Math.min(Math.max(frameRect.width * 1.4, minPortalWidth), 1400);

    u.uPortalCenter.value.set(localCenterX, height - localCenterY - portalYOffset);
    u.uPortalMaxWidth.value = maxPortalWidth;
  } else {
    u.uPortalCenter.value.set(width * 0.5, height * 0.5);
    u.uPortalMaxWidth.value = Math.min(width * 0.92, 1360);
  }
}

// Render loop inner component — must be a child of TresCanvas
</script>

<template>
  <div ref="containerRef" class="absolute inset-0 z-0 pointer-events-none">
    <!-- WebGL fallback: CSS ring for mobile or failed WebGL -->
    <div v-if="webglFailed" class="portal-fallback" />

    <!-- TresJS Canvas -->
    <TresCanvas
      v-else
      :alpha="true"
      :antialias="false"
      :power-preference="powerPreference"
      :dpr="pixelRatio"
      :clear-color="'#000000'"
      window-size
      class="absolute! inset-0!"
    >
      <PortalScene :uniforms="uniforms" :reduced-motion="reducedMotion" />
    </TresCanvas>
  </div>
</template>

<script>
// Separate component that lives inside TresCanvas context for useLoop
import { defineComponent, h } from "vue";
import { useLoop } from "@tresjs/core";
import { AdditiveBlending } from "three";

const PortalScene = defineComponent({
  name: "PortalScene",
  props: {
    uniforms: { type: Object, required: true },
    reducedMotion: { type: Boolean, default: false },
  },
  setup(props) {
    if (!props.reducedMotion) {
      const { onBeforeRender } = useLoop();
      const startTime = performance.now();
      onBeforeRender(() => {
        props.uniforms.uTime.value = (performance.now() - startTime) / 1000;
      });
    }

    return () =>
      h("TresOrthographicCamera", { args: [-1, 1, 1, -1, 0, 1] }, [
        h("TresMesh", null, [
          h("TresPlaneGeometry", { args: [2, 2] }),
          h("TresShaderMaterial", {
            vertexShader,
            fragmentShader,
            uniforms: props.uniforms,
            transparent: true,
            depthWrite: false,
            blending: AdditiveBlending,
          }),
        ]),
      ]);
  },
});

export { PortalScene };
</script>

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
