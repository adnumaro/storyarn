<script setup lang="ts">
import Profile from "@modules/account/settings/Profile.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <Profile v-bind="$attrs" />
</template>
