<script setup lang="ts">
import WorkspaceMembers from "@modules/workspaces/settings/WorkspaceMembers.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <WorkspaceMembers v-bind="$attrs" />
</template>
