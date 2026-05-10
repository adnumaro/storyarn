<script setup lang="ts">
import WorkspaceDeletedProjects from "@modules/workspaces/settings/WorkspaceDeletedProjects.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <WorkspaceDeletedProjects v-bind="$attrs" />
</template>
