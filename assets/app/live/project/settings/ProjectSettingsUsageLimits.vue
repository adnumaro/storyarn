<script setup lang="ts">
import { Archive, Clock3, Image, Link2 } from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Progress } from "@components/ui/progress";
import { Separator } from "@components/ui/separator";
import {
  formatBasisPoints,
  formatBytes,
  storagePercentage,
  type ByteCount,
  type WorkspaceStorageUsage,
} from "@shared/utils/storage-accounting";

interface CountUsageBucket {
  used: number;
  limit: number | null;
}

interface StorageUsageBucket {
  used: ByteCount;
  limit: ByteCount | null;
}

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
  workspace: {
    projects: CountUsageBucket;
    members: CountUsageBucket;
    storageBytes: StorageUsageBucket;
  };
  itemBreakdown: {
    sheets: number;
    flows: number;
    scenes: number;
    flowNodes: number;
  };
  storage: {
    projectAccountedBytes: ByteCount;
    projectAssetBytes: ByteCount;
    projectSnapshotBytes: ByteCount;
    projectReservationBytes: ByteCount;
    assetCount: number;
    workspace: WorkspaceStorageUsage;
  };
}

type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

interface LimitRowBase {
  key: string;
  label: string;
  description: string;
}

type LimitRow =
  | (LimitRowBase & { bucket: CountUsageBucket; format: "count" })
  | (LimitRowBase & { bucket: StorageUsageBucket; format: "bytes" });

const { usageLimits } = defineProps<{
  usageLimits: UsageLimits;
}>();

const { locale, t } = useI18n();

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

function usageRatio(bucket: CountUsageBucket) {
  if (bucket.limit === null || bucket.limit <= 0) return 0;
  return bucket.used / bucket.limit;
}

function countHasDeterminateProgress(row: LimitRow) {
  return row.format === "count" && row.bucket.limit !== null && row.bucket.limit > 0;
}

function usagePercent(row: LimitRow) {
  if (row.format === "bytes") {
    return workspaceStoragePercentage.value.progressPercent;
  }

  if (row.bucket.limit === null || row.bucket.limit <= 0) return 0;
  return Math.min(Math.round(usageRatio(row.bucket) * 100), 100);
}

function statusFor(row: LimitRow): { label: string; variant: BadgeVariant } {
  if (row.format === "bytes") return storageStatus.value;

  if (row.bucket.limit === null) {
    return { label: t("project_settings.usage_limits.status.unknown"), variant: "secondary" };
  }

  if (row.bucket.limit <= 0) {
    return {
      label: t("project_settings.usage_limits.status.limit_reached"),
      variant: "destructive",
    };
  }

  const ratio = usageRatio(row.bucket);

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

function formatCount(value: number) {
  return new Intl.NumberFormat(locale.value).format(value);
}

function formatUsed(row: LimitRow) {
  return row.format === "bytes"
    ? formatBytes(row.bucket.used, locale.value)
    : formatCount(row.bucket.used);
}

function formatLimit(row: LimitRow) {
  if (row.format === "bytes") {
    if (usageLimits.storage.workspace.limitKind === "unlimited") {
      return t("project_settings.usage_limits.status.no_limit");
    }

    if (usageLimits.storage.workspace.limitKind === "unknown") {
      return t("project_settings.usage_limits.status.unknown");
    }

    return row.bucket.limit !== null
      ? formatBytes(row.bucket.limit, locale.value)
      : t("project_settings.usage_limits.status.unknown");
  }

  return row.bucket.limit !== null
    ? formatCount(row.bucket.limit)
    : t("project_settings.usage_limits.status.unknown");
}

const workspaceStoragePercentage = computed(() =>
  storagePercentage(
    usageLimits.storage.workspace.totalAccountedBytes,
    usageLimits.storage.workspace.limitBytes,
    usageLimits.storage.workspace.limitKind,
  ),
);

const workspaceStorageHasDeterminateProgress = computed(
  () =>
    workspaceStoragePercentage.value.basisPoints !== null &&
    workspaceStoragePercentage.value.state !== "zero",
);

const storageStatus = computed<{ label: string; variant: BadgeVariant }>(() => {
  const percentage = workspaceStoragePercentage.value;

  if (percentage.state === "unlimited") {
    return { label: t("project_settings.usage_limits.status.no_limit"), variant: "outline" };
  }

  if (percentage.state === "unknown") {
    return { label: t("project_settings.usage_limits.status.unknown"), variant: "secondary" };
  }

  if (percentage.state === "zero") {
    return {
      label: t("project_settings.usage_limits.status.zero_capacity"),
      variant: "destructive",
    };
  }

  if (
    percentage.state === "over_limit" ||
    (percentage.basisPoints !== null && percentage.basisPoints >= 10_000n)
  ) {
    return {
      label: t("project_settings.usage_limits.status.limit_reached"),
      variant: "destructive",
    };
  }

  if (percentage.basisPoints !== null && percentage.basisPoints >= 8_000n) {
    return {
      label: t("project_settings.usage_limits.status.near_limit"),
      variant: "secondary",
    };
  }

  return { label: t("project_settings.usage_limits.status.available"), variant: "outline" };
});

const workspaceStoragePercentLabel = computed(() => {
  const percentage = workspaceStoragePercentage.value;

  if (percentage.lessThanOneBasisPoint) {
    return t("project_settings.usage_limits.status.less_than_percent", {
      percent: formatBasisPoints(1n, locale.value),
    });
  }

  if (percentage.basisPoints !== null) {
    return formatBasisPoints(percentage.basisPoints, locale.value);
  }

  if (percentage.state === "over_limit") {
    return t("project_settings.usage_limits.status.over_limit");
  }

  return storageStatus.value.label;
});

function formattedRemainingStorage() {
  const storage = usageLimits.storage.workspace;

  if (storage.limitKind === "unlimited") {
    return t("project_settings.usage_limits.status.no_limit");
  }

  if (storage.limitKind === "unknown") {
    return t("project_settings.usage_limits.status.unknown");
  }

  return formatBytes(storage.remainingBytes, locale.value);
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
            <Badge
              :variant="statusFor(row).variant"
              :aria-label="
                $t('project_settings.usage_limits.accessibility.status', {
                  label: row.label,
                  status: statusFor(row).label,
                })
              "
            >
              {{ statusFor(row).label }}
            </Badge>
          </div>

          <div class="mt-4 flex justify-between gap-4 text-sm">
            <span class="font-medium tabular-nums">
              {{ formatUsed(row) }}
            </span>
            <span class="text-muted-foreground tabular-nums">
              {{ formatLimit(row) }}
            </span>
          </div>
          <Progress
            v-if="countHasDeterminateProgress(row)"
            :model-value="usagePercent(row)"
            class="mt-2"
            :aria-label="row.label"
          />
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
            {{ formatCount(item.value) }}
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
            <Badge
              :variant="statusFor(row).variant"
              :aria-label="
                $t('project_settings.usage_limits.accessibility.status', {
                  label: row.label,
                  status: statusFor(row).label,
                })
              "
            >
              {{ statusFor(row).label }}
            </Badge>
          </div>

          <div class="mt-4 flex justify-between gap-4 text-sm">
            <span class="font-medium tabular-nums">
              {{ formatUsed(row) }}
            </span>
            <span class="text-muted-foreground tabular-nums">
              {{ formatLimit(row) }}
            </span>
          </div>
          <Progress
            v-if="row.key === 'storageBytes' && workspaceStorageHasDeterminateProgress"
            data-testid="workspace-storage-progress"
            :model-value="usagePercent(row)"
            class="mt-2"
            :aria-label="
              $t('project_settings.usage_limits.storage_progress_label', {
                percent: workspaceStoragePercentLabel,
              })
            "
          />
          <Progress
            v-else-if="row.key !== 'storageBytes' && countHasDeterminateProgress(row)"
            :model-value="usagePercent(row)"
            class="mt-2"
            :aria-label="row.label"
          />

          <div v-if="row.key === 'storageBytes'" class="mt-5 space-y-4">
            <div class="grid gap-3 sm:grid-cols-3">
              <div class="rounded-md border border-border/70 bg-muted/25 p-3">
                <div class="text-xs text-muted-foreground">
                  {{ $t("project_settings.usage_limits.storage_summary.counted") }}
                </div>
                <div class="mt-1 font-semibold tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.totalAccountedBytes, locale) }}
                </div>
                <div class="mt-0.5 text-xs text-muted-foreground">
                  {{ workspaceStoragePercentLabel }}
                </div>
              </div>
              <div class="rounded-md border border-border/70 bg-muted/25 p-3">
                <div class="text-xs text-muted-foreground">
                  {{ $t("project_settings.usage_limits.storage_summary.remaining") }}
                </div>
                <div class="mt-1 font-semibold tabular-nums">
                  {{ formattedRemainingStorage() }}
                </div>
              </div>
              <div class="rounded-md border border-border/70 bg-muted/25 p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Clock3 class="size-3.5" aria-hidden="true" />
                  {{ $t("project_settings.usage_limits.storage_summary.reservations") }}
                </div>
                <div class="mt-1 font-semibold tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.activeReservationsBytes, locale) }}
                </div>
              </div>
            </div>

            <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
              <div class="rounded-md border border-border/60 p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Image class="size-3.5" aria-hidden="true" />
                  {{ $t("project_settings.usage_limits.storage_breakdown.current_assets") }}
                </div>
                <div class="mt-1 font-medium tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.currentAssetsBytes, locale) }}
                </div>
              </div>
              <div class="rounded-md border border-border/60 p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Archive class="size-3.5" aria-hidden="true" />
                  {{ $t("project_settings.usage_limits.storage_breakdown.full_snapshots") }}
                </div>
                <div class="mt-1 font-medium tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.fullSnapshotsBytes, locale) }}
                </div>
              </div>
              <div class="rounded-md border border-border/60 p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Link2 class="size-3.5" aria-hidden="true" />
                  {{ $t("project_settings.usage_limits.storage_breakdown.linked_snapshots") }}
                </div>
                <div class="mt-1 font-medium tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.linkedSnapshotsBytes, locale) }}
                </div>
              </div>
              <div class="rounded-md border border-border/60 p-3">
                <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Clock3 class="size-3.5" aria-hidden="true" />
                  {{ $t("project_settings.usage_limits.storage_breakdown.reservations") }}
                </div>
                <div class="mt-1 font-medium tabular-nums">
                  {{ formatBytes(usageLimits.storage.workspace.activeReservationsBytes, locale) }}
                </div>
              </div>
            </div>

            <p class="text-xs text-muted-foreground">
              {{
                $t("project_settings.usage_limits.project_storage_note", {
                  storage: formatBytes(usageLimits.storage.projectAccountedBytes, locale),
                  assetStorage: formatBytes(usageLimits.storage.projectAssetBytes, locale),
                  assets: formatCount(usageLimits.storage.assetCount),
                  snapshots: formatBytes(usageLimits.storage.projectSnapshotBytes, locale),
                  reservations: formatBytes(usageLimits.storage.projectReservationBytes, locale),
                })
              }}
            </p>
            <p class="text-xs text-muted-foreground">
              {{ $t("project_settings.usage_limits.storage_counted_note") }}
            </p>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
