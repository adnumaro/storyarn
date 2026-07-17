<script setup lang="ts">
import VersionHistory from "@components/versioning/history/VersionHistory.vue";
import type { VersionEntry } from "@components/versioning/history/useVersionHistory.ts";

const {
  versions = [],
  namedVersions = [],
  autoVersions = [],
  hasMore = false,
  canNameVersion = false,
  currentVersionId = null,
  canEdit = false,
  restoreEnabled,
  loading = false,
} = defineProps<{
  versions?: VersionEntry[];
  namedVersions?: VersionEntry[];
  autoVersions?: VersionEntry[];
  hasMore?: boolean;
  canNameVersion?: boolean;
  currentVersionId?: number | null;
  canEdit?: boolean;
  restoreEnabled: boolean;
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
    :restore-enabled="restoreEnabled"
    :loading="loading"
  />
</template>
