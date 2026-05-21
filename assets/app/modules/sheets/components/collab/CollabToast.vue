<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import CollabToast from "@components/collab/CollabToast.vue";

const { t } = useI18n();

const actionLabels = computed<Record<string, string>>(() => ({
  block_created: t("sheets.collab_toast.added_block"),
  block_updated: t("sheets.collab_toast.edited_block"),
  block_deleted: t("sheets.collab_toast.removed_block"),
  block_reordered: t("sheets.collab_toast.reordered_blocks"),
  block_type_changed: t("sheets.collab_toast.changed_type"),
  sheet_updated: t("sheets.collab_toast.updated_sheet"),
  sheet_restored: t("sheets.collab_toast.restored_version"),
}));
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
