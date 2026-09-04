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
import { Button } from "@components/ui/button";

interface CountUsageBucket {
  used: number;
  limit: number | null;
}

/**
 * The LiveView still serializes the workspace quotas and storage accounting
 * alongside the project counters; this page only reads the project half.
 * Workspace-wide meters live on Workspace › Plan & usage.
 */
interface UsageLimits {
  plan: {
    key: string;
    name: string;
  };
  project: {
    items: CountUsageBucket;
    projectSnapshots: CountUsageBucket;
    namedVersions: CountUsageBucket;
  };
  itemBreakdown: {
    sheets: number;
    flows: number;
    scenes: number;
    flowNodes: number;
  };
}

interface Meter {
  key: string;
  label: string;
  hint: string;
  used: string;
  limit: string;
  percent: number | null;
  status: SettingsMeterStatus;
}

const { usageLimits, workspacePlanPath = null } = defineProps<{
  usageLimits: UsageLimits;
  workspacePlanPath?: string | null;
}>();

const { locale, t } = useI18n();

function formatCount(value: number): string {
  return new Intl.NumberFormat(locale.value).format(value);
}

function meterStatus(bucket: CountUsageBucket): SettingsMeterStatus {
  if (bucket.limit === null) return "unknown";
  if (bucket.limit <= 0 || bucket.used >= bucket.limit) return "reached";
  if (bucket.used / bucket.limit >= 0.8) return "warning";

  return "available";
}

function meterPercent(bucket: CountUsageBucket): number | null {
  if (bucket.limit === null || bucket.limit <= 0) return null;

  return Math.min(Math.round((bucket.used / bucket.limit) * 100), 100);
}

function meter(key: string, bucket: CountUsageBucket, label: string, hint: string): Meter {
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

const itemsHint = computed(() =>
  t("project_settings.usage_limits.items_breakdown", {
    sheets: formatCount(usageLimits.itemBreakdown.sheets),
    flows: formatCount(usageLimits.itemBreakdown.flows),
    scenes: formatCount(usageLimits.itemBreakdown.scenes),
    nodes: formatCount(usageLimits.itemBreakdown.flowNodes),
  }),
);

const meters = computed<Meter[]>(() => [
  meter(
    "items",
    usageLimits.project.items,
    t("project_settings.usage_limits.rows.items"),
    itemsHint.value,
  ),
  meter(
    "backups",
    usageLimits.project.projectSnapshots,
    t("project_settings.usage_limits.backups"),
    t("project_settings.usage_limits.backups_hint"),
  ),
  meter(
    "named_versions",
    usageLimits.project.namedVersions,
    t("project_settings.usage_limits.rows.named_versions"),
    t("project_settings.usage_limits.named_versions_hint"),
  ),
]);

function statusLabel(status: SettingsMeterStatus): string {
  return t(`project_settings.usage_limits.meter_status.${status}`);
}
</script>

<template>
  <SettingsPage :title="t('project_settings.usage_limits.page_title')">
    <SettingsSection
      :title="t('project_settings.usage_limits.project_limits')"
      :hint="t('project_settings.usage_limits.project_limits_hint')"
    >
      <SettingsMeterRow
        v-for="row in meters"
        :key="row.key"
        :data-testid="`project-usage-meter-${row.key}`"
        :label="row.label"
        :hint="row.hint"
        :used="row.used"
        :limit="row.limit"
        :percent="row.percent"
        :status="row.status"
        :status-label="statusLabel(row.status)"
      >
        <template v-if="row.status === 'reached'" #footer>
          <span>{{ t(`project_settings.usage_limits.reached_hint.${row.key}`) }}</span>
          <Button
            v-if="workspacePlanPath"
            as-child
            variant="link"
            size="sm"
            class="h-auto p-0 text-xs"
          >
            <LiveLink :to="workspacePlanPath">
              {{ t("project_settings.usage_limits.plan_link") }}
            </LiveLink>
          </Button>
        </template>
      </SettingsMeterRow>

      <template #footer>
        {{ t("project_settings.usage_limits.workspace_note") }}
        <LiveLink
          v-if="workspacePlanPath"
          :to="workspacePlanPath"
          class="underline underline-offset-2"
        >
          {{ t("project_settings.usage_limits.workspace_note_link") }}
        </LiveLink>
      </template>
    </SettingsSection>
  </SettingsPage>
</template>
