<script setup lang="ts">
import SignIn from "@modules/auth/SignIn.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <SignIn v-bind="$attrs" />
</template>
