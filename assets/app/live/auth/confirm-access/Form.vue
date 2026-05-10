<script setup lang="ts">
import ConfirmAccess from "@modules/auth/ConfirmAccess.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <ConfirmAccess v-bind="$attrs" />
</template>
