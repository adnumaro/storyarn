<script setup lang="ts">
import LandingPage from "@modules/public/landing/LandingPage.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <LandingPage v-bind="$attrs" />
</template>
