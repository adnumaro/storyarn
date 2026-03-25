<script setup>
import {
	Clock,
	Bookmark,
	BookmarkPlus,
	ChevronDown,
	ChevronRight,
	Columns2,
	RotateCcw,
	Trash2,
	Plus,
	Save,
	X,
	AlertTriangle,
	Info,
	Loader2,
	Image,
	FileText,
	GitBranch,
	Map,
	Puzzle,
	CircleAlert,
} from "lucide-vue-next";
import { Badge } from "@/vue/components/ui/badge";
import { Button } from "@/vue/components/ui/button";
import { Input } from "@/vue/components/ui/input";
import { Label } from "@/vue/components/ui/label";
import { Textarea } from "@/vue/components/ui/textarea";
import {
	Dialog,
	DialogContent,
	DialogHeader,
	DialogTitle,
	DialogDescription,
	DialogFooter,
	DialogClose,
} from "@/vue/components/ui/dialog";
import { useLive } from "@/vue/composables/useLive";
import { useVersionHistory } from "./useVersionHistory";

const props = defineProps({
	versions: { type: Array, default: () => [] },
	namedVersions: { type: Array, default: () => [] },
	autoVersions: { type: Array, default: () => [] },
	hasMore: { type: Boolean, default: false },
	canNameVersion: { type: Boolean, default: false },
	currentVersionId: { type: Number, default: null },
	canEdit: { type: Boolean, default: false },
	loading: { type: Boolean, default: false },
});

const live = useLive();
const h = useVersionHistory();

function changeActionIcon(action) {
	if (action === "added") return "+";
	if (action === "modified") return "~";
	if (action === "removed") return "-";
	return "?";
}

function changeActionColor(action) {
	if (action === "added") return "text-green-600 dark:text-green-400";
	if (action === "modified") return "text-amber-600 dark:text-amber-400";
	if (action === "removed") return "text-red-600 dark:text-red-400";
	return "text-muted-foreground";
}

const conflictIcons = {
	asset: Image,
	sheet: FileText,
	flow: GitBranch,
	scene: Map,
	block: Puzzle,
};

function conflictIcon(type) {
	return conflictIcons[type] || CircleAlert;
}

function conflictLabel(type) {
	const labels = {
		asset: "asset",
		sheet: "sheet",
		flow: "flow",
		scene: "scene",
		block: "block",
	};
	return labels[type] || "entity";
}
</script>

<template>
  <!-- Loading -->
  <div v-if="loading" class="flex items-center justify-center p-16">
    <div class="size-6 border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin" />
  </div>

  <!-- Empty state -->
  <div v-else-if="versions.length === 0" class="rounded-xl border border-border/60 bg-card p-8 text-center">
    <Clock class="size-10 mx-auto text-muted-foreground/20 mb-3" />
    <p class="text-sm font-medium text-muted-foreground mb-1">No versions yet</p>
    <p class="text-xs text-muted-foreground/60 mb-4">
      Create a version to save the current state.
    </p>
    <Button
      v-if="canEdit && canNameVersion"
      size="sm"
      class="gap-1.5"
      @click="h.openCreateModal"
    >
      <Plus class="size-3.5" />
      Create Version
    </Button>
  </div>

  <!-- Main content -->
  <div v-else class="space-y-4">
    <!-- Create button -->
    <div v-if="canEdit && canNameVersion" class="flex justify-end">
      <Button size="sm" class="gap-1.5" @click="h.openCreateModal">
        <Plus class="size-3.5" />
        Create Version
      </Button>
    </div>

    <!-- Named Versions -->
    <div v-if="namedVersions.length > 0" class="space-y-2">
      <h3 class="text-xs font-medium text-muted-foreground flex items-center gap-1.5">
        <Bookmark class="size-3.5" />
        Named Versions
      </h3>
      <div
        v-for="version in namedVersions"
        :key="version.id"
        :class="[
          'flex items-start gap-2.5 p-3 rounded-lg group',
          version.id === currentVersionId
            ? 'bg-primary/10 border border-primary/30'
            : 'hover:bg-muted'
        ]"
      >
        <div :class="[
          'flex-shrink-0 size-7 rounded-full flex items-center justify-center mt-0.5',
          version.id === currentVersionId
            ? 'bg-primary text-primary-foreground'
            : 'bg-amber-500/15 text-amber-600 dark:text-amber-400'
        ]">
          <Bookmark class="size-3.5" />
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center justify-between gap-1">
            <div class="flex items-center gap-1.5 min-w-0">
              <span class="text-sm font-medium truncate">
                {{ version.title || version.changeSummary || "No summary" }}
              </span>
              <Badge v-if="version.id === currentVersionId" variant="default" class="text-[10px] px-1.5 py-0 rounded-full shrink-0">
                Current
              </Badge>
              <Badge variant="outline" class="text-[10px] px-1.5 py-0 rounded-full shrink-0">
                v{{ version.versionNumber }}
              </Badge>
            </div>
            <div class="flex-shrink-0 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                title="Compare with current"
                @click="live.pushEvent('compare_version', { version_number: version.versionNumber })"
              >
                <Columns2 class="size-3.5" />
              </button>
              <button
                v-if="canEdit && version.id !== currentVersionId"
                class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                title="Restore this version"
                @click="h.previewRestore(version.versionNumber)"
              >
                <Loader2 v-if="h.loadingAction.value === `restore-${version.versionNumber}`" class="size-3.5 animate-spin" />
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
              <ChevronDown v-if="h.expandedChangelogs.value.has(version.versionNumber)" class="size-3" />
              <ChevronRight v-else class="size-3" />
              <span class="flex items-center gap-1.5">
                <span v-if="version.changeDetails.stats?.added > 0" class="text-green-600 dark:text-green-400">
                  +{{ version.changeDetails.stats.added }}
                </span>
                <span v-if="version.changeDetails.stats?.modified > 0" class="text-amber-600 dark:text-amber-400">
                  ~{{ version.changeDetails.stats.modified }}
                </span>
                <span v-if="version.changeDetails.stats?.removed > 0" class="text-red-600 dark:text-red-400">
                  -{{ version.changeDetails.stats.removed }}
                </span>
              </span>
            </button>
            <div v-if="h.expandedChangelogs.value.has(version.versionNumber)" class="mt-1.5 space-y-0.5 ml-0.5">
              <div
                v-for="(change, ci) in version.changeDetails.changes"
                :key="ci"
                class="flex items-start gap-1.5 text-[11px]"
              >
                <span :class="['flex-shrink-0 font-mono font-bold leading-4', changeActionColor(change.action)]">
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
        {{ autoVersions.length }} auto-save{{ autoVersions.length === 1 ? '' : 's' }}
      </button>
      <div v-if="h.showAutoVersions.value" class="space-y-1">
        <div
          v-for="version in autoVersions"
          :key="version.id"
          :class="[
            'flex items-start gap-2.5 p-3 rounded-lg group',
            version.id === currentVersionId
              ? 'bg-primary/10 border border-primary/30'
              : 'hover:bg-muted'
          ]"
        >
          <div :class="[
            'flex-shrink-0 size-7 rounded-full flex items-center justify-center mt-0.5 text-[10px] font-semibold',
            version.id === currentVersionId
              ? 'bg-primary text-primary-foreground'
              : 'bg-muted text-foreground'
          ]">
            v{{ version.versionNumber }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between gap-1">
              <div class="flex items-center gap-1.5 min-w-0">
                <span class="text-sm text-foreground truncate">
                  {{ version.changeSummary || "No summary" }}
                </span>
                <Badge v-if="version.id === currentVersionId" variant="default" class="text-[10px] px-1.5 py-0 rounded-full shrink-0">
                  Current
                </Badge>
              </div>
              <div class="flex-shrink-0 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                  title="Compare with current"
                  @click="live.pushEvent('compare_version', { version_number: version.versionNumber })"
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
                  <Loader2 v-if="h.loadingAction.value === `restore-${version.versionNumber}`" class="size-3.5 animate-spin" />
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
                <ChevronDown v-if="h.expandedChangelogs.value.has(version.versionNumber)" class="size-3" />
                <ChevronRight v-else class="size-3" />
                <span class="flex items-center gap-1.5">
                  <span v-if="version.changeDetails.stats?.added > 0" class="text-green-600 dark:text-green-400">
                    +{{ version.changeDetails.stats.added }}
                  </span>
                  <span v-if="version.changeDetails.stats?.modified > 0" class="text-amber-600 dark:text-amber-400">
                    ~{{ version.changeDetails.stats.modified }}
                  </span>
                  <span v-if="version.changeDetails.stats?.removed > 0" class="text-red-600 dark:text-red-400">
                    -{{ version.changeDetails.stats.removed }}
                  </span>
                </span>
              </button>
              <div v-if="h.expandedChangelogs.value.has(version.versionNumber)" class="mt-1.5 space-y-0.5 ml-0.5">
                <div
                  v-for="(change, ci) in version.changeDetails.changes"
                  :key="ci"
                  class="flex items-start gap-1.5 text-[11px]"
                >
                  <span :class="['flex-shrink-0 font-mono font-bold leading-4', changeActionColor(change.action)]">
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
      Load more
    </Button>
  </div>

  <!-- Create Version Dialog -->
  <Dialog v-model:open="h.showCreateModal.value">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>Create Version</DialogTitle>
        <DialogDescription>Save the current state as a named version.</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="h.submitCreate" class="space-y-4">
        <div class="space-y-2">
          <Label for="version-title">Title</Label>
          <Input id="version-title" v-model="h.createTitle.value" placeholder="e.g., Before major refactor" required autofocus />
        </div>
        <div class="space-y-2">
          <Label for="version-description">Description (optional)</Label>
          <Textarea id="version-description" v-model="h.createDescription.value" :rows="3" placeholder="Describe what this version captures..." />
        </div>
        <DialogFooter>
          <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
          <Button type="submit" :disabled="!h.createTitle.value.trim() || h.loadingAction.value === 'create'">
            <Loader2 v-if="h.loadingAction.value === 'create'" class="size-4 animate-spin mr-1" />
            <Save v-else class="size-4 mr-1" />
            Create Version
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>

  <!-- Promote Version Dialog -->
  <Dialog v-model:open="h.showPromoteModal.value">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>Name This Version</DialogTitle>
        <DialogDescription>Give this auto-save a name to make it a milestone.</DialogDescription>
      </DialogHeader>
      <form @submit.prevent="h.submitPromote" class="space-y-4">
        <div class="space-y-2">
          <Label for="promote-title">Title</Label>
          <Input id="promote-title" v-model="h.promoteTitle.value" :placeholder="h.promoteVersion.value?.changeSummary || 'e.g., Before major refactor'" required autofocus />
        </div>
        <div class="space-y-2">
          <Label for="promote-description">Description (optional)</Label>
          <Textarea id="promote-description" v-model="h.promoteDescription.value" :rows="3" placeholder="Describe what this version captures..." />
        </div>
        <DialogFooter>
          <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
          <Button type="submit" :disabled="!h.promoteTitle.value.trim() || h.loadingAction.value === 'promote'">
            <Loader2 v-if="h.loadingAction.value === 'promote'" class="size-4 animate-spin mr-1" />
            <BookmarkPlus v-else class="size-4 mr-1" />
            Name Version
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>

  <!-- Delete Confirm Dialog -->
  <Dialog v-model:open="h.showDeleteModal.value">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-destructive" />
          Delete version?
        </DialogTitle>
        <DialogDescription>Are you sure you want to delete this version? This action cannot be undone.</DialogDescription>
      </DialogHeader>
      <DialogFooter>
        <DialogClose as-child><Button variant="ghost" type="button">Cancel</Button></DialogClose>
        <Button variant="destructive" :disabled="h.loadingAction.value === 'delete'" @click="h.confirmDelete">
          <Loader2 v-if="h.loadingAction.value === 'delete'" class="size-4 animate-spin mr-1" />
          <Trash2 v-else class="size-4 mr-1" />
          Delete
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <!-- Unsaved Changes Dialog -->
  <Dialog v-model:open="h.showUnsavedModal.value">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <AlertTriangle class="size-5 text-amber-500" />
          Unsaved changes
        </DialogTitle>
        <DialogDescription>
          You have changes that aren't saved in any version.
          Restoring to v{{ h.unsavedVersionNumber.value }} will overwrite them.
        </DialogDescription>
      </DialogHeader>
      <p class="text-sm text-muted-foreground">What would you like to do with your current changes?</p>
      <div class="flex flex-col gap-2">
        <Button class="w-full justify-start gap-2" :disabled="h.loadingAction.value === 'save-restore'" @click="h.saveAndRestore">
          <Loader2 v-if="h.loadingAction.value === 'save-restore'" class="size-4 animate-spin" />
          <Save v-else class="size-4" />
          Save current state, then restore
        </Button>
        <Button variant="outline" class="w-full justify-start gap-2 border-amber-500/30 text-amber-600 hover:bg-amber-500/10" :disabled="h.loadingAction.value === 'discard-restore'" @click="h.discardAndRestore">
          <Loader2 v-if="h.loadingAction.value === 'discard-restore'" class="size-4 animate-spin" />
          <Trash2 v-else class="size-4" />
          Discard changes and restore
        </Button>
        <Button variant="ghost" class="w-full justify-start gap-2" @click="h.showUnsavedModal.value = false">
          <X class="size-4" />
          Cancel
        </Button>
      </div>
    </DialogContent>
  </Dialog>

  <!-- Restore Preview Dialog -->
  <Dialog v-model:open="h.showRestoreModal.value">
    <DialogContent class="sm:max-w-lg">
      <DialogHeader>
        <DialogTitle class="flex items-center gap-2">
          <RotateCcw class="size-5" />
          Restore to version {{ h.restoreData.value?.versionNumber }}
        </DialogTitle>
      </DialogHeader>
      <template v-if="h.restoreData.value">
        <div v-if="h.restoreData.value.report.hasConflicts" class="space-y-3">
          <div v-if="h.restoreData.value.report.shortcutCollision" class="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 border border-amber-500/20">
            <AlertTriangle class="size-4 text-amber-500 shrink-0 mt-0.5" />
            <span class="text-sm">Shortcut collision — will be renamed to "{{ h.restoreData.value.report.resolvedShortcut }}"</span>
          </div>
          <div v-if="h.restoreData.value.report.conflicts.length > 0" class="space-y-2">
            <p class="text-sm font-medium text-amber-600 flex items-center gap-1.5">
              <AlertTriangle class="size-4" />
              Some referenced entities no longer exist:
            </p>
            <div v-for="(conflict, ci) in h.restoreData.value.report.conflicts" :key="ci" class="bg-muted/50 rounded-lg p-3">
              <div class="flex items-center gap-2 text-sm font-medium">
                <component :is="conflictIcon(conflict.type)" class="size-4 text-amber-500" />
                <span>Missing {{ conflictLabel(conflict.type) }} (ID: {{ conflict.id }})</span>
              </div>
              <ul class="mt-1 ml-6 text-xs text-muted-foreground list-disc">
                <li v-for="(ctx, j) in conflict.contexts" :key="j">{{ ctx }}</li>
              </ul>
            </div>
          </div>
          <p class="text-sm text-muted-foreground">
            <template v-if="h.restoreData.value.skipPreSnapshot">Missing references will be cleared.</template>
            <template v-else>Missing references will be cleared. Current state will be saved as a backup.</template>
          </p>
        </div>
        <p v-else class="text-muted-foreground">This will restore to version {{ h.restoreData.value.versionNumber }}.</p>
        <div v-if="h.restoreData.value.report.autoResolved?.length > 0" class="bg-blue-500/10 border border-blue-500/20 rounded-lg p-3">
          <p class="text-sm font-medium text-blue-600 dark:text-blue-400 mb-1 flex items-center gap-1.5">
            <Info class="size-4" />
            Auto-resolved:
          </p>
          <ul class="text-xs text-muted-foreground list-disc ml-5">
            <li v-for="(item, i) in h.restoreData.value.report.autoResolved" :key="i">{{ item }}</li>
          </ul>
        </div>
      </template>
      <DialogFooter>
        <Button variant="ghost" @click="h.showRestoreModal.value = false">Cancel</Button>
        <Button
          :class="h.restoreData.value?.report?.hasConflicts ? 'bg-amber-600 hover:bg-amber-700' : ''"
          :disabled="h.loadingAction.value === 'confirm-restore'"
          @click="h.confirmRestore"
        >
          <Loader2 v-if="h.loadingAction.value === 'confirm-restore'" class="size-4 animate-spin mr-1" />
          <RotateCcw v-else class="size-4 mr-1" />
          {{ h.restoreData.value?.report?.hasConflicts ? 'Restore anyway' : 'Restore' }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
