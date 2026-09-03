<script setup lang="ts">
import { Clapperboard, FileText, Workflow } from "@lucide/vue";
import { computed, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import SaveIndicator from "@components/SaveIndicator.vue";
import {
  SettingsMeterRow,
  SettingsPage,
  SettingsRow,
  SettingsSection,
  type SettingsMeterStatus,
} from "@components/settings";
import { Button } from "@components/ui/button";
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
  autoVersionFlows = false,
  autoVersionScenes = false,
  autoVersionSheets = false,
  versionUsage = null,
  usagePath = null,
  saveStatus = "idle",
} = defineProps<{
  autoVersionFlows?: boolean;
  autoVersionScenes?: boolean;
  autoVersionSheets?: boolean;
  versionUsage?: VersionUsage | null;
  usagePath?: string | null;
  saveStatus?: "idle" | "saving" | "saved";
}>();

const live = useLive();
const { locale, t } = useI18n();

// ---------------------------------------------------------------------------
// Auto-versioning: each switch saves on toggle.
// ---------------------------------------------------------------------------
type EntityKey = "flows" | "scenes" | "sheets";

const autoFlows = ref(autoVersionFlows);
const autoScenes = ref(autoVersionScenes);
const autoSheets = ref(autoVersionSheets);

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

const entityRows: { key: EntityKey; icon: Component }[] = [
  { key: "flows", icon: Workflow },
  { key: "scenes", icon: Clapperboard },
  { key: "sheets", icon: FileText },
];

// A toggle is pending until the LiveView answers: the switch shows the pending
// value meanwhile, later toggles build their payload from the pending state,
// and a rejected or lost save drops the pending value so the server state
// shows again.
const pending = ref<Partial<Record<EntityKey, boolean>>>({});

function serverValue(key: EntityKey): boolean {
  if (key === "flows") return autoFlows.value;
  if (key === "scenes") return autoScenes.value;
  return autoSheets.value;
}

function displayedValue(key: EntityKey): boolean {
  return pending.value[key] ?? serverValue(key);
}

function clearPending(key: EntityKey): void {
  const { [key]: _cleared, ...rest } = pending.value;
  pending.value = rest;
}

function toggle(key: EntityKey, value: boolean): void {
  pending.value = { ...pending.value, [key]: value };

  const payload = {
    auto_version_flows: String(displayedValue("flows")),
    auto_version_scenes: String(displayedValue("scenes")),
    auto_version_sheets: String(displayedValue("sheets")),
  };

  live.pushEvent(
    "save_version_control",
    { version_control: payload },
    () => clearPending(key),
    () => clearPending(key),
  );
}

// ---------------------------------------------------------------------------
// Quota
// ---------------------------------------------------------------------------
interface Meter {
  key: string;
  label: string;
  hint: string;
  used: string;
  limit: string;
  percent: number | null;
  status: SettingsMeterStatus;
}

function formatCount(value: number): string {
  return new Intl.NumberFormat(locale.value).format(value);
}

function meterStatus(bucket: UsageBucket): SettingsMeterStatus {
  if (bucket.limit === null) return "unknown";
  if (bucket.limit <= 0 || bucket.used >= bucket.limit) return "reached";
  if (bucket.used / bucket.limit >= 0.8) return "warning";

  return "available";
}

function meterPercent(bucket: UsageBucket): number | null {
  if (bucket.limit === null || bucket.limit <= 0) return null;

  return Math.min(Math.round((bucket.used / bucket.limit) * 100), 100);
}

function meter(key: string, bucket: UsageBucket, label: string, hint: string): Meter {
  return {
    key,
    label,
    hint,
    used: formatCount(bucket.used),
    limit:
      bucket.limit === null
        ? t("project_settings.usage_limits.status.unknown")
        : formatCount(bucket.limit),
    percent: meterPercent(bucket),
    status: meterStatus(bucket),
  };
}

const meters = computed<Meter[]>(() => {
  if (!versionUsage) return [];

  return [
    meter(
      "backups",
      versionUsage.projectSnapshots,
      t("project_settings.version_control.backups"),
      t("project_settings.version_control.backups_hint"),
    ),
    meter(
      "named_versions",
      versionUsage.namedVersions,
      t("project_settings.version_control.named_versions"),
      t("project_settings.version_control.named_versions_hint"),
    ),
  ];
});

function statusLabel(status: SettingsMeterStatus): string {
  return t(`project_settings.usage_limits.meter_status.${status}`);
}
</script>

<template>
  <SettingsPage :title="t('project_settings.version_control.page_title')">
    <template #actions>
      <SaveIndicator :status="saveStatus" />
    </template>

    <SettingsSection
      :title="t('project_settings.version_control.auto_versioning')"
      :hint="t('project_settings.version_control.auto_versioning_description')"
    >
      <SettingsRow
        v-for="row in entityRows"
        :key="row.key"
        :label="t(`project_settings.version_control.${row.key}`)"
        :hint="t(`project_settings.version_control.${row.key}_hint`)"
        :html-for="`auto-version-${row.key}`"
      >
        <template #leading>
          <component
            :is="row.icon"
            class="size-4 shrink-0 text-muted-foreground"
            aria-hidden="true"
          />
        </template>
        <Switch
          :id="`auto-version-${row.key}`"
          :model-value="displayedValue(row.key)"
          @update:model-value="(value) => toggle(row.key, value)"
        />
      </SettingsRow>
    </SettingsSection>

    <SettingsSection
      v-if="versionUsage"
      :title="t('project_settings.version_control.quota')"
      :hint="t('project_settings.version_control.quota_hint')"
    >
      <SettingsMeterRow
        v-for="row in meters"
        :key="row.key"
        :data-testid="`version-control-meter-${row.key}`"
        :label="row.label"
        :hint="row.hint"
        :used="row.used"
        :limit="row.limit"
        :percent="row.percent"
        :status="row.status"
        :status-label="statusLabel(row.status)"
      />

      <template v-if="usagePath" #footer>
        <Button as-child variant="link" size="sm" class="h-auto p-0 text-xs">
          <LiveLink :to="usagePath">{{
            t("project_settings.version_control.view_usage")
          }}</LiveLink>
        </Button>
      </template>
    </SettingsSection>
  </SettingsPage>
</template>
