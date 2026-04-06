<script setup lang="ts">
import CompareView from "./CompareView.vue";

const { backUrl, versionLabel = "", prevVersionUrl = null, nextVersionUrl = null, currentUrl = "", versionUrl = "" } =
  defineProps<{
    backUrl: string;
    versionLabel?: string;
    prevVersionUrl?: string | null;
    nextVersionUrl?: string | null;
    currentUrl?: string;
    versionUrl?: string;
  }>();
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
