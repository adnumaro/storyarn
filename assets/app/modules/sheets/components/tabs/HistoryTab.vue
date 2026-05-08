<script setup lang="ts">
import VersionHistory from "../../../../components/versioning/history/VersionHistory.vue";
import type { VersionEntry } from "../../../../components/versioning/history/useVersionHistory";

const {
  versions = [],
  namedVersions = [],
  autoVersions = [],
  hasMore = false,
  canNameVersion = false,
  currentVersionId = null,
  canEdit = false,
  loading = false,
} = defineProps<{
  versions?: VersionEntry[];
  namedVersions?: VersionEntry[];
  autoVersions?: VersionEntry[];
  hasMore?: boolean;
  canNameVersion?: boolean;
  currentVersionId?: number | null;
  canEdit?: boolean;
  loading?: boolean;
}>();
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
