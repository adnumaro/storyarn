<script setup>
import { ref, watch } from "vue";
import { Button } from "@/vue/components/ui/button/index.js";
import { Progress } from "@/vue/components/ui/progress/index.js";
import { Separator } from "@/vue/components/ui/separator/index.js";
import { Switch } from "@/vue/components/ui/switch/index.js";
import { useLive } from "@/vue/composables/useLive.js";

const props = defineProps({
	autoSnapshotsEnabled: { type: Boolean, default: false },
	autoVersionFlows: { type: Boolean, default: false },
	autoVersionScenes: { type: Boolean, default: false },
	autoVersionSheets: { type: Boolean, default: false },
	versionUsage: { type: Object, default: null },
});

const live = useLive();

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
</script>

<template>
  <div class="space-y-8">
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
