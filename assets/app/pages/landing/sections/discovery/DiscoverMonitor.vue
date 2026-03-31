<script setup>
/**
 * 3D monitor wrapper for the Discover section.
 * Handles TresCanvas setup, mobile/a11y detection.
 * The actual 3D scene lives in MonitorScene.vue.
 */

import { TresCanvas } from "@tresjs/core";
import { onMounted, ref } from "vue";
import MonitorScene from "./MonitorScene.vue";

const props = defineProps({
  activeStep: { type: Number, default: 0 },
  isVisible: { type: Boolean, default: false },
});

const isMobile = ref(false);
const reducedMotion = ref(false);
const dpr = ref(typeof window !== "undefined" ? Math.min(window.devicePixelRatio, 2) : 1);

onMounted(() => {
  isMobile.value = /Android|iPhone|iPad/i.test(navigator.userAgent) || window.innerWidth < 768;
  reducedMotion.value = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
});
</script>

<template>
  <div class="absolute inset-0 z-0 pointer-events-none">
    <template v-if="!isMobile && !reducedMotion">
      <TresCanvas
        :alpha="true"
        :antialias="true"
        power-preference="high-performance"
        :dpr="dpr"
        :clear-alpha="0"
      >
        <MonitorScene :active-step="activeStep" :is-visible="isVisible" />
      </TresCanvas>
    </template>
  </div>
</template>
