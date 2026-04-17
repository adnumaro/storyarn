<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import CollabToast from "@components/collab/CollabToast.vue";

const { t } = useI18n();

const actionLabels = computed<Record<string, string>>(() => ({
  node_added: t("flows.collab_toast.node_created"),
  node_updated: t("flows.collab_toast.node_updated"),
  node_deleted: t("flows.collab_toast.node_deleted"),
  node_restored: t("flows.collab_toast.node_restored"),
  node_moved: t("flows.collab_toast.node_moved"),
  connection_added: t("flows.collab_toast.connection_created"),
  connection_deleted: t("flows.collab_toast.connection_deleted"),
  flow_refresh: t("flows.collab_toast.flow_updated"),
  locked: t("flows.collab_toast.node_locked"),
  unlocked: t("flows.collab_toast.node_unlocked"),
  entity_merged: t("flows.collab_toast.flow_merged"),
}));
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
