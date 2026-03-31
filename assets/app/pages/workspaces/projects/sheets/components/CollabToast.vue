<script setup>
import CollabToast from "@components/shared/CollabToast.vue";

const actionLabels = {
  block_created: "added a block",
  block_updated: "edited a block",
  block_deleted: "removed a block",
  block_reordered: "reordered blocks",
  block_type_changed: "changed a block type",
  sheet_updated: "updated the sheet",
  sheet_restored: "restored a version",
};
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
