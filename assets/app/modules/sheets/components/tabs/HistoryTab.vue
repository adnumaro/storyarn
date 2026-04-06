<script setup>
import VersionHistory from "@components/version-history/VersionHistory.vue";

const {
  versions,
  namedVersions,
  autoVersions,
  hasMore,
  canNameVersion,
  currentVersionId,
  canEdit,
  loading,
} = defineProps({
  versions: { type: Array, default: () => [] },
  namedVersions: { type: Array, default: () => [] },
  autoVersions: { type: Array, default: () => [] },
  hasMore: { type: Boolean, default: false },
  canNameVersion: { type: Boolean, default: false },
  currentVersionId: { type: Number, default: null },
  canEdit: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});
</script>

<template>
  <VersionHistory
    :versions="versions"
    :named-versions="namedVersions"
    :auto-versions="autoVersions"
    :has-more="hasMore"
    :can-name-version="canNameVersion"
    :current-version-id="currentVersionId"
    :can-edit="canEdit"
    :loading="loading"
  />
</template>
