<script setup lang="ts">
import { ref, watch } from "vue";
import { Button } from "@components/ui/button";
import { Progress } from "@components/ui/progress";
import { Separator } from "@components/ui/separator";
import { Switch } from "@components/ui/switch";
import { useLive } from "@shared/composables/useLive";

interface UsageBucket {
  used: number;
  limit: number | null;
}

interface VersionUsage {
  projectSnapshots: UsageBucket;
  namedVersions: UsageBucket;
}

const {
  autoSnapshotsEnabled = false,
  autoVersionFlows = false,
  autoVersionScenes = false,
  autoVersionSheets = false,
  versionUsage = null,
} = defineProps<{
  autoSnapshotsEnabled?: boolean;
  autoVersionFlows?: boolean;
  autoVersionScenes?: boolean;
  autoVersionSheets?: boolean;
  versionUsage?: VersionUsage | null;
}>();

const live = useLive();

const autoSnapshots = ref(autoSnapshotsEnabled);
const autoFlows = ref(autoVersionFlows);
const autoScenes = ref(autoVersionScenes);
const autoSheets = ref(autoVersionSheets);

watch(
  () => autoSnapshotsEnabled,
  (v) => {
    autoSnapshots.value = v;
  },
);
watch(
  () => autoVersionFlows,
  (v) => {
    autoFlows.value = v;
  },
);
watch(
  () => autoVersionScenes,
  (v) => {
    autoScenes.value = v;
  },
);
watch(
  () => autoVersionSheets,
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

function usagePct(used: number, limit: number | null) {
  if (!limit || limit <= 0) return 0;
  return Math.min(Math.round((used / limit) * 100), 100);
}
</script>

<template>
  <div class="space-y-8">
    <form @submit.prevent="saveVersionControl">
      <!-- Auto Daily Snapshots -->
      <section>
        <h3 class="text-lg font-semibold mb-4">
          {{ $t("project_settings.version_control.auto_snapshots") }}
        </h3>
        <div class="rounded-lg border border-border bg-muted/30 p-4">
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch
              :checked="autoSnapshots"
              @update:checked="(v: boolean) => (autoSnapshots = v)"
            />
            <div>
              <span class="font-medium">{{
                $t("project_settings.version_control.enable_daily")
              }}</span>
              <p class="text-sm text-muted-foreground">
                {{ $t("project_settings.version_control.daily_description") }}
              </p>
            </div>
          </label>
        </div>
      </section>

      <Separator class="my-6" />

      <!-- Per-Entity Auto-Versioning -->
      <section>
        <h3 class="text-lg font-semibold mb-4">
          {{ $t("project_settings.version_control.auto_versioning") }}
        </h3>
        <p class="text-sm text-muted-foreground mb-4">
          {{ $t("project_settings.version_control.auto_versioning_description") }}
        </p>
        <div class="rounded-lg border border-border bg-muted/30 p-4 space-y-4">
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoFlows" @update:checked="(v: boolean) => (autoFlows = v)" />
            <span>{{ $t("project_settings.version_control.flows") }}</span>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoScenes" @update:checked="(v: boolean) => (autoScenes = v)" />
            <span>{{ $t("project_settings.version_control.scenes") }}</span>
          </label>
          <label class="flex items-center gap-3 cursor-pointer">
            <Switch :checked="autoSheets" @update:checked="(v: boolean) => (autoSheets = v)" />
            <span>{{ $t("project_settings.version_control.sheets") }}</span>
          </label>
        </div>
      </section>

      <div class="flex justify-end gap-3 pt-4">
        <Button type="submit">{{ $t("project_settings.version_control.save_changes") }}</Button>
      </div>
    </form>

    <Separator v-if="versionUsage" />

    <!-- Usage Breakdown -->
    <section v-if="versionUsage">
      <h3 class="text-lg font-semibold mb-4">{{ $t("project_settings.version_control.usage") }}</h3>
      <div class="space-y-4">
        <div>
          <div class="flex justify-between text-sm mb-1">
            <span>{{ $t("project_settings.version_control.project_snapshots") }}</span>
            <span class="text-muted-foreground">
              {{ versionUsage.projectSnapshots.used }} /
              {{ versionUsage.projectSnapshots.limit || "\u221E" }}
            </span>
          </div>
          <Progress
            :model-value="
              usagePct(versionUsage.projectSnapshots.used, versionUsage.projectSnapshots.limit)
            "
          />
        </div>
        <div>
          <div class="flex justify-between text-sm mb-1">
            <span>{{ $t("project_settings.version_control.named_versions") }}</span>
            <span class="text-muted-foreground">
              {{ versionUsage.namedVersions.used }} /
              {{ versionUsage.namedVersions.limit || "\u221E" }}
            </span>
          </div>
          <Progress
            :model-value="
              usagePct(versionUsage.namedVersions.used, versionUsage.namedVersions.limit)
            "
          />
        </div>
      </div>
    </section>
  </div>
</template>
