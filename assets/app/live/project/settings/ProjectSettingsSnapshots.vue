<script setup lang="ts">
import {
  Archive,
  Clock3,
  Database,
  Download,
  FileJson2,
  HardDrive,
  Image,
  Link2,
} from "@lucide/vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Badge } from "@components/ui/badge";
import { Progress } from "@components/ui/progress";
import { Separator } from "@components/ui/separator";
import {
  formatBasisPoints,
  formatBytes,
  positiveByteCount,
  storagePercentage,
  type ByteCount,
  type WorkspaceStorageUsage,
} from "@shared/utils/storage-accounting";

type SnapshotMode = "full" | "linked";
type SnapshotLifecycle =
  | "pending"
  | "building"
  | "verifying"
  | "ready"
  | "failed"
  | "cancelled"
  | "deleting";
type SnapshotIntegrity = "unknown" | "verified" | "at_risk" | "missing" | "corrupt" | "incomplete";
type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

interface Snapshot {
  id: number;
  title?: string;
  description?: string;
  versionNumber: number;
  insertedAt: string;
  entityCounts?: Record<string, number>;
  createdByEmail?: string;
  mode: SnapshotMode | null;
  lifecycleStatus: SnapshotLifecycle | null;
  integrityStatus: SnapshotIntegrity | null;
  accountedSizeBytes: ByteCount | null;
  projectDataSizeBytes: ByteCount | null;
  metadataSizeBytes: ByteCount | null;
  assetBlobSizeBytes: ByteCount | null;
  assetCount: number | null;
  blobCount: number | null;
  activeReservationBytes: ByteCount;
  exportReservationBytes: ByteCount;
  accountingVersion: number | null;
  accountingMeasuredAt: string | null;
}

const { snapshots = [], storageUsage } = defineProps<{
  snapshots?: Snapshot[];
  storageUsage: WorkspaceStorageUsage;
}>();

const { locale, t } = useI18n();

function formatSnapshotDate(dateStr: string | undefined) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  return d.toLocaleDateString(locale.value, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "UTC",
    timeZoneName: "short",
  });
}

const workspacePercentage = computed(() =>
  storagePercentage(
    storageUsage.totalAccountedBytes,
    storageUsage.limitBytes,
    storageUsage.limitKind,
  ),
);

const workspacePercentLabel = computed(() => percentageLabel(workspacePercentage.value));

const workspaceHasDeterminateProgress = computed(
  () =>
    workspacePercentage.value.basisPoints !== null && workspacePercentage.value.state !== "zero",
);

function snapshotPercentage(snapshot: Snapshot) {
  if (snapshot.accountedSizeBytes === null) {
    return storagePercentage(null, storageUsage.limitBytes, storageUsage.limitKind);
  }

  return storagePercentage(
    snapshot.accountedSizeBytes,
    storageUsage.limitBytes,
    storageUsage.limitKind,
  );
}

function snapshotPercentLabel(snapshot: Snapshot) {
  return percentageLabel(snapshotPercentage(snapshot));
}

function percentageLabel(percentage: ReturnType<typeof storagePercentage>) {
  if (percentage.state === "zero") {
    return t("project_settings.snapshots.storage_status.zero_capacity");
  }

  if (percentage.lessThanOneBasisPoint) {
    return t("project_settings.snapshots.storage_status.less_than_percent", {
      percent: formatBasisPoints(1n, locale.value),
    });
  }

  if (percentage.basisPoints !== null) {
    return formatBasisPoints(percentage.basisPoints, locale.value);
  }

  switch (percentage.state) {
    case "unlimited":
      return t("project_settings.snapshots.storage_status.unlimited");
    case "over_limit":
      return t("project_settings.snapshots.storage_status.over_limit");
    default:
      return t("project_settings.snapshots.storage_status.unknown");
  }
}

function remainingStorageLabel() {
  if (storageUsage.limitKind === "unlimited") {
    return t("project_settings.snapshots.storage_status.unlimited");
  }

  if (storageUsage.limitKind === "unknown") {
    return t("project_settings.snapshots.storage_status.unknown");
  }

  return formatBytes(storageUsage.remainingBytes, locale.value);
}

function modeLabel(mode: SnapshotMode | null) {
  return t(`project_settings.snapshots.mode.${mode ?? "unknown"}`);
}

function lifecycleLabel(status: SnapshotLifecycle | null) {
  return t(`project_settings.snapshots.lifecycle.${status ?? "unknown"}`);
}

function integrityLabel(status: SnapshotIntegrity | null) {
  return t(`project_settings.snapshots.integrity.${status ?? "unknown"}`);
}

function lifecycleVariant(status: SnapshotLifecycle | null): BadgeVariant {
  if (status === "failed" || status === "cancelled") return "destructive";
  if (status === "ready") return "outline";
  return "secondary";
}

function integrityVariant(status: SnapshotIntegrity | null): BadgeVariant {
  if (status === "verified") return "default";
  if (status === "unknown") return "secondary";
  if (!status) return "secondary";
  return "destructive";
}

function formatCount(value: number | null) {
  return value === null ? "\u2014" : new Intl.NumberFormat(locale.value).format(value);
}

function accessibleMeasurement(label: string, value: ByteCount | null) {
  return t("project_settings.snapshots.accessibility.measurement", {
    label,
    value: formatBytes(value, locale.value),
  });
}

function entityCountLabel(type: string, count: number) {
  return t(`project_settings.snapshots.entity_types.${type}`, { count: formatCount(count) }, count);
}

function accountingMeasurementLabel(snapshot: Snapshot) {
  if (snapshot.accountingVersion === null || !snapshot.accountingMeasuredAt) return null;

  return t("project_settings.snapshots.measurements.measured", {
    version: snapshot.accountingVersion,
    date: formatSnapshotDate(snapshot.accountingMeasuredAt),
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

function sortedEntityCounts(counts: Record<string, number> | undefined) {
  if (!counts) return [];
  return entityTypeOrder
    .filter((type) => counts[type] && counts[type] > 0)
    .map((type) => ({ type, count: counts[type] }));
}
</script>

<template>
  <div class="space-y-6">
    <section aria-labelledby="snapshot-storage-heading">
      <div class="rounded-xl border border-border bg-muted/25 p-4 sm:p-5">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <div class="flex items-center gap-2">
              <HardDrive class="size-4 text-primary" aria-hidden="true" />
              <h3 id="snapshot-storage-heading" class="font-semibold">
                {{ $t("project_settings.snapshots.storage_heading") }}
              </h3>
            </div>
            <p class="mt-1 text-sm text-muted-foreground">
              {{ $t("project_settings.snapshots.storage_description") }}
            </p>
          </div>
          <Badge
            variant="outline"
            class="w-fit tabular-nums"
            :aria-label="
              $t('project_settings.snapshots.accessibility.workspace_percentage', {
                percent: workspacePercentLabel,
              })
            "
          >
            {{ workspacePercentLabel }}
          </Badge>
        </div>

        <div class="mt-4 flex items-baseline justify-between gap-4 text-sm">
          <span
            class="font-semibold tabular-nums"
            :aria-label="
              accessibleMeasurement(
                $t('project_settings.snapshots.storage_heading'),
                storageUsage.totalAccountedBytes,
              )
            "
          >
            {{ formatBytes(storageUsage.totalAccountedBytes, locale) }}
          </span>
          <span class="text-muted-foreground tabular-nums">
            <template v-if="storageUsage.limitKind === 'limited'">
              {{ formatBytes(storageUsage.limitBytes, locale) }}
            </template>
            <template v-else>
              {{ workspacePercentLabel }}
            </template>
          </span>
        </div>
        <Progress
          v-if="workspaceHasDeterminateProgress"
          data-testid="workspace-storage-progress"
          :model-value="workspacePercentage.progressPercent"
          class="mt-2"
          :aria-label="
            $t('project_settings.snapshots.storage_progress_label', {
              percent: workspacePercentLabel,
            })
          "
        />

        <div class="mt-4 grid gap-2 sm:grid-cols-3">
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Image class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.current_assets") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.currentAssetsBytes, locale) }}
            </div>
          </div>
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Archive class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.full_snapshots") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.fullSnapshotsBytes, locale) }}
            </div>
          </div>
          <div class="rounded-md border border-border/60 bg-background/70 p-3">
            <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Link2 class="size-3.5" aria-hidden="true" />
              {{ $t("project_settings.snapshots.storage_breakdown.linked_snapshots") }}
            </div>
            <div class="mt-1 font-medium tabular-nums">
              {{ formatBytes(storageUsage.linkedSnapshotsBytes, locale) }}
            </div>
          </div>
        </div>

        <div class="mt-3 grid gap-2 text-xs text-muted-foreground sm:grid-cols-2">
          <div class="flex items-center gap-1.5 rounded-md bg-background/55 px-3 py-2">
            <Database class="size-3.5" aria-hidden="true" />
            <span>{{ $t("project_settings.snapshots.storage_remaining") }}</span>
            <span class="ml-auto font-medium text-foreground tabular-nums">
              {{ remainingStorageLabel() }}
            </span>
          </div>
          <div class="flex items-center gap-1.5 rounded-md bg-background/55 px-3 py-2">
            <Clock3 class="size-3.5" aria-hidden="true" />
            <span>{{ $t("project_settings.snapshots.storage_reservations") }}</span>
            <span class="ml-auto font-medium text-foreground tabular-nums">
              {{ formatBytes(storageUsage.activeReservationsBytes, locale) }}
            </span>
          </div>
        </div>

        <p class="mt-3 text-xs text-muted-foreground">
          {{ $t("project_settings.snapshots.storage_counted_note") }}
        </p>
      </div>
    </section>

    <Separator />

    <!-- Snapshot List -->
    <section>
      <h3 class="text-lg font-semibold mb-4">
        {{ $t("project_settings.snapshots.snapshots_heading") }}
      </h3>

      <!-- Empty state -->
      <div v-if="snapshots.length === 0" class="text-center py-12">
        <Archive class="size-12 mx-auto mb-4 text-muted-foreground/30" />
        <p class="font-medium text-muted-foreground/70">
          {{ $t("project_settings.snapshots.empty_title") }}
        </p>
        <p class="text-sm text-muted-foreground/50 mt-1">
          {{ $t("project_settings.snapshots.empty_description") }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="snapshot in snapshots"
          :key="snapshot.id"
          class="rounded-lg border border-border bg-muted/30 p-4"
        >
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div class="flex-1 min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <Badge variant="secondary" class="text-xs">
                  v{{ formatCount(snapshot.versionNumber) }}
                </Badge>
                <Badge
                  variant="outline"
                  class="text-xs"
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.mode', {
                      status: modeLabel(snapshot.mode),
                    })
                  "
                >
                  {{ modeLabel(snapshot.mode) }}
                </Badge>
                <Badge
                  :variant="lifecycleVariant(snapshot.lifecycleStatus)"
                  class="text-xs"
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.lifecycle', {
                      status: lifecycleLabel(snapshot.lifecycleStatus),
                    })
                  "
                >
                  {{ lifecycleLabel(snapshot.lifecycleStatus) }}
                </Badge>
                <Badge
                  :variant="integrityVariant(snapshot.integrityStatus)"
                  class="text-xs"
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.integrity', {
                      status: integrityLabel(snapshot.integrityStatus),
                    })
                  "
                >
                  {{ integrityLabel(snapshot.integrityStatus) }}
                </Badge>
                <span class="font-medium truncate">
                  {{ snapshot.title || $t("project_settings.snapshots.untitled") }}
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
                <span
                  class="font-medium text-foreground/75 tabular-nums"
                  :aria-label="
                    accessibleMeasurement(
                      $t('project_settings.snapshots.measurements.accounted_size'),
                      snapshot.accountedSizeBytes,
                    )
                  "
                >
                  {{ formatBytes(snapshot.accountedSizeBytes, locale) }}
                </span>
                <span
                  :aria-label="
                    $t('project_settings.snapshots.accessibility.snapshot_percentage', {
                      percent: snapshotPercentLabel(snapshot),
                    })
                  "
                >
                  {{
                    $t("project_settings.snapshots.accessibility.snapshot_percentage", {
                      percent: snapshotPercentLabel(snapshot),
                    })
                  }}
                </span>
                <span v-for="ec in sortedEntityCounts(snapshot.entityCounts)" :key="ec.type">
                  {{ entityCountLabel(ec.type, ec.count) }}
                </span>
              </div>

              <div
                class="mt-3 grid gap-2 rounded-lg border border-border/60 bg-background/60 p-3 sm:grid-cols-3"
              >
                <div>
                  <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <FileJson2 class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.measurements.project_data") }}
                  </div>
                  <div class="mt-1 text-sm font-medium tabular-nums">
                    {{ formatBytes(snapshot.projectDataSizeBytes, locale) }}
                  </div>
                </div>
                <div>
                  <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <Database class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.measurements.metadata") }}
                  </div>
                  <div class="mt-1 text-sm font-medium tabular-nums">
                    {{ formatBytes(snapshot.metadataSizeBytes, locale) }}
                  </div>
                </div>
                <div>
                  <div class="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <HardDrive class="size-3.5" aria-hidden="true" />
                    {{ $t("project_settings.snapshots.measurements.unique_blobs") }}
                  </div>
                  <div class="mt-1 text-sm font-medium tabular-nums">
                    {{ formatBytes(snapshot.assetBlobSizeBytes, locale) }}
                  </div>
                </div>
              </div>
              <p class="mt-2 text-xs text-muted-foreground">
                {{
                  $t("project_settings.snapshots.measurements.inventory", {
                    assets: formatCount(snapshot.assetCount),
                    blobs: formatCount(snapshot.blobCount),
                  })
                }}
              </p>
              <p
                v-if="accountingMeasurementLabel(snapshot)"
                class="mt-1 text-xs text-muted-foreground"
              >
                {{ accountingMeasurementLabel(snapshot) }}
              </p>
              <div
                v-if="
                  positiveByteCount(snapshot.activeReservationBytes) ||
                  positiveByteCount(snapshot.exportReservationBytes)
                "
                class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground"
              >
                <span
                  v-if="positiveByteCount(snapshot.activeReservationBytes)"
                  class="inline-flex items-center gap-1.5"
                >
                  <Clock3 class="size-3.5" aria-hidden="true" />
                  {{
                    $t("project_settings.snapshots.measurements.active_reservation", {
                      storage: formatBytes(snapshot.activeReservationBytes, locale),
                    })
                  }}
                </span>
                <span
                  v-if="positiveByteCount(snapshot.exportReservationBytes)"
                  class="inline-flex items-center gap-1.5"
                >
                  <Download class="size-3.5" aria-hidden="true" />
                  {{
                    $t("project_settings.snapshots.measurements.export_reservation", {
                      storage: formatBytes(snapshot.exportReservationBytes, locale),
                    })
                  }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
