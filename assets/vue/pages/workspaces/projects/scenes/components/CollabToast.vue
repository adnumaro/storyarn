<script setup>
import CollabToast from "@/vue/components/shared/CollabToast.vue";

const actionLabels = {
	pin_created: "added a pin",
	pin_updated: "updated a pin",
	pin_deleted: "removed a pin",
	zone_created: "added a zone",
	zone_updated: "updated a zone",
	zone_deleted: "removed a zone",
	connection_created: "added a connection",
	connection_updated: "updated a connection",
	connection_deleted: "removed a connection",
	annotation_created: "added an annotation",
	annotation_updated: "updated an annotation",
	annotation_deleted: "removed an annotation",
	layer_created: "added a layer",
	layer_updated: "updated a layer",
	layer_deleted: "removed a layer",
	scene_refreshed: "updated the scene",
	scene_settings_updated: "changed scene settings",
};
</script>

<template>
  <CollabToast :action-labels="actionLabels" />
</template>
