<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import LiveLink from "@components/navigation/LiveLink.vue";
import {
  SettingsMeterRow,
  SettingsPage,
  SettingsSection,
  type SettingsMeterStatus,
} from "@components/settings";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  formatBytes,
  storagePercentage,
  type ByteCount,
  type WorkspaceStorageUsage,
} from "@shared/utils/storage-accounting";

interface CountBucket {
  used: number;
  limit: number | null;
}

interface StorageBucket {
  used: ByteCount;
  limit: ByteCount | null;
}

interface WorkspaceUsage {
  plan: { key: string };
  projects: CountBucket;
  members: CountBucket;
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

const { usage, contactPath } = defineProps<{
  usage: WorkspaceUsage;
  contactPath: string;
}>();

const { locale, t, te } = useI18n();

const planName = computed(() => {
  const key = `settings.workspace.plan.plans.${usage.plan.key}`;
  return te(key) ? t(key) : usage.plan.key;
});

function countMeter(key: string, bucket: CountBucket, hint: string): Meter {
  const format = new Intl.NumberFormat(locale.value);
  let status: SettingsMeterStatus = "unlimited";
  let percent: number | null = null;

  if (bucket.limit !== null) {
    percent = bucket.limit > 0 ? Math.min((bucket.used / bucket.limit) * 100, 100) : 100;
    if (bucket.used >= bucket.limit) status = "reached";
    else if (percent >= 90) status = "warning";
    else status = "available";
  }

  return {
    key,
    label: t(`settings.workspace.plan.meters.${key}`),
    hint,
    used: format.format(bucket.used),
    limit: bucket.limit === null ? null : format.format(bucket.limit),
    percent,
    status,
  };
}

function storageStatus(state: string, progressPercent: number): SettingsMeterStatus {
  if (state === "over_limit" || state === "zero") return "reached";
  if (state === "unlimited") return "unlimited";
  if (state === "unknown") return "unknown";
  if (progressPercent >= 90) return "warning";
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
    label: t("settings.workspace.plan.meters.storage"),
    hint: t("settings.workspace.plan.storage_breakdown", {
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
  countMeter("projects", usage.projects, t("settings.workspace.plan.hints.projects")),
  countMeter("members", usage.members, t("settings.workspace.plan.hints.members")),
  storageMeter.value,
]);
</script>

<template>
  <SettingsPage :title="t('settings.workspace.plan.title')">
    <SettingsSection :title="t('settings.workspace.plan.plan_section')">
      <div
        class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3.5 sm:grid-cols-[minmax(0,1fr)_auto]"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-medium" data-testid="workspace-plan-name">{{ planName }}</span>
            <Badge>{{ t("settings.workspace.plan.current_plan") }}</Badge>
          </div>
          <div class="text-[13px] text-muted-foreground">
            {{ t("settings.workspace.plan.plan_hint") }}
          </div>
        </div>
        <div class="flex items-center justify-end">
          <Button as-child variant="outline" size="sm">
            <LiveLink :to="contactPath">{{ t("settings.workspace.plan.talk_to_us") }}</LiveLink>
          </Button>
        </div>
      </div>
    </SettingsSection>

    <SettingsSection
      :title="t('settings.workspace.plan.limits_section')"
      :hint="t('settings.workspace.plan.limits_hint')"
    >
      <SettingsMeterRow
        v-for="meter in meters"
        :key="meter.key"
        :data-testid="`workspace-plan-meter-${meter.key}`"
        :label="meter.label"
        :hint="meter.hint"
        :used="meter.used"
        :limit="meter.limit"
        :percent="meter.percent"
        :status="meter.status"
        :status-label="t(`settings.workspace.plan.status.${meter.status}`)"
      />

      <template #footer>{{ t("settings.workspace.plan.footer") }}</template>
    </SettingsSection>
  </SettingsPage>
</template>
