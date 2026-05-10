<script setup lang="ts">
import WorkspaceGeneral from "@modules/workspaces/settings/WorkspaceGeneral.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <WorkspaceGeneral v-bind="$attrs" />
</template>
