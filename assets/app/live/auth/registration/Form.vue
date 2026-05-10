<script setup lang="ts">
import SignUp from "@modules/auth/SignUp.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <SignUp v-bind="$attrs" />
</template>
