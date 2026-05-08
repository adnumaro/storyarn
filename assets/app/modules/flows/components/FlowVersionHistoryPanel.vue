<script setup lang="ts">
import { History, X } from "lucide-vue-next";
import Sidebar from "../../../shell/Sidebar.vue";
import VersionHistory from "@components/version-history/VersionHistory.vue";
import type { VersionEntry } from "@components/version-history/useVersionHistory";
import { useLive } from "@composables/useLive";

const {
  versions = [],
  namedVersions = [],
  autoVersions = [],
  hasMore = false,
  canNameVersion = false,
  currentVersionId = null,
  canEdit = false,
  loading = false,
  open = false,
} = defineProps<{
  versions?: VersionEntry[];
  namedVersions?: VersionEntry[];
  autoVersions?: VersionEntry[];
  hasMore?: boolean;
  canNameVersion?: boolean;
  currentVersionId?: number | null;
  canEdit?: boolean;
  loading?: boolean;
  open?: boolean;
}>();

const live = useLive();

function close() {
  live.pushEvent("close_versions_panel", {});
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <History class="size-4" />
          {{ $t("flows.version_history.title") }}
        </div>
        <button
          type="button"
          class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
          @click="close"
        >
          <X class="size-4" />
        </button>
      </div>
    </template>
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
  </Sidebar>
</template>
