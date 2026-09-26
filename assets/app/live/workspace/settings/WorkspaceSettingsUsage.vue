<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import {
  METER_WARNING_RATIO,
  SettingsMeterRow,
  SettingsPage,
  SettingsRow,
  SettingsSection,
  type SettingsMeterStatus,
} from "@components/settings";
import { Button } from "@components/ui/button";
import {
  formatBytes,
  storagePercentage,
  type ByteCount,
  type WorkspaceStorageUsage,
} from "@shared/utils/storage-accounting";

interface CountBucket {
  used: number;
  /** `null` when the plan does not define the limit. */
  limit: number | "unlimited" | null;
}

interface StorageBucket {
  used: ByteCount;
  limit: ByteCount | null;
}

interface WorkspaceUsage {
  projects: CountBucket;
  storageBytes: StorageBucket;
  storage: WorkspaceStorageUsage;
}

interface Meter {
  key: string;
  label: string;
  hint: string;
  used: string;
  limit: string | null;
  percent: number | null;
  status: SettingsMeterStatus;
}

const { usage, planPath = null } = defineProps<{
  usage: WorkspaceUsage;
  /** Plan & billing, sent only to the workspace owner, whose plan sets these limits. */
  planPath?: string | null;
}>();

const { locale, t } = useI18n();

function countMeter(key: string, bucket: CountBucket, hint: string): Meter {
  const format = new Intl.NumberFormat(locale.value);
  const meter = {
    key,
    label: t(`settings.workspace.usage.meters.${key}`),
    hint,
    used: format.format(bucket.used),
    limit: null,
    percent: null,
  };

  if (bucket.limit === "unlimited") return { ...meter, status: "unlimited" };
  if (bucket.limit === null) return { ...meter, status: "unknown" };

  const percent = bucket.limit > 0 ? Math.min((bucket.used / bucket.limit) * 100, 100) : 100;
  let status: SettingsMeterStatus = "available";
  if (bucket.used >= bucket.limit) status = "reached";
  else if (percent >= METER_WARNING_RATIO * 100) status = "warning";

  return { ...meter, limit: format.format(bucket.limit), percent, status };
}

function storageStatus(state: string, progressPercent: number): SettingsMeterStatus {
  if (state === "over_limit" || state === "zero") return "reached";
  if (state === "unlimited") return "unlimited";
  if (state === "unknown") return "unknown";
  if (progressPercent >= METER_WARNING_RATIO * 100) return "warning";
  return "available";
}

const storageMeter = computed<Meter>(() => {
  const percentage = storagePercentage(
    usage.storage.totalAccountedBytes,
    usage.storageBytes.limit,
    usage.storage.limitKind,
  );
  const status = storageStatus(percentage.state, percentage.progressPercent);

  return {
    key: "storage",
    label: t("settings.workspace.usage.meters.storage"),
    hint: t("settings.workspace.usage.storage_breakdown", {
      assets: formatBytes(usage.storage.currentAssetsBytes, locale.value),
      trash: formatBytes(usage.storage.assetTrashBytes, locale.value),
      backups: formatBytes(usage.storage.fullSnapshotsBytes, locale.value),
      reservations: formatBytes(usage.storage.activeReservationsBytes, locale.value),
    }),
    used: formatBytes(usage.storage.totalAccountedBytes, locale.value),
    limit:
      usage.storageBytes.limit === null
        ? null
        : formatBytes(usage.storageBytes.limit, locale.value),
    percent:
      percentage.state === "unlimited" || percentage.state === "unknown"
        ? null
        : percentage.progressPercent,
    status,
  };
});

const meters = computed<Meter[]>(() => [
  countMeter("projects", usage.projects, t("settings.workspace.usage.hints.projects")),
  storageMeter.value,
]);
</script>

<template>
  <SettingsPage :title="t('settings.workspace.usage.title')">
    <SettingsSection
      :title="t('settings.workspace.usage.limits_section')"
      :hint="t('settings.workspace.usage.limits_hint')"
    >
      <SettingsMeterRow
        v-for="meter in meters"
        :key="meter.key"
        :data-testid="`workspace-usage-meter-${meter.key}`"
        :label="meter.label"
        :hint="meter.hint"
        :used="meter.used"
        :limit="meter.limit"
        :percent="meter.percent"
        :status="meter.status"
        :status-label="t(`settings.workspace.usage.status.${meter.status}`)"
      />

      <template #footer>{{ t("settings.workspace.usage.footer") }}</template>
    </SettingsSection>

    <SettingsSection v-if="planPath" :title="t('settings.workspace.usage.plan_section')">
      <SettingsRow
        :label="t('settings.workspace.usage.plan_label')"
        :hint="t('settings.workspace.usage.plan_hint')"
      >
        <Button as-child variant="outline" size="sm">
          <LiveLink :to="planPath" data-testid="workspace-usage-plan-link">
            {{ t("settings.workspace.usage.plan_link") }}
          </LiveLink>
        </Button>
      </SettingsRow>
    </SettingsSection>
  </SettingsPage>
</template>
