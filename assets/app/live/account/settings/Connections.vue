<script setup lang="ts">
import Connections from "@modules/account/settings/Connections.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <Connections v-bind="$attrs" />
</template>
