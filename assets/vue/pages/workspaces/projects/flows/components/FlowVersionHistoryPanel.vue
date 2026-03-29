<script setup>
import { History, X } from "lucide-vue-next";
import { useLive } from "@/vue/composables/useLive.js";
import Sidebar from "@/vue/components/layout/Sidebar.vue";
import VersionHistory from "@/vue/components/shared/VersionHistory.vue";

const props = defineProps({
	versions: { type: Array, default: () => [] },
	namedVersions: { type: Array, default: () => [] },
	autoVersions: { type: Array, default: () => [] },
	hasMore: { type: Boolean, default: false },
	canNameVersion: { type: Boolean, default: false },
	currentVersionId: { type: Number, default: null },
	canEdit: { type: Boolean, default: false },
	loading: { type: Boolean, default: false },
	open: { type: Boolean, default: false },
});

const live = useLive();

function close() {
	live.pushEvent("close_versions_panel", {});
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between px-3 py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <History class="size-4" />
          Version History
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
