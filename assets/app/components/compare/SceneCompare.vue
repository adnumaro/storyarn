<script setup>
import CompareView from "./CompareView.vue";

defineProps({
  backUrl: { type: String, required: true },
  versionLabel: { type: String, default: "" },
  prevVersionUrl: { type: String, default: null },
  nextVersionUrl: { type: String, default: null },
  currentUrl: { type: String, default: "" },
  versionUrl: { type: String, default: "" },
});
</script>

<template>
  <CompareView
    :back-url="backUrl"
    :version-label="versionLabel"
    :prev-version-url="prevVersionUrl"
    :next-version-url="nextVersionUrl"
    :current-url="currentUrl"
    :version-url="versionUrl"
  />
</template>
