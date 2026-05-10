<script setup lang="ts">
import DocsShow from "@modules/docs/DocsShow.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <DocsShow v-bind="$attrs" />
</template>
