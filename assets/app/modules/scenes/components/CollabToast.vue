<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import CollabToast from "@components/collab/CollabToast.vue";

const { t } = useI18n();

const actionLabels = computed<Record<string, string>>(() => ({
  pin_created: t("scenes.collab_toast.pin_created"),
  pin_updated: t("scenes.collab_toast.pin_updated"),
  pin_deleted: t("scenes.collab_toast.pin_deleted"),
  zone_created: t("scenes.collab_toast.zone_created"),
  zone_updated: t("scenes.collab_toast.zone_updated"),
  zone_deleted: t("scenes.collab_toast.zone_deleted"),
  connection_created: t("scenes.collab_toast.connection_created"),
  connection_updated: t("scenes.collab_toast.connection_updated"),
  connection_deleted: t("scenes.collab_toast.connection_deleted"),
  annotation_created: t("scenes.collab_toast.annotation_created"),
  annotation_updated: t("scenes.collab_toast.annotation_updated"),
  annotation_deleted: t("scenes.collab_toast.annotation_deleted"),
  layer_created: t("scenes.collab_toast.layer_created"),
  layer_updated: t("scenes.collab_toast.layer_updated"),
  layer_deleted: t("scenes.collab_toast.layer_deleted"),
  scene_refreshed: t("scenes.collab_toast.scene_updated"),
  scene_settings_updated: t("scenes.collab_toast.scene_settings_changed"),
}));
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
