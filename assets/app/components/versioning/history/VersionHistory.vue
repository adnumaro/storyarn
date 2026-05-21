<script setup lang="ts">
import {
  Bookmark,
  BookmarkPlus,
  ChevronDown,
  ChevronRight,
  Clock,
  Columns2,
  Loader2,
  Plus,
  RotateCcw,
  Trash2,
} from "lucide-vue-next";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import { useVersionHistory, type VersionEntry } from "./useVersionHistory";
import {
  CreateVersionDialog,
  PromoteVersionDialog,
  DeleteVersionDialog,
  UnsavedChangesDialog,
  RestorePreviewDialog,
} from "./index.ts";

type Version = VersionEntry;

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
  versions?: Version[];
  namedVersions?: Version[];
  autoVersions?: Version[];
  hasMore?: boolean;
  canNameVersion?: boolean;
  currentVersionId?: number | null;
  canEdit?: boolean;
  loading?: boolean;
}>();

const live = useLive();
const h = useVersionHistory();

function changeActionIcon(action: string) {
  if (action === "added") return "+";
  if (action === "modified") return "~";
  if (action === "removed") return "-";
  return "?";
}

function changeActionColor(action: string) {
  if (action === "added") return "text-green-600 dark:text-green-400";
  if (action === "modified") return "text-amber-600 dark:text-amber-400";
  if (action === "removed") return "text-red-600 dark:text-red-400";
  return "text-muted-foreground";
}
</script>

<template>
  <!-- Loading -->
  <div v-if="loading" class="flex items-center justify-center p-16">
    <div
      class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin"
    />
  </div>

  <!-- Empty state -->
  <div
    v-else-if="versions.length === 0"
    class="rounded-xl border border-border/60 bg-card p-8 text-center"
  >
    <Clock class="size-10 mx-auto text-muted-foreground/20 mb-3" />
    <p class="text-sm font-medium text-muted-foreground mb-1">
      {{ $t("common.version_history.empty_title") }}
    </p>
    <p class="text-xs text-muted-foreground/60 mb-4">
      {{ $t("common.version_history.empty_description") }}
    </p>
    <Button v-if="canEdit && canNameVersion" size="sm" class="gap-1.5" @click="h.openCreateModal">
      <Plus class="size-3.5" />
      {{ $t("common.version_history.create_version") }}
    </Button>
  </div>

  <!-- Main content -->
  <div v-else class="space-y-4">
    <!-- Create button -->
    <div v-if="canEdit && canNameVersion" class="flex justify-end">
      <Button size="sm" class="gap-1.5" @click="h.openCreateModal">
        <Plus class="size-3.5" />
        {{ $t("common.version_history.create_version") }}
      </Button>
    </div>

    <!-- Named Versions -->
    <div v-if="namedVersions.length > 0" class="space-y-2">
      <h3 class="text-xs font-medium text-muted-foreground flex items-center gap-1.5">
        <Bookmark class="size-3.5" />
        {{ $t("common.version_history.named_versions") }}
      </h3>
      <div
        v-for="version in namedVersions"
        :key="version.id"
        :class="[
          'flex items-start gap-2.5 p-3 rounded-lg group',
          version.id === currentVersionId
            ? 'bg-primary/10 border border-primary/30'
            : 'hover:bg-muted',
        ]"
      >
        <div
          :class="[
            'flex-shrink-0 size-7 rounded-full flex items-center justify-center mt-0.5',
            version.id === currentVersionId
              ? 'bg-primary text-primary-foreground'
              : 'bg-amber-500/15 text-amber-600 dark:text-amber-400',
          ]"
        >
          <Bookmark class="size-3.5" />
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-1">
            <div class="flex items-center gap-1.5 min-w-0">
              <span class="text-sm font-medium truncate">
                {{
                  version.title || version.changeSummary || $t("common.version_history.no_summary")
                }}
              </span>
              <Badge
                v-if="version.id === currentVersionId"
                variant="default"
                class="text-[10px] px-1.5 py-0 rounded-full shrink-0"
              >
                {{ $t("common.version_history.current") }}
              </Badge>
              <Badge variant="outline" class="text-[10px] px-1.5 py-0 rounded-full shrink-0">
                v{{ version.versionNumber }}
              </Badge>
            </div>
            <div
              class="flex-shrink-0 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <button
                class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                title="Compare with current"
                @click="
                  live.pushEvent('compare_version', { version_number: version.versionNumber })
                "
              >
                <Columns2 class="size-3.5" />
              </button>
              <button
                v-if="canEdit && version.id !== currentVersionId"
                class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                title="Restore this version"
                @click="h.previewRestore(version.versionNumber)"
              >
                <Loader2
                  v-if="h.loadingAction.value === `restore-${version.versionNumber}`"
                  class="size-3.5 animate-spin"
                />
                <RotateCcw v-else class="size-3.5" />
              </button>
              <button
                v-if="canEdit"
                class="p-1 rounded hover:bg-muted text-destructive transition-colors"
                title="Delete version"
                @click="h.openDeleteModal(version.versionNumber)"
              >
                <Trash2 class="size-3.5" />
              </button>
            </div>
          </div>
          <p v-if="version.description" class="text-xs text-muted-foreground mt-0.5">
            {{ version.description }}
          </p>
          <p
            v-if="version.changeSummary && version.changeSummary !== version.title"
            class="text-xs text-muted-foreground mt-0.5 line-clamp-2"
          >
            {{ version.changeSummary }}
          </p>
          <div v-if="version.changeDetails" class="mt-1">
            <button
              class="text-[11px] text-muted-foreground hover:text-foreground transition-colors flex items-center gap-0.5"
              @click="h.toggleChangelog(version.versionNumber)"
            >
              <ChevronDown
                v-if="h.expandedChangelogs.value.has(version.versionNumber)"
                class="size-3"
              />
              <ChevronRight v-else class="size-3" />
              <span class="flex items-center gap-1.5">
                <span
                  v-if="(version.changeDetails?.stats?.added ?? 0) > 0"
                  class="text-green-600 dark:text-green-400"
                >
                  +{{ version.changeDetails?.stats?.added }}
                </span>
                <span
                  v-if="(version.changeDetails?.stats?.modified ?? 0) > 0"
                  class="text-amber-600 dark:text-amber-400"
                >
                  ~{{ version.changeDetails?.stats?.modified }}
                </span>
                <span
                  v-if="(version.changeDetails?.stats?.removed ?? 0) > 0"
                  class="text-red-600 dark:text-red-400"
                >
                  -{{ version.changeDetails?.stats?.removed }}
                </span>
              </span>
            </button>
            <div
              v-if="h.expandedChangelogs.value.has(version.versionNumber)"
              class="mt-1.5 space-y-0.5 ml-0.5"
            >
              <div
                v-for="(change, ci) in version.changeDetails?.changes"
                :key="ci"
                class="flex items-start gap-1.5 text-[11px]"
              >
                <span
                  :class="[
                    'flex-shrink-0 font-mono font-bold leading-4',
                    changeActionColor(change.action),
                  ]"
                >
                  {{ changeActionIcon(change.action) }}
                </span>
                <span class="text-muted-foreground leading-4">{{ change.detail }}</span>
              </div>
            </div>
          </div>
          <div class="text-xs text-muted-foreground mt-1">
            {{ version.insertedAt }}
          </div>
          <div v-if="version.createdBy" class="text-xs text-muted-foreground truncate">
            by {{ version.createdBy }}
          </div>
        </div>
      </div>
    </div>

    <!-- Auto-saves section -->
    <div v-if="autoVersions.length > 0">
      <button
        class="text-xs font-medium text-muted-foreground flex items-center gap-1.5 mb-2 hover:text-foreground transition-colors"
        @click="h.showAutoVersions.value = !h.showAutoVersions.value"
      >
        <ChevronDown v-if="h.showAutoVersions.value" class="size-3.5" />
        <ChevronRight v-else class="size-3.5" />
        {{ autoVersions.length }} {{ $t("common.version_history.auto_save", autoVersions.length) }}
      </button>
      <div v-if="h.showAutoVersions.value" class="space-y-1">
        <div
          v-for="version in autoVersions"
          :key="version.id"
          :class="[
            'flex items-start gap-2.5 p-3 rounded-lg group',
            version.id === currentVersionId
              ? 'bg-primary/10 border border-primary/30'
              : 'hover:bg-muted',
          ]"
        >
          <div
            :class="[
              'flex-shrink-0 size-7 rounded-full flex items-center justify-center mt-0.5 text-[10px] font-semibold',
              version.id === currentVersionId
                ? 'bg-primary text-primary-foreground'
                : 'bg-muted text-foreground',
            ]"
          >
            v{{ version.versionNumber }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between gap-1">
              <div class="flex items-center gap-1.5 min-w-0">
                <span class="text-sm text-foreground truncate">
                  {{ version.changeSummary || $t("common.version_history.no_summary") }}
                </span>
                <Badge
                  v-if="version.id === currentVersionId"
                  variant="default"
                  class="text-[10px] px-1.5 py-0 rounded-full shrink-0"
                >
                  Current
                </Badge>
              </div>
              <div
                class="flex-shrink-0 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <button
                  class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                  title="Compare with current"
                  @click="
                    live.pushEvent('compare_version', { version_number: version.versionNumber })
                  "
                >
                  <Columns2 class="size-3.5" />
                </button>
                <button
                  v-if="canEdit && canNameVersion"
                  class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                  title="Name this version"
                  @click="h.openPromoteModal(version)"
                >
                  <BookmarkPlus class="size-3.5" />
                </button>
                <button
                  v-if="canEdit && version.id !== currentVersionId"
                  class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                  title="Restore this version"
                  @click="h.previewRestore(version.versionNumber)"
                >
                  <Loader2
                    v-if="h.loadingAction.value === `restore-${version.versionNumber}`"
                    class="size-3.5 animate-spin"
                  />
                  <RotateCcw v-else class="size-3.5" />
                </button>
                <button
                  v-if="canEdit"
                  class="p-1 rounded hover:bg-muted text-destructive transition-colors"
                  title="Delete version"
                  @click="h.openDeleteModal(version.versionNumber)"
                >
                  <Trash2 class="size-3.5" />
                </button>
              </div>
            </div>
            <div v-if="version.changeDetails" class="mt-1">
              <button
                class="text-[11px] text-muted-foreground hover:text-foreground transition-colors flex items-center gap-0.5"
                @click="h.toggleChangelog(version.versionNumber)"
              >
                <ChevronDown
                  v-if="h.expandedChangelogs.value.has(version.versionNumber)"
                  class="size-3"
                />
                <ChevronRight v-else class="size-3" />
                <span class="flex items-center gap-1.5">
                  <span
                    v-if="(version.changeDetails?.stats?.added ?? 0) > 0"
                    class="text-green-600 dark:text-green-400"
                  >
                    +{{ version.changeDetails?.stats?.added }}
                  </span>
                  <span
                    v-if="(version.changeDetails?.stats?.modified ?? 0) > 0"
                    class="text-amber-600 dark:text-amber-400"
                  >
                    ~{{ version.changeDetails?.stats?.modified }}
                  </span>
                  <span
                    v-if="(version.changeDetails?.stats?.removed ?? 0) > 0"
                    class="text-red-600 dark:text-red-400"
                  >
                    -{{ version.changeDetails?.stats?.removed }}
                  </span>
                </span>
              </button>
              <div
                v-if="h.expandedChangelogs.value.has(version.versionNumber)"
                class="mt-1.5 space-y-0.5 ml-0.5"
              >
                <div
                  v-for="(change, ci) in version.changeDetails?.changes"
                  :key="ci"
                  class="flex items-start gap-1.5 text-[11px]"
                >
                  <span
                    :class="[
                      'flex-shrink-0 font-mono font-bold leading-4',
                      changeActionColor(change.action),
                    ]"
                  >
                    {{ changeActionIcon(change.action) }}
                  </span>
                  <span class="text-muted-foreground leading-4">{{ change.detail }}</span>
                </div>
              </div>
            </div>
            <div class="text-xs text-muted-foreground mt-1">
              {{ version.insertedAt }}
            </div>
            <div v-if="version.createdBy" class="text-xs text-muted-foreground truncate">
              by {{ version.createdBy }}
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Load more -->
    <Button
      v-if="hasMore"
      variant="ghost"
      size="sm"
      class="w-full gap-1.5"
      :disabled="h.loadingAction.value === 'load-more'"
      @click="h.loadMore"
    >
      <Loader2 v-if="h.loadingAction.value === 'load-more'" class="size-3.5 animate-spin" />
      <ChevronDown v-else class="size-3.5" />
      {{ $t("common.version_history.load_more") }}
    </Button>
  </div>

  <!-- Dialogs -->
  <CreateVersionDialog
    :open="h.showCreateModal.value"
    :title="h.createTitle.value"
    :description="h.createDescription.value"
    :loading-action="h.loadingAction.value"
    @update:open="h.showCreateModal.value = $event"
    @update:title="h.createTitle.value = $event"
    @update:description="h.createDescription.value = $event"
    @submit="h.submitCreate"
  />

  <PromoteVersionDialog
    :open="h.showPromoteModal.value"
    :title="h.promoteTitle.value"
    :description="h.promoteDescription.value"
    :promote-version="h.promoteVersion.value"
    :loading-action="h.loadingAction.value"
    @update:open="h.showPromoteModal.value = $event"
    @update:title="h.promoteTitle.value = $event"
    @update:description="h.promoteDescription.value = $event"
    @submit="h.submitPromote"
  />

  <DeleteVersionDialog
    :open="h.showDeleteModal.value"
    :loading-action="h.loadingAction.value"
    @update:open="h.showDeleteModal.value = $event"
    @confirm="h.confirmDelete"
  />

  <UnsavedChangesDialog
    :open="h.showUnsavedModal.value"
    :version-number="h.unsavedVersionNumber.value"
    :loading-action="h.loadingAction.value"
    @update:open="h.showUnsavedModal.value = $event"
    @save-and-restore="h.saveAndRestore"
    @discard-and-restore="h.discardAndRestore"
  />

  <RestorePreviewDialog
    :open="h.showRestoreModal.value"
    :restore-data="h.restoreData.value"
    :loading-action="h.loadingAction.value"
    @update:open="h.showRestoreModal.value = $event"
    @confirm="h.confirmRestore"
  />
</template>
