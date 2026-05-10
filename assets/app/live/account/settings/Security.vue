<script setup lang="ts">
import Security from "@modules/account/settings/Security.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <Security v-bind="$attrs" />
</template>
