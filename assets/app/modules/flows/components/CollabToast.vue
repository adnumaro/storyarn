<script setup lang="ts">
import CollabToast from "@components/collab/CollabToast.vue";

const actionLabels: Record<string, string> = {
  node_added: "added a node",
  node_updated: "updated a node",
  node_deleted: "removed a node",
  node_restored: "restored a node",
  node_moved: "moved a node",
  connection_added: "added a connection",
  connection_deleted: "removed a connection",
  flow_refresh: "updated the flow",
  locked: "locked a node",
  unlocked: "unlocked a node",
  entity_merged: "merged changes",
};
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
