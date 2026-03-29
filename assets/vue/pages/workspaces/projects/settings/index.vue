<script setup>
import {
	AlertTriangle,
	Archive,
	Download,
	Loader,
	Monitor,
	Moon,
	RotateCcw,
	Sun,
	Trash2,
	Wrench,
} from "lucide-vue-next";
import { ref, watch } from "vue";
import ColorPickerPopover from "@/vue/components/ColorPickerPopover.vue";
import { Badge } from "@/vue/components/ui/badge/index.js";
import { Button } from "@/vue/components/ui/button/index.js";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/vue/components/ui/dialog/index.js";
import { Input } from "@/vue/components/ui/input/index.js";
import { Label } from "@/vue/components/ui/label/index.js";
import { Progress } from "@/vue/components/ui/progress/index.js";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@/vue/components/ui/select/index.js";
import { Separator } from "@/vue/components/ui/separator/index.js";
import { Switch } from "@/vue/components/ui/switch/index.js";
import { Textarea } from "@/vue/components/ui/textarea/index.js";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	section: { type: String, required: true },
	// General
	projectName: { type: String, default: "" },
	projectDescription: { type: String, default: "" },
	sourceLanguage: { type: Object, default: null },
	sourceLanguageName: { type: String, default: "" },
	themePrimary: { type: String, default: "#00D4CC" },
	themeAccent: { type: String, default: "#E8922F" },
	hasCustomTheme: { type: Boolean, default: false },
	// Localization
	providerApiEndpoint: { type: String, default: "https://api-free.deepl.com" },
	hasApiKey: { type: Boolean, default: false },
	providerUsage: { type: Object, default: null },
	// Members
	members: { type: Array, default: () => [] },
	currentUserId: { type: Number, default: null },
	// Snapshots
	snapshots: { type: Array, default: () => [] },
	canCreateSnapshot: { type: Boolean, default: true },
	restorationInProgress: { type: Boolean, default: false },
	workspaceSlug: { type: String, default: "" },
	projectSlug: { type: String, default: "" },
	// Version Control
	autoSnapshotsEnabled: { type: Boolean, default: false },
	autoVersionFlows: { type: Boolean, default: false },
	autoVersionScenes: { type: Boolean, default: false },
	autoVersionSheets: { type: Boolean, default: false },
	versionUsage: { type: Object, default: null },
});

const live = useLive();

// ── General Section ──────────────────────────────────────────────────
const projectNameLocal = ref(props.projectName);
const projectDescLocal = ref(props.projectDescription);

watch(
	() => props.projectName,
	(v) => {
		projectNameLocal.value = v;
	},
);
watch(
	() => props.projectDescription,
	(v) => {
		projectDescLocal.value = v;
	},
);

function saveProject() {
	live.pushEvent("update_project", {
		project: {
			name: projectNameLocal.value,
			description: projectDescLocal.value,
		},
	});
}

function validateProject() {
	live.pushEvent("validate_project", {
		project: {
			name: projectNameLocal.value,
			description: projectDescLocal.value,
		},
	});
}

// Theme
const localPrimary = ref(props.themePrimary);
const localAccent = ref(props.themeAccent);

watch(
	() => props.themePrimary,
	(v) => {
		localPrimary.value = v;
	},
);
watch(
	() => props.themeAccent,
	(v) => {
		localAccent.value = v;
	},
);

function onPrimaryChange(hex) {
	localPrimary.value = hex;
	live.pushEvent("update_theme_primary", { color: hex });
}

function onAccentChange(hex) {
	localAccent.value = hex;
	live.pushEvent("update_theme_accent", { color: hex });
}

function saveTheme() {
	live.pushEvent("save_theme", {});
}

function resetTheme() {
	live.pushEvent("reset_theme", {});
}

// Theme toggle — write to localStorage then trigger applyTheme via event
function setTheme(theme) {
	if (theme === "system") {
		localStorage.removeItem("phx:theme");
	} else {
		localStorage.setItem("phx:theme", theme);
	}
	// Dispatch the event that app.js listens to for re-applying the theme
	window.dispatchEvent(new CustomEvent("phx:set-theme"));
}

// Repair
const showRepairConfirm = ref(false);

function confirmRepair() {
	showRepairConfirm.value = false;
	live.pushEvent("repair_variable_references", {});
}

// Delete project
const showDeleteConfirm = ref(false);

function confirmDeleteProject() {
	showDeleteConfirm.value = false;
	live.pushEvent("delete_project", {});
}

// ── Localization Section ─────────────────────────────────────────────
const providerApiKey = ref("");
const providerEndpoint = ref(props.providerApiEndpoint);

watch(
	() => props.providerApiEndpoint,
	(v) => {
		providerEndpoint.value = v;
	},
);

function saveProviderConfig() {
	live.pushEvent("save_provider_config", {
		provider: {
			api_key_encrypted: providerApiKey.value,
			api_endpoint: providerEndpoint.value,
		},
	});
	providerApiKey.value = "";
}

function testProviderConnection() {
	live.pushEvent("test_provider_connection", {});
}

function formatNumber(n) {
	if (typeof n !== "number") return String(n);
	return n.toLocaleString();
}

// ── Members Section ──────────────────────────────────────────────────
const inviteEmail = ref("");
const inviteRole = ref("editor");

function sendInvitation() {
	live.pushEvent("send_invitation", {
		invite: {
			email: inviteEmail.value,
			role: inviteRole.value,
		},
	});
	inviteEmail.value = "";
}

function removeMember(id) {
	live.pushEvent("remove_member", { id: String(id) });
}

function memberDisplayName(member) {
	return member.display_name || member.email;
}

function memberInitials(member) {
	const name = member.display_name || member.email;
	return name.substring(0, 2).toUpperCase();
}

// ── Snapshots Section ─────────────��──────────────────────────────────
const snapshotTitle = ref("");
const snapshotDescription = ref("");
const showRestoreDialog = ref(null);
const showDeleteSnapshotDialog = ref(null);

function createSnapshot() {
	live.pushEvent("create_snapshot", {
		snapshot: {
			title: snapshotTitle.value,
			description: snapshotDescription.value,
		},
	});
	snapshotTitle.value = "";
	snapshotDescription.value = "";
}

function restoreSnapshot(id) {
	showRestoreDialog.value = null;
	live.pushEvent("restore_snapshot", { id });
}

function deleteSnapshot(id) {
	showDeleteSnapshotDialog.value = null;
	live.pushEvent("delete_snapshot", { id });
}

function clearStaleLock() {
	live.pushEvent("clear_stale_lock", {});
}

function formatSnapshotSize(bytes) {
	if (typeof bytes !== "number") return "\u2014";
	if (bytes < 1024) return `${bytes} B`;
	if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
	return `${(bytes / 1048576).toFixed(1)} MB`;
}

function formatSnapshotDate(dateStr) {
	if (!dateStr) return "";
	const d = new Date(dateStr);
	return d.toLocaleDateString("en-US", {
		month: "short",
		day: "numeric",
		year: "numeric",
		hour: "2-digit",
		minute: "2-digit",
		timeZone: "UTC",
		timeZoneName: "short",
	});
}

const entityTypeOrder = [
	"sheets",
	"flows",
	"scenes",
	"languages",
	"localized_texts",
	"glossary_entries",
];

function sortedEntityCounts(counts) {
	if (!counts) return [];
	return entityTypeOrder
		.filter((type) => counts[type] && counts[type] > 0)
		.map((type) => ({ type, count: counts[type] }));
}

function downloadUrl(snapshotId) {
	return `/workspaces/${props.workspaceSlug}/projects/${props.projectSlug}/snapshots/${snapshotId}/download`;
}

// ── Version Control Section ──────────────────────────────────────────
const autoSnapshots = ref(props.autoSnapshotsEnabled);
const autoFlows = ref(props.autoVersionFlows);
const autoScenes = ref(props.autoVersionScenes);
const autoSheets = ref(props.autoVersionSheets);

watch(
	() => props.autoSnapshotsEnabled,
	(v) => {
		autoSnapshots.value = v;
	},
);
watch(
	() => props.autoVersionFlows,
	(v) => {
		autoFlows.value = v;
	},
);
watch(
	() => props.autoVersionScenes,
	(v) => {
		autoScenes.value = v;
	},
);
watch(
	() => props.autoVersionSheets,
	(v) => {
		autoSheets.value = v;
	},
);

function saveVersionControl() {
	live.pushEvent("save_version_control", {
		version_control: {
			auto_snapshots_enabled: String(autoSnapshots.value),
			auto_version_flows: String(autoFlows.value),
			auto_version_scenes: String(autoScenes.value),
			auto_version_sheets: String(autoSheets.value),
		},
	});
}

function usagePct(used, limit) {
	if (!limit || limit <= 0) return 0;
	return Math.min(Math.round((used / limit) * 100), 100);
}

// Badge variant helper for roles
const roleBadgeVariant = {
	owner: "default",
	admin: "secondary",
	editor: "outline",
	viewer: "outline",
};
</script>

<template>
  <!-- ═══════════════ GENERAL ═══════════════ -->
  <div v-if="section === 'general'" class="space-y-8">
    <!-- Project Details -->
    <section>
      <form @submit.prevent="saveProject" class="space-y-4">
        <div class="space-y-1.5">
          <Label for="project-name">Project Name</Label>
          <Input
            id="project-name"
            v-model="projectNameLocal"
            required
            @blur="validateProject"
          />
        </div>
        <div class="space-y-1.5">
          <Label for="project-description">Description</Label>
          <Textarea
            id="project-description"
            v-model="projectDescLocal"
            :rows="3"
            @blur="validateProject"
          />
        </div>
        <div class="flex justify-end gap-3 pt-1">
          <Button type="submit">Save Changes</Button>
        </div>
      </form>
    </section>

    <Separator />

    <!-- Source Language -->
    <section class="space-y-4" v-if="sourceLanguage">
      <div>
        <h3 class="text-lg font-semibold mb-1">Source language</h3>
        <p class="text-sm text-muted-foreground">
          Defines the base locale used for source texts and translation workflows in this project.
        </p>
      </div>

      <div class="rounded-lg border border-border bg-muted/30 p-4 space-y-4">
        <div class="rounded-lg border border-border bg-card p-3">
          <div class="flex items-center gap-3">
            <div class="size-8 rounded-md bg-muted flex items-center justify-center text-xs font-bold">
              {{ sourceLanguage.localeCode?.substring(0, 2).toUpperCase() }}
            </div>
            <div class="min-w-0">
              <div class="truncate text-sm font-semibold">{{ sourceLanguageName }}</div>
              <div class="text-xs text-muted-foreground">{{ sourceLanguage.localeCode }}</div>
            </div>
          </div>
        </div>

        <p class="text-xs text-muted-foreground">
          To change the source language, use the localization settings.
        </p>
      </div>
    </section>

    <Separator />

    <!-- Appearance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">Appearance</h3>
      <div class="flex items-center gap-1 rounded-full border border-border bg-muted p-0.5 w-fit">
        <button
          class="flex items-center justify-center size-8 rounded-full transition-colors hover:bg-accent"
          title="System"
          @click="setTheme('system')"
        >
          <Monitor class="size-4 opacity-75" />
        </button>
        <button
          class="flex items-center justify-center size-8 rounded-full transition-colors hover:bg-accent"
          title="Light"
          @click="setTheme('light')"
        >
          <Sun class="size-4 opacity-75" />
        </button>
        <button
          class="flex items-center justify-center size-8 rounded-full transition-colors hover:bg-accent"
          title="Dark"
          @click="setTheme('dark')"
        >
          <Moon class="size-4 opacity-75" />
        </button>
      </div>
    </section>

    <Separator />

    <!-- Theme -->
    <section>
      <h3 class="text-lg font-semibold mb-4">Project Theme</h3>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <div class="flex gap-8 items-start">
          <div>
            <Label class="mb-2 block">Primary</Label>
            <div class="flex items-center gap-3">
              <ColorPickerPopover
                :color="localPrimary"
                @update:color="onPrimaryChange"
              />
              <code class="text-xs text-muted-foreground">{{ localPrimary }}</code>
            </div>
          </div>
          <div>
            <Label class="mb-2 block">Accent</Label>
            <div class="flex items-center gap-3">
              <ColorPickerPopover
                :color="localAccent"
                @update:color="onAccentChange"
              />
              <code class="text-xs text-muted-foreground">{{ localAccent }}</code>
            </div>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button v-if="hasCustomTheme" variant="outline" @click="resetTheme">
            Reset to Default
          </Button>
          <Button @click="saveTheme">Apply Theme</Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Maintenance -->
    <section>
      <h3 class="text-lg font-semibold mb-4">Maintenance</h3>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <p class="text-sm text-muted-foreground mb-3">
          If you renamed sheet shortcuts or variable names, flow nodes may reference old names. Use this to repair them.
        </p>
        <div class="flex justify-end gap-3">
          <Button @click="showRepairConfirm = true">
            <Wrench class="size-4 mr-1.5" />
            Repair variable references
          </Button>
        </div>
      </div>
    </section>

    <Separator />

    <!-- Danger Zone -->
    <section>
      <h3 class="text-lg font-semibold mb-4 text-destructive">Danger Zone</h3>
      <div class="border border-destructive/30 rounded-lg p-4">
        <p class="text-sm text-muted-foreground mb-4">
          Once you delete a project, there is no going back. Please be certain.
        </p>
        <div class="flex justify-end gap-3">
          <Button variant="destructive" @click="showDeleteConfirm = true">
            Delete Project
          </Button>
        </div>
      </div>
    </section>

    <!-- Repair Confirm Dialog -->
    <Dialog v-model:open="showRepairConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Repair variable references?</DialogTitle>
          <DialogDescription>
            This will update node data across the entire project.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showRepairConfirm = false">Cancel</Button>
          <Button @click="confirmRepair">Continue</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- Delete Confirm Dialog -->
    <Dialog v-model:open="showDeleteConfirm">
      <DialogContent>
        <DialogHeader>
          <div class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            <DialogTitle>Delete project?</DialogTitle>
          </div>
          <DialogDescription>
            This action cannot be undone.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showDeleteConfirm = false">Cancel</Button>
          <Button variant="destructive" @click="confirmDeleteProject">Delete</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>

  <!-- ═══════════════ LOCALIZATION ═══════════════ -->
  <div v-else-if="section === 'localization'">
    <div class="rounded-lg border border-border bg-muted/30 p-4">
      <h4 class="font-medium mb-3">Translation Provider (DeepL)</h4>

      <form @submit.prevent="saveProviderConfig" class="space-y-4">
        <div class="space-y-1.5">
          <Label for="api-key">API Key</Label>
          <Input
            id="api-key"
            type="password"
            v-model="providerApiKey"
            :placeholder="hasApiKey ? '••••••••' : ''"
          />
        </div>

        <div class="space-y-1.5">
          <Label for="api-tier">API Tier</Label>
          <Select v-model="providerEndpoint">
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="https://api-free.deepl.com">Free (api-free.deepl.com)</SelectItem>
              <SelectItem value="https://api.deepl.com">Pro (api.deepl.com)</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div class="flex justify-end gap-3 pt-1">
          <Button
            v-if="hasApiKey"
            type="button"
            variant="outline"
            @click="testProviderConnection"
          >
            Test Connection
          </Button>
          <Button type="submit">Save</Button>
        </div>
      </form>

      <div v-if="providerUsage" class="mt-3 text-sm text-muted-foreground">
        Usage: {{ formatNumber(providerUsage.characterCount) }} / {{ formatNumber(providerUsage.characterLimit) }} characters
      </div>
    </div>
  </div>

  <!-- ═��═══════════���═ MEMBERS ═══════════════ -->
  <div v-else-if="section === 'members'" class="space-y-6">
    <div class="space-y-3">
      <div
        v-for="member in members"
        :key="member.id"
        class="flex items-center justify-between p-3 rounded-lg border border-border"
      >
        <div class="flex items-center gap-3">
          <div class="size-9 rounded-full bg-muted flex items-center justify-center text-xs font-medium">
            {{ memberInitials(member) }}
          </div>
          <div>
            <p class="font-medium">{{ memberDisplayName(member) }}</p>
            <p v-if="member.display_name" class="text-sm text-muted-foreground">
              {{ member.email }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <Badge :variant="roleBadgeVariant[member.role] || 'outline'">
            {{ member.role }}
          </Badge>
          <Button
            v-if="member.role !== 'owner' && member.id !== currentUserId"
            variant="ghost"
            size="sm"
            class="text-destructive hover:text-destructive"
            @click="removeMember(member.id)"
          >
            <Trash2 class="size-4" />
          </Button>
        </div>
      </div>
    </div>

    <div class="rounded-lg border border-border bg-muted/30 p-4">
      <h4 class="font-medium mb-3">Request member invitation</h4>
      <p class="text-sm text-muted-foreground mb-3">
        Invitation requests are reviewed by an admin before being sent.
      </p>
      <form @submit.prevent="sendInvitation">
        <div class="flex gap-3 items-end">
          <div class="flex-1 space-y-1.5">
            <Label for="invite-email">Email address</Label>
            <Input
              id="invite-email"
              type="email"
              v-model="inviteEmail"
              placeholder="colleague@example.com"
              required
            />
          </div>
          <div class="w-32 space-y-1.5">
            <Label for="invite-role">Role</Label>
            <Select v-model="inviteRole">
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="editor">Editor</SelectItem>
                <SelectItem value="viewer">Viewer</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-4">
          <Button type="submit">Request Invitation</Button>
        </div>
      </form>
    </div>
  </div>

  <!-- ══��═════��══════ SNAPSHOTS ═══════════════ -->
  <div v-else-if="section === 'snapshots'" class="space-y-6">
    <!-- Restoration banner -->
    <div
      v-if="restorationInProgress"
      class="flex items-center gap-3 rounded-lg border border-yellow-500/30 bg-yellow-500/10 p-4 text-sm"
    >
      <Loader class="size-5 animate-spin text-yellow-600 shrink-0" />
      <span class="flex-1">A restoration is in progress. Please wait for it to complete.</span>
      <Button variant="ghost" size="sm" @click="clearStaleLock">
        Clear stale lock
      </Button>
    </div>

    <!-- Create Snapshot -->
    <section>
      <div class="rounded-lg border border-border bg-muted/30 p-4">
        <form @submit.prevent="createSnapshot" class="space-y-4">
          <div class="space-y-1.5">
            <Label for="snapshot-title">Snapshot Title</Label>
            <Input
              id="snapshot-title"
              v-model="snapshotTitle"
              placeholder="e.g., Before playtest v2"
            />
          </div>
          <div class="space-y-1.5">
            <Label for="snapshot-desc">Description</Label>
            <Textarea
              id="snapshot-desc"
              v-model="snapshotDescription"
              :rows="2"
            />
          </div>
          <div class="flex justify-end gap-3 pt-1">
            <Button
              type="submit"
              :disabled="!canCreateSnapshot || restorationInProgress"
            >
              <Archive class="size-4 mr-1.5" />
              Create Snapshot
            </Button>
          </div>
        </form>
        <p v-if="!canCreateSnapshot" class="text-sm text-destructive mt-2">
          Snapshot limit reached for your plan.
        </p>
      </div>
    </section>

    <Separator />

    <!-- Snapshot List -->
    <section>
      <h3 class="text-lg font-semibold mb-4">Snapshots</h3>

      <!-- Empty state -->
      <div v-if="snapshots.length === 0" class="text-center py-12">
        <Archive class="size-12 mx-auto mb-4 text-muted-foreground/30" />
        <p class="font-medium text-muted-foreground/70">No snapshots yet</p>
        <p class="text-sm text-muted-foreground/50 mt-1">
          Create a snapshot to save a point-in-time backup of your entire project.
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="snapshot in snapshots"
          :key="snapshot.id"
          class="rounded-lg border border-border bg-muted/30 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <Badge variant="secondary" class="text-xs">
                  v{{ snapshot.versionNumber }}
                </Badge>
                <span class="font-medium truncate">
                  {{ snapshot.title || "Untitled Snapshot" }}
                </span>
              </div>
              <p v-if="snapshot.description" class="text-sm text-muted-foreground mt-1">
                {{ snapshot.description }}
              </p>
              <div class="flex flex-wrap gap-3 mt-2 text-xs text-muted-foreground/60">
                <span v-if="snapshot.createdByEmail">
                  {{ snapshot.createdByEmail }}
                </span>
                <span>{{ formatSnapshotDate(snapshot.insertedAt) }}</span>
                <span>{{ formatSnapshotSize(snapshot.snapshotSizeBytes) }}</span>
                <span v-for="ec in sortedEntityCounts(snapshot.entityCounts)" :key="ec.type">
                  {{ ec.count }} {{ ec.type }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                variant="outline"
                size="sm"
                as="a"
                :href="downloadUrl(snapshot.id)"
              >
                <Download class="size-3 mr-1" />
                Download
              </Button>
              <Button
                variant="outline"
                size="sm"
                :disabled="restorationInProgress"
                @click="showRestoreDialog = snapshot.id"
              >
                <RotateCcw class="size-3 mr-1" />
                Restore
              </Button>
              <Button
                variant="outline"
                size="sm"
                class="text-destructive border-destructive/30 hover:bg-destructive/10"
                :disabled="restorationInProgress"
                @click="showDeleteSnapshotDialog = snapshot.id"
              >
                <Trash2 class="size-3" />
              </Button>
            </div>
          </div>

          <!-- Restore dialog -->
          <Dialog
            :open="showRestoreDialog === snapshot.id"
            @update:open="(v) => { if (!v) showRestoreDialog = null; }"
          >
            <DialogContent>
              <DialogHeader>
                <div class="flex items-center gap-2">
                  <RotateCcw class="size-5 text-yellow-500" />
                  <DialogTitle>Restore project snapshot?</DialogTitle>
                </div>
                <DialogDescription>
                  This will overwrite all current project data with the state from this snapshot.
                  A safety snapshot will be created before restoring.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showRestoreDialog = null">Cancel</Button>
                <Button
                  class="bg-yellow-600 hover:bg-yellow-700 text-white"
                  @click="restoreSnapshot(snapshot.id)"
                >
                  Restore
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <!-- Delete dialog -->
          <Dialog
            :open="showDeleteSnapshotDialog === snapshot.id"
            @update:open="(v) => { if (!v) showDeleteSnapshotDialog = null; }"
          >
            <DialogContent>
              <DialogHeader>
                <div class="flex items-center gap-2">
                  <Trash2 class="size-5 text-destructive" />
                  <DialogTitle>Delete snapshot?</DialogTitle>
                </div>
                <DialogDescription>
                  This will permanently delete this snapshot. This action cannot be undone.
                </DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" @click="showDeleteSnapshotDialog = null">Cancel</Button>
                <Button variant="destructive" @click="deleteSnapshot(snapshot.id)">Delete</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </div>
    </section>
  </div>

  <!-- ═══════════════ VERSION CONTROL ═══════════��═══ -->
  <div v-else-if="section === 'version_control'" class="space-y-8">
    <form @submit.prevent="saveVersionControl">
      <!-- Auto Daily Snapshots -->
      <section>
        <h3 class="text-lg font-semibold mb-4">Automatic Snapshots</h3>
        <div class="rounded-lg border border-border bg-muted/30 p-4">
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoSnapshots" @update:checked="(v) => autoSnapshots = v" />
            <div>
              <span class="font-medium">Enable daily automatic snapshots</span>
              <p class="text-sm text-muted-foreground">
                Creates a daily backup at 3:00 AM UTC when changes are detected.
              </p>
            </div>
          </label>
        </div>
      </section>

      <Separator class="my-6" />

      <!-- Per-Entity Auto-Versioning -->
      <section>
        <h3 class="text-lg font-semibold mb-4">Auto-Versioning</h3>
        <p class="text-sm text-muted-foreground mb-4">
          Automatically create version snapshots when editing entities.
        </p>
        <div class="rounded-lg border border-border bg-muted/30 p-4 space-y-4">
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoFlows" @update:checked="(v) => autoFlows = v" />
            <span>Flows</span>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoScenes" @update:checked="(v) => autoScenes = v" />
            <span>Scenes</span>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoSheets" @update:checked="(v) => autoSheets = v" />
            <span>Sheets</span>
          </label>
        </div>
      </section>

      <div class="flex justify-end gap-3 pt-4">
        <Button type="submit">Save Changes</Button>
      </div>
    </form>

    <Separator v-if="versionUsage" />

    <!-- Usage Breakdown -->
    <section v-if="versionUsage">
      <h3 class="text-lg font-semibold mb-4">Usage</h3>
      <div class="space-y-4">
        <div>
          <div class="flex justify-between text-sm mb-1">
            <span>Project Snapshots</span>
            <span class="text-muted-foreground">
              {{ versionUsage.projectSnapshots.used }} / {{ versionUsage.projectSnapshots.limit || "\u221E" }}
            </span>
          </div>
          <Progress
            :model-value="usagePct(versionUsage.projectSnapshots.used, versionUsage.projectSnapshots.limit)"
          />
        </div>
        <div>
          <div class="flex justify-between text-sm mb-1">
            <span>Named Versions</span>
            <span class="text-muted-foreground">
              {{ versionUsage.namedVersions.used }} / {{ versionUsage.namedVersions.limit || "\u221E" }}
            </span>
          </div>
          <Progress
            :model-value="usagePct(versionUsage.namedVersions.used, versionUsage.namedVersions.limit)"
          />
        </div>
      </div>
    </section>
  </div>
</template>
