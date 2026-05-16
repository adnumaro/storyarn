<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Progress } from "@components/ui/progress";
import { Separator } from "@components/ui/separator";

interface UsageBucket {
  used: number;
  limit: number | null;
}

interface UsageLimits {
  plan: {
    key: string;
    name: string;
  };
  project: {
    items: UsageBucket;
    projectSnapshots: UsageBucket;
    namedVersions: UsageBucket;
  };
  workspace: {
    projects: UsageBucket;
    members: UsageBucket;
    storageBytes: UsageBucket;
  };
  itemBreakdown: {
    sheets: number;
    flows: number;
    scenes: number;
    flowNodes: number;
  };
  storage: {
    projectBytes: number;
    assetCount: number;
  };
}

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";
type ValueFormat = "count" | "bytes";

interface LimitRow {
  key: string;
  label: string;
  description: string;
  bucket: UsageBucket;
  format: ValueFormat;
}

const { usageLimits } = defineProps<{
  usageLimits: UsageLimits;
}>();

const { t } = useI18n();

const projectRows = computed<LimitRow[]>(() => [
  {
    key: "items",
    label: t("project_settings.usage_limits.rows.items"),
    description: t("project_settings.usage_limits.descriptions.items"),
    bucket: usageLimits.project.items,
    format: "count",
  },
  {
    key: "projectSnapshots",
    label: t("project_settings.usage_limits.rows.project_snapshots"),
    description: t("project_settings.usage_limits.descriptions.project_snapshots"),
    bucket: usageLimits.project.projectSnapshots,
    format: "count",
  },
  {
    key: "namedVersions",
    label: t("project_settings.usage_limits.rows.named_versions"),
    description: t("project_settings.usage_limits.descriptions.named_versions"),
    bucket: usageLimits.project.namedVersions,
    format: "count",
  },
]);

const workspaceRows = computed<LimitRow[]>(() => [
  {
    key: "storageBytes",
    label: t("project_settings.usage_limits.rows.storage"),
    description: t("project_settings.usage_limits.descriptions.storage"),
    bucket: usageLimits.workspace.storageBytes,
    format: "bytes",
  },
  {
    key: "projects",
    label: t("project_settings.usage_limits.rows.projects"),
    description: t("project_settings.usage_limits.descriptions.projects"),
    bucket: usageLimits.workspace.projects,
    format: "count",
  },
  {
    key: "members",
    label: t("project_settings.usage_limits.rows.members"),
    description: t("project_settings.usage_limits.descriptions.members"),
    bucket: usageLimits.workspace.members,
    format: "count",
  },
]);

const itemBreakdown = computed(() => [
  {
    label: t("project_settings.usage_limits.breakdown.sheets"),
    value: usageLimits.itemBreakdown.sheets,
  },
  {
    label: t("project_settings.usage_limits.breakdown.flows"),
    value: usageLimits.itemBreakdown.flows,
  },
  {
    label: t("project_settings.usage_limits.breakdown.scenes"),
    value: usageLimits.itemBreakdown.scenes,
  },
  {
    label: t("project_settings.usage_limits.breakdown.flow_nodes"),
    value: usageLimits.itemBreakdown.flowNodes,
  },
]);

function usageRatio(bucket: UsageBucket) {
  if (!bucket.limit || bucket.limit <= 0) return 0;
  return bucket.used / bucket.limit;
}

function usagePercent(bucket: UsageBucket) {
  if (!bucket.limit || bucket.limit <= 0) return 0;
  return Math.min(Math.round(usageRatio(bucket) * 100), 100);
}

function statusFor(bucket: UsageBucket): { label: string; variant: BadgeVariant } {
  if (!bucket.limit || bucket.limit <= 0) {
    return { label: t("project_settings.usage_limits.status.no_limit"), variant: "outline" };
  }

  const ratio = usageRatio(bucket);

  if (ratio >= 1) {
    return {
      label: t("project_settings.usage_limits.status.limit_reached"),
      variant: "destructive",
    };
  }

  if (ratio >= 0.8) {
    return { label: t("project_settings.usage_limits.status.near_limit"), variant: "secondary" };
  }

  return { label: t("project_settings.usage_limits.status.available"), variant: "outline" };
}

function formatValue(value: number, format: ValueFormat) {
  return format === "bytes" ? formatBytes(value) : new Intl.NumberFormat().format(value);
}

function formatLimit(bucket: UsageBucket, format: ValueFormat) {
  return bucket.limit
    ? formatValue(bucket.limit, format)
    : t("project_settings.usage_limits.status.no_limit");
}

function formatBytes(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";

  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let index = 0;

  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }

  const maximumFractionDigits = value >= 10 || index === 0 ? 0 : 1;
  const formatted = new Intl.NumberFormat(undefined, { maximumFractionDigits }).format(value);

  return `${formatted} ${units[index]}`;
}
</script>

<template>
  <div class="space-y-8">
    <section class="rounded-lg border border-border bg-muted/30 p-4">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h3 class="text-base font-semibold">
            {{ $t("project_settings.usage_limits.current_plan") }}
          </h3>
          <p class="text-sm text-muted-foreground">
            {{ $t("project_settings.usage_limits.current_plan_description") }}
          </p>
        </div>
        <Badge variant="secondary" class="capitalize">
          {{ usageLimits.plan.name || usageLimits.plan.key }}
        </Badge>
      </div>
    </section>

    <section>
      <h3 class="text-lg font-semibold mb-2">
        {{ $t("project_settings.usage_limits.project_limits") }}
      </h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ $t("project_settings.usage_limits.project_limits_description") }}
      </p>

      <div class="space-y-3">
        <div
          v-for="row in projectRows"
          :key="row.key"
          class="rounded-lg border border-border bg-background p-4"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0">
              <h4 class="font-medium">{{ row.label }}</h4>
              <p class="text-sm text-muted-foreground">{{ row.description }}</p>
            </div>
            <Badge :variant="statusFor(row.bucket).variant">
              {{ statusFor(row.bucket).label }}
            </Badge>
          </div>

          <div class="mt-4 flex justify-between gap-4 text-sm">
            <span class="font-medium tabular-nums">
              {{ formatValue(row.bucket.used, row.format) }}
            </span>
            <span class="text-muted-foreground tabular-nums">
              {{ formatLimit(row.bucket, row.format) }}
            </span>
          </div>
          <Progress :model-value="usagePercent(row.bucket)" class="mt-2" />
        </div>
      </div>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
        <div
          v-for="item in itemBreakdown"
          :key="item.label"
          class="rounded-lg border border-border bg-muted/20 p-3"
        >
          <div class="text-xs text-muted-foreground">{{ item.label }}</div>
          <div class="mt-1 text-lg font-semibold tabular-nums">
            {{ item.value }}
          </div>
        </div>
      </div>
    </section>

    <Separator />

    <section>
      <h3 class="text-lg font-semibold mb-2">
        {{ $t("project_settings.usage_limits.workspace_limits") }}
      </h3>
      <p class="text-sm text-muted-foreground mb-4">
        {{ $t("project_settings.usage_limits.workspace_limits_description") }}
      </p>

      <div class="space-y-3">
        <div
          v-for="row in workspaceRows"
          :key="row.key"
          class="rounded-lg border border-border bg-background p-4"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0">
              <h4 class="font-medium">{{ row.label }}</h4>
              <p class="text-sm text-muted-foreground">{{ row.description }}</p>
            </div>
            <Badge :variant="statusFor(row.bucket).variant">
              {{ statusFor(row.bucket).label }}
            </Badge>
          </div>

          <div class="mt-4 flex justify-between gap-4 text-sm">
            <span class="font-medium tabular-nums">
              {{ formatValue(row.bucket.used, row.format) }}
            </span>
            <span class="text-muted-foreground tabular-nums">
              {{ formatLimit(row.bucket, row.format) }}
            </span>
          </div>
          <Progress :model-value="usagePercent(row.bucket)" class="mt-2" />

          <p v-if="row.key === 'storageBytes'" class="mt-3 text-xs text-muted-foreground">
            {{
              $t("project_settings.usage_limits.project_storage_note", {
                storage: formatBytes(usageLimits.storage.projectBytes),
                assets: usageLimits.storage.assetCount,
              })
            }}
          </p>
        </div>
      </div>
    </section>
  </div>
</template>
